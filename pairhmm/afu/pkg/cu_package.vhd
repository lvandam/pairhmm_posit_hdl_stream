library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.psl.all;
  use work.dma_package.all;
  use work.wed.all;
  use work.pairhmm_package.all;
  use work.pe_package.all;
  use work.functions.all;

package cu_package is

  constant CU_MAX_CYCLES              : natural := PAIRHMM_MAX_SIZE / PE_DEPTH * 2 * PAIRHMM_MAX_SIZE;
  constant CU_CYCLE_BITS              : natural := log2(CU_MAX_CYCLES);
  constant CU_BATCH_CACHELINES        : natural := 1 + 2 * PAIRHMM_STRING_CACHELINES + PE_DEPTH * PAIRHMM_PROBS_CACHELINES;
  constant CU_BPS_PER_RAM_ADDR        : natural := DMA_DATA_WIDTH / (8 * PE_DEPTH);
  constant CU_RAM_ADDRS_PER_BATCH     : natural := PAIRHMM_MAX_SIZE / CU_BPS_PER_RAM_ADDR;
  constant CU_RESULT_SIZE             : natural := 4 * PE_DW;
  constant CU_BATCH_RESULT_CACHELINES : natural := 16 * CU_RESULT_SIZE / DMA_DATA_WIDTH;
  constant CU_CACHELINES_PER_PROB     : natural := PE_DEPTH * PE_DW * 8 / DMA_DATA_WIDTH;
  constant CU_BASES_PER_CACHELINE     : natural := DMA_DATA_WIDTH / (PE_DEPTH * 8);
----------------------------------------------------------------------------------------------------------------------- io

  type pairhmm_mmio_regs_in is record
    control   : std_logic_vector(PSL_MMIO_DATA_WIDTH - 1 downto 0);
    size      : std_logic_vector(PSL_MMIO_DATA_WIDTH - 1 downto 0);
  end record;

  type pairhmm_mmio_regs_out is record
    status    : std_logic_vector(PSL_MMIO_DATA_WIDTH - 1 downto 0); -- status
    reqs      : std_logic_vector(PSL_MMIO_DATA_WIDTH - 1 downto 0); -- requests to streaming framework
    reps      : std_logic_vector(PSL_MMIO_DATA_WIDTH - 1 downto 0); -- replies from streaming framework
    fifo      : std_logic_vector(PSL_MMIO_DATA_WIDTH - 1 downto 0); -- fifo status
    fifo_rvs  : std_logic_vector(PSL_MMIO_DATA_WIDTH - 1 downto 0); -- fifo read valids
    fifo_was  : std_logic_vector(PSL_MMIO_DATA_WIDTH - 1 downto 0); -- fifo write acks
  end record;

  type pairhmm_mmio_regs is record
    i         : pairhmm_mmio_regs_in;
    o         : pairhmm_mmio_regs_out;
  end record;

  type cu_in is record
    cr        : cr_in;
    start     : std_logic;
    wed       : wed_type;
    id        : unsigned(DMA_ID_WIDTH - 1 downto 0);
    read      : dma_read_response;
    write     : dma_write_response;
    mmio_regs : pairhmm_mmio_regs_in;
  end record;

  type cu_out is record
    done      : std_logic;
    read      : dma_read_request;
    write     : dma_write_request;
    mmio_regs : pairhmm_mmio_regs_out;
  end record;

----------------------------------------------------------------------------------------------------------------------- internals

  type fifo_controls is record
    rd_en       : std_logic;
    valid       : std_logic;

    wr_en       : std_logic;
    wr_ack      : std_logic;

    empty       : std_logic;
    full        : std_logic;

    overflow    : std_logic;
    underflow   : std_logic;

    rst         : std_logic;
    rd_rst      : std_logic;
    wr_rst      : std_logic;
  end record;

  type pfifo_item is record
    din         : std_logic_vector(DMA_DATA_WIDTH-1 downto 0);
    dout        : std_logic_vector(PAIRHMM_BITS_PER_PROB - 1 downto 0);
    c           : fifo_controls;
  end record;
  
  type outfifo_item is record
    din         : std_logic_vector(127 downto 0);
    dout        : std_logic_vector(DMA_DATA_WIDTH - 1 downto 0);
    c           : fifo_controls;
  end record;
  
  type fbfifo_item is record
    din         : std_logic_vector(386 downto 0);
    dout        : std_logic_vector(386 downto 0);
    c           : fifo_controls;
  end record;

  type ram_item is record
    clka        : std_logic;
    wea         : std_logic;
    addra       : unsigned(6 downto 0);
    dina        : std_logic_vector(383 downto 0);
    clkb        : std_logic;
    addrb       : unsigned(9 downto 0);
    doutb       : std_logic_vector(3 * PE_DEPTH - 1 downto 0);
  end record;

  type cu_state is (
    idle,
    request_init,
    load_init,
    loadnextinit,
    request_data,
    loadx,
    loady,
    streamps,
    launch,
    done
  );
  
  type cu_inits is record 
    loaded      : std_logic;
    batch_bytes : unsigned(31 downto 0);
    x_size      : unsigned(31 downto 0);
    x_padded    : unsigned(31 downto 0);
    x_bppadded  : unsigned(31 downto 0);
    y_size      : unsigned(31 downto 0);
    y_padded    : unsigned(31 downto 0);
  end record;

  type initial_array_type is array (0 to PE_DEPTH - 1) of prob;

  -- To distribute data to FIFO's
  type readdata_array is array (0 to 1) of std_logic_vector(DMA_DATA_WIDTH-1 downto 0);

  type cu_int is record
    state                 : cu_state;
    wed                   : wed_type;
    o                     : cu_out;

    inits                 : cu_inits;
    initial_array         : initial_array_type;
    sched                 : cu_inits;
    sched_array           : initial_array_type;

    y_reads               : unsigned(15 downto 0);
    x_reads               : unsigned(15 downto 0);
    p_reads               : unsigned(15 downto 0);

    hapl_addr             : unsigned( 6 downto 0);
    hapl_addr1            : unsigned( 6 downto 0);
    hapl_wren             : std_logic;
    hapl_data             : std_logic_vector(DMA_DATA_WIDTH - 1 downto 0);
    read_addr             : unsigned( 6 downto 0);
    read_addr1            : unsigned( 6 downto 0);
    read_wren             : std_logic;
    read_data             : std_logic_vector(DMA_DATA_WIDTH - 1 downto 0);
    ram                   : std_logic;

    pair                  : unsigned(PE_DEPTH_BITS-1 downto 0);
    filled                : std_logic;
    fifos_rst             : std_logic;

    outfifo_rd            : std_logic;

    p_fifo_en             : std_logic;
    p_fifo_en1            : std_logic;
    p_fifo_en2            : std_logic;
    
    p_fifodata            : readdata_array;
    
    resultcachelines      : unsigned(31 downto 0);
    
  end record;

  type cu_sched_state is (
    idle,
    startup,
    processing,
    empty_fifos,
    done
  );

  type cu_sched is record
    pairhmm_rst           : std_logic;                                        -- Reset

    state                 : cu_sched_state;                                   -- State of the scheduler process
    cycle                 : unsigned(CU_CYCLE_BITS-1 downto 0);               -- This must be able to hold up to PAIRHMM_MAX_SIZE / PE_DEPTH * 2 * PAIRHMM_MAX_SIZE-1
    basepair              : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0);        -- This must be able to hold up to PAIRHMM_MAX_SIZE-1 but is 1 larger to compare to size array values
    element               : unsigned(log2e(PAIRHMM_NUM_PES) downto 0);         -- This must be able to hold PAIRHMM_NUM_PES-1
    schedule              : unsigned(PE_DEPTH_BITS-1 downto 0);               -- To hold the pair that is currently scheduled
    supercolumn           : unsigned(log2e(PAIRHMM_MAX_SIZE / PAIRHMM_NUM_PES) downto 0);  -- To keep track in which group of columns we are

    fifo_rd_en            : std_logic;
    fifo_reads            : unsigned(log2e(PAIRHMM_MAX_SIZE*PE_DEPTH) downto 0);  -- To keep track on howmany values were read from the fifo's

    valid                 : std_logic;                                        -- Valid bit for the PairHMM core
    cell                  : pe_cell_type;                                     -- State of the cell for this bunch of data

    feedback              : std_logic;                                        -- To select the feedback FIFO as PairHMM core input
    feedback_rd_en        : std_logic;                                        -- Read enable for the feedback FIFO
    feedback_rd_en1       : std_logic;                                        -- Read enable for the feedback FIFO
    feedback_wr_en        : std_logic;                                        -- Write enable for the feedback FIFO
    feedback_rst          : std_logic;                                        -- Feedback FIFO reset
    output_en             : std_logic;                                        -- To enable the

    sizey                 : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0);        -- To keep track of howmany bp's each pair still has to process in y direction
    sizey1                : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0);        -- To keep track of howmany bp's each pair still has to process in y direction
    sizex                 : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0);        -- To keep track of howmany bp's each pair still has to process in x direction
    sizexp                : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0);        -- To keep track of howmany bp's each pair still has to process in x direction (padded value)

    ram                   : std_logic;                                        -- To keep track of if we're using the top or bottom half of the RAM
    startflag             : std_logic;                                        -- To keep track of if we just started up a new pair

    pe_first              : pe_in;

    ybus_addr             : unsigned(log2e(PAIRHMM_NUM_PES) downto 0);
    ybus_addr1            : unsigned(log2e(PAIRHMM_NUM_PES) downto 0);
    ybus_en               : std_logic;
    ybus_en1              : std_logic;
    
    core_schedule         : unsigned(PE_DEPTH_BITS-1 downto 0);
    
    initial_array          : initial_array_type;
  end record;

  constant cu_sched_empty : cu_sched := (
    state                 => idle,
    cycle                 => (others => '0'),
    basepair              => (others => '0'),
    element               => (others => '0'),
    schedule              => (others => '0'),
    supercolumn           => (others => '0'),
    fifo_rd_en            => '0',
    valid                 => '0',
    cell                  => PE_NORMAL,
    pairhmm_rst           => '1',
    feedback              => '0',
    feedback_rd_en        => '0',
    feedback_rd_en1       => '0',
    feedback_wr_en        => '0',
    feedback_rst          => '1',
    output_en             => '0',
    sizey                 => (others => '0'),
    sizey1                => (others => '0'),
    sizex                 => (others => '0'),
    sizexp                => (others => '0'),
    fifo_reads            => (others => '0'),
    ram                   => '1',
    startflag             => '1',
    pe_first              => pe_in_empty,
    ybus_addr             => (others => '0'),
    ybus_addr1            => (others => '0'),
    ybus_en               => '0',
    ybus_en1              => '0',
    core_schedule         => (others => '0'),
    initial_array         => (others => (others => '0'))
  );

  constant CYCLE_ZERO     : unsigned(CU_CYCLE_BITS-1 downto 0) := u(0,CU_CYCLE_BITS);
  constant CYCLE_LAST     : unsigned(CU_CYCLE_BITS-1 downto 0) := u(PAIRHMM_NUM_PES - 1, CU_CYCLE_BITS);

  type cu_ext is record
    pairhmm_cr            : cr_in;
    pairhmm               : pairhmm_item;
    pairhmm_in            : pe_in;
    pfifo                 : pfifo_item;
    outfifo               : outfifo_item;
    fbfifo                : fbfifo_item;
    haplram               : ram_item;
    readram               : ram_item;
    fbpairhmm             : pe_in;
    outdata               : std_logic_vector(DMA_DATA_WIDTH-1 downto 0);
    clk_kernel            : std_logic;

  end record;

  procedure cu_reset (signal r : inout cu_int);

  component asym_ram is
    port (
      clka    : in  std_logic;
      wea     : in  std_logic;
      addra   : in  unsigned(6 downto 0);
      dina    : in  std_logic_vector(383 downto 0);
      clkb    : in  std_logic;
      addrb   : in  unsigned(9 downto 0);
      doutb   : out std_logic_vector(3 * PE_DEPTH - 1 downto 0)
    );
  end component;

end package cu_package;

package body cu_package is

  procedure cu_reset (signal r : inout cu_int) is
  begin
    r.state                 <= idle;
    r.o.done                <= '0';

    r.o.mmio_regs.status    <= (others => '0');
    r.o.mmio_regs.reqs      <= (others => '0');
    r.o.mmio_regs.reps      <= (others => '0');
    r.o.mmio_regs.fifo      <= (others => '0');
    r.o.mmio_regs.fifo_rvs  <= (others => '0');
    r.o.mmio_regs.fifo_was  <= (others => '0');

    r.x_reads               <= (others => '0');
    r.y_reads               <= (others => '0');

    r.hapl_addr             <= (others => '0');
    r.hapl_wren             <= '0';
    r.read_addr             <= (others => '0');
    r.read_wren             <= '0';

    r.p_reads               <= (others => '0');
    r.pair                  <= (others => '0');

    r.filled                <= '0';
    r.fifos_rst             <= '1';

    r.p_fifo_en             <= '0';
    
    r.ram                   <= '1';
    
  end procedure cu_reset;

end package body cu_package;
