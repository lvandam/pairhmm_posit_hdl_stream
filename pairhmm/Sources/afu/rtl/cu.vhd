library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.functions.all;
use work.psl.all;
use work.cu_package.all;
use work.dma_package.all;
use work.pairhmm_package.all;
use work.pe_package.all;

entity cu is
  port (
    i : in  cu_in;
    o : out cu_out
    );
end entity cu;

architecture logic of cu is
  signal q, r   : cu_int;
  signal re     : cu_ext;
  signal qs, rs : cu_sched := cu_sched_empty;

  signal if_rv : unsigned(31 downto 0) := (others => '0');
  signal of_wa : unsigned(31 downto 0) := (others => '0');

  component probabilities_fifo
    port (
      rst       : in  std_logic;
      wr_clk    : in  std_logic;
      rd_clk    : in  std_logic;
      din       : in  std_logic_vector(1023 downto 0);
      wr_en     : in  std_logic;
      rd_en     : in  std_logic;
      dout      : out std_logic_vector(255 downto 0);
      full      : out std_logic;
      wr_ack    : out std_logic;
      overflow  : out std_logic;
      empty     : out std_logic;
      valid     : out std_logic;
      underflow : out std_logic
      );
  end component;

  component kernel_to_streaming_fifo
    port (
      wr_clk    : in  std_logic;
      rd_clk    : in  std_logic;
      din       : in  std_logic_vector(127 downto 0);
      wr_en     : in  std_logic;
      rd_en     : in  std_logic;
      dout      : out std_logic_vector(1023 downto 0);
      full      : out std_logic;
      wr_ack    : out std_logic;
      overflow  : out std_logic;
      empty     : out std_logic;
      valid     : out std_logic;
      underflow : out std_logic
      );
  end component;

  component feedback_fifo
    port (
      clk       : in  std_logic;
      srst      : in  std_logic;
      din       : in  std_logic_vector(386 downto 0);
      wr_en     : in  std_logic;
      rd_en     : in  std_logic;
      dout      : out std_logic_vector(386 downto 0);
      full      : out std_logic;
      wr_ack    : out std_logic;
      overflow  : out std_logic;
      empty     : out std_logic;
      valid     : out std_logic;
      underflow : out std_logic
      );
  end component;

  component psl_to_kernel
    port
      (
        clk_kernel : out std_logic;
        clk_psl    : in  std_logic
        );
  end component;

begin

---------------------------------------------------------------------------------------------------
--    ____        _       _       _                     _
--   |  _ \      | |     | |     | |                   | |
--   | |_) | __ _| |_ ___| |__   | |     ___   __ _  __| | ___ _ __
--   |  _ < / _` | __/ __| '_ \  | |    / _ \ / _` |/ _` |/ _ \ '__|
--   | |_) | (_| | || (__| | | | | |___| (_) | (_| | (_| |  __/ |
--   |____/ \__,_|\__\___|_| |_| |______\___/ \__,_|\__,_|\___|_|
---------------------------------------------------------------------------------------------------
  loader_comb : process(all)
    variable v : cu_int;
    variable t : std_logic;
  begin
--------------------------------------------------------------------------------------------------- default assignments
    v                       := r;
    v.o.read.valid          := '0';
    v.o.write.request.valid := '0';
    v.o.write.data.valid    := '0';

    v.read_wren := '0';
    v.hapl_wren := '0';
    v.p_fifo_en := '0';

    v.outfifo_rd := '0';
--------------------------------------------------------------------------------------------------- state machine
    case r.state is
      -- Idle state, to wait until the WED has been loaded.
      when idle =>
        -- Reset input FIFO when idle.
        v.fifos_rst := '1';

        -- When start signal is received:
        if i.start then
          v.state            := load_init;
          v.wed              := i.wed;
          v.resultcachelines := u(idx(i.wed.batches) * CU_BATCH_RESULT_CACHELINES, 32);
          v.o.done           := '0';
          v.fifos_rst        := '0';

          -- Get the initial values for the first batch
          read_cacheline(v.o.read, i.wed.source);
          v.wed.source := i.wed.source + PSL_CACHELINE_SIZE;
        end if;

      -- State to register the initial values of the first row of D
      when load_init =>
        if i.read.valid = '1' then
          for K in 0 to PE_DEPTH - 1 loop
            v.initial_array(K) := i.read.data((K+1) * PE_DW -1 downto K * PE_DW);
          end loop;

          v.inits.batch_bytes := u(i.read.data(543 downto 512));
          v.inits.x_size      := u(i.read.data(575 downto 544));
          v.inits.x_padded    := u(i.read.data(607 downto 576));
          v.inits.y_size      := u(i.read.data(639 downto 608));
          v.inits.y_padded    := u(i.read.data(671 downto 640));
          v.inits.x_bppadded  := u(i.read.data(703 downto 672));

          v.state := request_data;
        end if;

      -- Request all data
      when request_data =>
        -- Reset all counters etc...
        v.x_reads := (others => '0');
        v.y_reads := (others => '0');
        v.p_reads := (others => '0');
        v.pair    := (others => '0');
        v.filled  := '0';

        read_bytes(v.o.read, r.wed.source, v.inits.batch_bytes(DMA_SIZE_WIDTH-1 downto 0));
        v.wed.source := r.wed.source + v.inits.batch_bytes;
        v.state      := loadx;

        -- Each pair gets a quarter of a cacheline to put the result in
        write_cachelines(v.o.write.request, r.wed.destination, CU_BATCH_RESULT_CACHELINES);
        v.wed.destination := r.wed.destination + CU_BATCH_RESULT_CACHELINES * PSL_CACHELINE_SIZE;

        -- Determine RAM location and flip RAM bit
        v.ram := not(r.ram);

        v.read_addr := u(idx(u(v.ram)) * CU_RAM_ADDRS_PER_BATCH, 7);
        v.hapl_addr := u(idx(u(v.ram)) * CU_RAM_ADDRS_PER_BATCH, 7);



      -- Load the values for the read X
      when loadx =>

        -- Store the bases of the read in the RAM
        if i.read.valid = '1' then
          v.x_reads   := r.x_reads + 1;
          v.read_addr := r.read_addr + 1;
          v.read_wren := '1';
          v.read_data := i.read.data;
        end if;

        -- If all (padded) bases of all reads are completely loaded,
        -- go to the next state to load the haplotypes
        if v.x_reads = v.inits.x_bppadded / CU_BASES_PER_CACHELINE then
          v.state := loady;
        end if;

      -- Load the values for the haplotype Y
      when loady =>
        -- Store the bases of the haplotype in the RAM
        if i.read.valid = '1' then
          v.y_reads   := r.y_reads + 1;
          v.hapl_addr := r.hapl_addr + 1;
          v.hapl_wren := '1';
          v.hapl_data := i.read.data;
        end if;

        -- If all bases of all haplotypes are completely loaded,
        -- go to the next state to load the probabilities
        if v.y_reads = v.inits.y_padded / CU_BASES_PER_CACHELINE then
          v.state := streamps;
        end if;

      -- State to stream in the probabilities
      when streamps =>
        -- Keep count of howmany cachelines have come in from the probabilities array.
        v.p_reads := r.p_reads + u(i.read.valid);

        -- Enable FIFO read if read is valid:
        v.p_fifo_en := i.read.valid;

        -- If we have loaded all the (padded) probabilities of the batch into the FIFO's
        if idx(v.p_reads) = v.inits.x_padded * CU_CACHELINES_PER_PROB then
          v.wed.batches := r.wed.batches - 1;
          v.state       := loadnextinit;
          v.p_reads     := (others => '0');
        end if;

        -- Copy the initials into the scheduler registers to make room for the new inits.
        v.sched       := v.inits;
        v.sched_array := v.initial_array;

      -- Load next batch information
      when loadnextinit =>
        if i.read.valid = '1' then
          for K in 0 to PE_DEPTH - 1 loop
            v.initial_array(K) := i.read.data((K+1) * PE_DW -1 downto K * PE_DW);
          end loop;

          v.inits.batch_bytes := u(i.read.data(543 downto 512));
          v.inits.x_size      := u(i.read.data(575 downto 544));
          v.inits.x_padded    := u(i.read.data(607 downto 576));
          v.inits.y_size      := u(i.read.data(639 downto 608));
          v.inits.y_padded    := u(i.read.data(671 downto 640));
          v.inits.x_bppadded  := u(i.read.data(703 downto 672));

          v.state := launch;
        end if;

      -- A new batch is ready to be started
      when launch =>
        -- Disable FIFO writes
        v.p_fifo_en := '0';

        -- If we told the scheduler to start a new batch
        if r.filled = '1' then
          -- And it's not idle anymore, it's busy with the new batch
          if rs.state /= idle then
            -- We can reset the filled bit to 0.
            v.filled := '0';
            -- If there is still work to do:
            if v.wed.batches /= 0 then
              -- We can start loading a new batch
              v.state := request_data;
            else
              v.state := done;
            end if;
          end if;
        end if;

        -- If the scheduler is idle
        if rs.state = idle and v.state /= done then
          -- We can signal the scheduler to start processing:
          v.filled := '1';
        end if;

      -- State where we wait for the scheduler to stop
      when done =>
        if rs.state = idle
          and r.resultcachelines = 0
        then
          v.state  := idle;
          v.o.done := '1';
        end if;

      when others => null;

    end case;

--------------------------------------------------------------------------------------------------- output fifo reads
    if (re.outfifo.c.valid = '1')       -- if there is a valid output
      and (i.write.full(0) = '0')       -- and the write buffer is not full
    then
      v.outfifo_rd := '1';
      write_data (v.o.write.data, re.outdata);
    end if;

    -- Keep track of howmany cachelines have been written back.
    if i.write.valid = '1' and r.state /= idle then
      v.resultcachelines := r.resultcachelines - 1;
    end if;

--------------------------------------------------------------------------------------------------- status register updates
    if r.o.mmio_regs.fifo = X"0000000000000000" then
      v.o.mmio_regs.fifo(0) := re.outfifo.c.underflow;
      v.o.mmio_regs.fifo(1) := re.outfifo.c.overflow;
    end if;

--------------------------------------------------------------------------------------------------- signals with latency
    -- These signals are either to match latencies of other components or  to cut critical paths up
    v.read_addr1 := r.read_addr;
    v.hapl_addr1 := r.hapl_addr;

    v.p_fifodata(0) := i.read.data;
    v.p_fifodata(1) := r.p_fifodata(0);

    v.p_fifo_en1 := r.p_fifo_en;

--------------------------------------------------------------------------------------------------- outputs
    -- drive input registers
    q <= v;
    -- outputs
    o <= r.o;
  end process;

--------------------------------------------------------------------------------------------------- registers
  loader_reg : process(i.cr)
  begin
    if rising_edge(i.cr.clk) then
      if i.cr.rst then
        cu_reset(r);
      else
        r <= q;
      end if;
    end if;
  end process;

--------------------------------------------------------------------------------------------------- Clock generator

  -- In case the kernel has to run slower due to timing constraints not being met, use this to lower the clock frequency
  kernel_clock_gen : psl_to_kernel port map (
    clk_psl    => i.cr.clk,
    clk_kernel => re.clk_kernel
    );

  -- Use this to keep everything in the same clock domain:
-- re.clk_kernel <= i.cr.clk;

---------------------------------------------------------------------------------------------------
--    ____                        _____            __  __
--   |  _ \                      |  __ \     /\   |  \/  |
--   | |_) | __ _ ___  ___  ___  | |__) |   /  \  | \  / |___
--   |  _ < / _` / __|/ _ \/ __| |  _  /   / /\ \ | |\/| / __|
--   | |_) | (_| \__ \  __/\__ \ | | \ \  / ____ \| |  | \__ \
--   |____/ \__,_|___/\___||___/ |_|  \_\/_/    \_\_|  |_|___/
---------------------------------------------------------------------------------------------------

  -- Connect clocks
  re.haplram.clka <= i.cr.clk;
  re.readram.clka <= i.cr.clk;
  re.haplram.clkb <= re.clk_kernel;
  re.readram.clkb <= re.clk_kernel;

  -- Convert data to basepair type
  convert_hapl : for K in 0 to PAIRHMM_BASEPAIRS_PER_CACHELINE-1 generate
    re.haplram.dina((K+1) * BP_SIZE - 1 downto K * BP_SIZE) <= slv8bpslv3(r.hapl_data((K + 1) * 8 - 1 downto (K * 8)));
  end generate;

  convert_read : for K in 0 to PAIRHMM_BASEPAIRS_PER_CACHELINE-1 generate
    re.readram.dina((K+1) * BP_SIZE - 1 downto K * BP_SIZE) <= slv8bpslv3(r.read_data((K + 1) * 8 - 1 downto (K * 8)));
  end generate;

  -- Connect write addresses
  re.haplram.addra <= r.hapl_addr1;
  re.readram.addra <= r.read_addr1;

  -- Connect write enables
  re.haplram.wea <= r.hapl_wren;
  re.readram.wea <= r.read_wren;

  -- Connect addresses to read from haplotype
  re.haplram.addrb <= u(idx(rs.element) + idx(rs.supercolumn) * PAIRHMM_NUM_PES + PAIRHMM_MAX_SIZE * idx(u(rs.ram)), 10);

  -- Connect addresses to read from read
  re.readram.addrb <= u(idx(rs.basepair) + PAIRHMM_MAX_SIZE * idx(u(rs.ram)), 10);

  -- Haplotype RAM
  hapl_ram : asym_ram port map (
    clka  => re.haplram.clka,
    wea   => re.haplram.wea,
    addra => re.haplram.addra,
    dina  => re.haplram.dina,
    clkb  => re.haplram.clkb,
    addrb => re.haplram.addrb,
    doutb => re.haplram.doutb
    );

  -- Read RAM
  read_ram : asym_ram port map (
    clka  => re.readram.clka,
    wea   => re.readram.wea,
    addra => re.readram.addra,
    dina  => re.readram.dina,
    clkb  => re.readram.clkb,
    addrb => re.readram.addrb,
    doutb => re.readram.doutb
    );

---------------------------------------------------------------------------------------------------
--    ______ _____ ______ ____
--   |  ____|_   _|  ____/ __ \
--   | |__    | | | |__ | |  | |___
--   |  __|   | | |  __|| |  | / __|
--   | |     _| |_| |   | |__| \__ \
--   |_|    |_____|_|    \____/|___/
----------------------------------------------------------------------------------------------  -----

--------------------------------------------------------------------------------------------------- Input FIFO

  -- Connect reset from the pair loader
  re.pfifo.c.rst <= r.fifos_rst;

  -- Connect read enables from the scheduler
  re.pfifo.c.rd_en <= rs.fifo_rd_en;

  -- Connect FIFO inputs:
  re.pfifo.c.wr_en <= r.p_fifo_en1;

  -- Swap the first floats to go into the fifo first
  floatswap : for K in 0 to DMA_DATA_WIDTH / PE_DW - 1 generate
    re.pfifo.din((K+1)*PE_DW-1 downto K*PE_DW) <= r.p_fifodata(1)(
      DMA_DATA_WIDTH - K * PE_DW - 1
      downto
      DMA_DATA_WIDTH - (K+1) * PE_DW
      );

  end generate;

  -- Connect PAIRHMM inputs
  re.pairhmm_in.en    <= '1';
  re.pairhmm_in.valid <= rs.valid;
  re.pairhmm_in.cell  <= rs.cell;

  -- Set top left input to 1.0 when this is the first cycle of this pair.

  -- Initial input for first PE
  re.pairhmm_in.mids.dtl <= rs.initial_array(idx(rs.schedule));

  -- Select initial value to travel with systolic array
  re.pairhmm_in.initial <= rs.initial_array(idx(rs.schedule));

  re.pairhmm_in.mids.itl <= (others => '0');
  re.pairhmm_in.mids.mtl <= (others => '0');
  re.pairhmm_in.mids.ml  <= (others => '0');
  re.pairhmm_in.mids.il  <= (others => '0');
  re.pairhmm_in.mids.dl  <= (others => '0');
  re.pairhmm_in.mids.mt  <= (others => '0');
  re.pairhmm_in.mids.it  <= (others => '0');
  re.pairhmm_in.mids.dt  <= (others => '0');

  re.pairhmm_in.emis.distm_simi <= re.pfifo.dout(31 downto 0);
  re.pairhmm_in.emis.distm_diff <= re.pfifo.dout(63 downto 32);
  re.pairhmm_in.tmis.alpha      <= re.pfifo.dout(95 downto 64);
  re.pairhmm_in.tmis.beta       <= re.pfifo.dout(127 downto 96);
  re.pairhmm_in.tmis.delta      <= re.pfifo.dout(159 downto 128);
  re.pairhmm_in.tmis.epsilon    <= re.pfifo.dout(191 downto 160);
  re.pairhmm_in.tmis.zeta       <= re.pfifo.dout(223 downto 192);
  re.pairhmm_in.tmis.eta        <= re.pfifo.dout(255 downto 224);

  -- First Word Fall Through FIFO's which can potentially cross clockdomains to a lower clock:
  p_fifo : probabilities_fifo port map (
    wr_clk    => i.cr.clk,
    rst       => re.pfifo.c.rst,
    rd_clk    => re.clk_kernel,
    din       => re.pfifo.din,
    wr_en     => re.pfifo.c.wr_en,
    wr_ack    => re.pfifo.c.wr_ack,
    rd_en     => re.pfifo.c.rd_en,
    valid     => re.pfifo.c.valid,
    dout      => re.pfifo.dout,
    full      => re.pfifo.c.full,
    empty     => re.pfifo.c.empty,
    overflow  => re.pfifo.c.overflow,
    underflow => re.pfifo.c.underflow
    );

--------------------------------------------------------------------------------------------------- Output FIFO

  -- Output data that is written back to the memory, goes into the fifo first
  re.outfifo.din <= (31 downto 0   => re.pairhmm.o.score,
                     63 downto 32  => X"00000000",   --re.pairhmm.o.score,
                     95 downto 64  => X"00000000",   --re.pairhmm.o.score,
                     127 downto 96 => X"00000000");  --re.pairhmm.o.score);

  re.outfifo.c.wr_en <= re.pairhmm.o.score_valid;  --'1' when (re.pairhmm.o.last.valid='1') and (re.pairhmm.o.last.cell = PE_LAST) else '0';

  -- Is this ugly? Maybe...
  re.outfifo.c.rd_en <= q.outfifo_rd;

  -- This fifo can potentially cross clock domains to the streaming framework.
  outfifo : kernel_to_streaming_fifo
    port map (
      wr_clk    => re.clk_kernel,
      rd_clk    => i.cr.clk,
      din       => re.outfifo.din,
      wr_en     => re.outfifo.c.wr_en,
      rd_en     => re.outfifo.c.rd_en,
      dout      => re.outfifo.dout,
      full      => re.outfifo.c.full,
      wr_ack    => re.outfifo.c.wr_ack,
      overflow  => re.outfifo.c.overflow,
      empty     => re.outfifo.c.empty,
      valid     => re.outfifo.c.valid,
      underflow => re.outfifo.c.underflow
      );

  -- Swap the first floats to go into the fifo first
  resultswap : for K in 0 to DMA_DATA_WIDTH / CU_RESULT_SIZE - 1 generate
    re.outdata((K+1)*CU_RESULT_SIZE-1 downto K*CU_RESULT_SIZE) <= re.outfifo.dout(
      DMA_DATA_WIDTH - K * CU_RESULT_SIZE - 1
      downto
      DMA_DATA_WIDTH - (K+1) * CU_RESULT_SIZE
      );

  end generate;

--------------------------------------------------------------------------------------------------- Feedback FIFO

  -- Output data that is written back to the memory, goes into the fifo first
  re.fbfifo.din <= (31 downto 0    => re.pairhmm.o.last.mids.ml,
                    63 downto 32   => re.pairhmm.o.last.mids.il,
                    95 downto 64   => re.pairhmm.o.last.mids.dl,
                    127 downto 96  => re.pairhmm.o.last.emis.distm_simi,
                    159 downto 128 => re.pairhmm.o.last.emis.distm_diff,
                    191 downto 160 => re.pairhmm.o.last.tmis.alpha,
                    223 downto 192 => re.pairhmm.o.last.tmis.beta,
                    255 downto 224 => re.pairhmm.o.last.tmis.delta,
                    287 downto 256 => re.pairhmm.o.last.tmis.epsilon,
                    319 downto 288 => re.pairhmm.o.last.tmis.zeta,
                    351 downto 320 => re.pairhmm.o.last.tmis.eta,
                    354 downto 352 => bpslv3(re.pairhmm.o.last.x),
                    386 downto 355 => re.pairhmm.o.last.initial,
                    others         => '0'
                    );

  -- latency of 1 to match delay of read and hapl rams
  re.fbfifo.c.rd_en <= rs.feedback_rd_en;

  re.fbfifo.c.wr_en <= rs.feedback_wr_en and re.pairhmm.o.last.valid;

  fbfifo : feedback_fifo port map (
    din       => re.fbfifo.din,
    dout      => re.fbfifo.dout,
    clk       => re.clk_kernel,
    srst      => re.fbfifo.c.rst,
    wr_en     => re.fbfifo.c.wr_en,
    rd_en     => re.fbfifo.c.rd_en,
    wr_ack    => re.fbfifo.c.wr_ack,
    valid     => re.fbfifo.c.valid,
    full      => re.fbfifo.c.full,
    empty     => re.fbfifo.c.empty,
    overflow  => re.fbfifo.c.overflow,
    underflow => re.fbfifo.c.underflow
    );

  re.fbfifo.c.rst <= rs.feedback_rst;

  -- Set top left input to 1.0 when this is the first cycle of this pair.
  gen_es2_topleft1 : if POSIT_ES = 2 generate
    with rs.cycle select re.fbpairhmm.mids.mtl <= X"40000000" when CYCLE_ZERO,
                                                  X"00000000" when others;
  end generate;
  gen_es3_topleft1 : if POSIT_ES = 3 generate
    with rs.cycle select re.fbpairhmm.mids.mtl <= X"40000000" when CYCLE_ZERO,
                                                  X"00000000" when others;
  end generate;

  re.fbpairhmm.mids.itl <= (others => '0');
  re.fbpairhmm.mids.dtl <= (others => '0');
  re.fbpairhmm.mids.mt  <= (others => '0');
  re.fbpairhmm.mids.it  <= (others => '0');
  re.fbpairhmm.mids.dt  <= (others => '0');

  re.fbpairhmm.mids.ml         <= re.fbfifo.dout(31 downto 0);
  re.fbpairhmm.mids.il         <= re.fbfifo.dout(63 downto 32);
  re.fbpairhmm.mids.dl         <= re.fbfifo.dout(95 downto 64);
  re.fbpairhmm.emis.distm_simi <= re.fbfifo.dout(127 downto 96);
  re.fbpairhmm.emis.distm_diff <= re.fbfifo.dout(159 downto 128);
  re.fbpairhmm.tmis.alpha      <= re.fbfifo.dout(191 downto 160);
  re.fbpairhmm.tmis.beta       <= re.fbfifo.dout(223 downto 192);
  re.fbpairhmm.tmis.delta      <= re.fbfifo.dout(255 downto 224);
  re.fbpairhmm.tmis.epsilon    <= re.fbfifo.dout(287 downto 256);
  re.fbpairhmm.tmis.zeta       <= re.fbfifo.dout(319 downto 288);
  re.fbpairhmm.tmis.eta        <= re.fbfifo.dout(351 downto 320);
  re.fbpairhmm.x               <= slv3bp(re.fbfifo.dout(354 downto 352));
  re.fbpairhmm.initial         <= re.fbfifo.dout(386 downto 355);


  re.fbpairhmm.en    <= '1';
  re.fbpairhmm.valid <= rs.valid;
  re.fbpairhmm.cell  <= rs.cell;

---------------------------------------------------------------------------------------------------
--     _____           _        _ _
--    / ____|         | |      | (_)          /\
--   | (___  _   _ ___| |_ ___ | |_  ___     /  \   _ __ _ __ __ _ _   _
--    \___ \| | | / __| __/ _ \| | |/ __|   / /\ \ | '__| '__/ _` | | | |
--    ____) | |_| \__ \ || (_) | | | (__   / ____ \| |  | | | (_| | |_| |
--   |_____/ \__, |___/\__\___/|_|_|\___| /_/    \_\_|  |_|  \__,_|\__, |
--            __/ |                                                 __/ |
--           |___/                                                 |___/
---------------------------------------------------------------------------------------------------
  -- Connect clock and reset
  re.pairhmm_cr <= (clk => re.clk_kernel,
                    rst => rs.pairhmm_rst
                    );

  -- Input for the first PE
  re.pairhmm.i.first <= rs.pe_first;
  -- Base X for the first PE must come from the read RAM or it must come from the feedback FIFO with a latency of 1
  re.pairhmm.i.x     <= slv3bp(re.readram.doutb((idx(rs.core_schedule) + 1)* BP_SIZE -1 downto idx(rs.core_schedule)*BP_SIZE)) when rs.feedback_rd_en1 = '0' else
                    rs.pe_first.x;
  -- Schedule
  re.pairhmm.i.schedule <= rs.core_schedule;

  -- Address for Y bus
  re.pairhmm.i.ybus.addr <= rs.ybus_addr1;
  re.pairhmm.i.ybus.wren <= rs.ybus_en1;

  re.pairhmm.i.fb <= rs.feedback_wr_en;

  -- Data for Y bus
  ybus_data_sel : for J in 0 to PE_DEPTH - 1 generate
    re.pairhmm.i.ybus.data(J) <= slv3bp(re.haplram.doutb((J+1) * BP_SIZE - 1 downto J * BP_SIZE)) when rs.ybus_addr1 < rs.sizey1 else
                                 BP_STOP;
  end generate;

  -- Core instantiation
  pairhmm_core : entity work.pairhmm port map (
    cr => re.pairhmm_cr,
    i  => re.pairhmm.i,
    o  => re.pairhmm.o
    );

---------------------------------------------------------------------------------------------------
--     _____      _              _       _
--    / ____|    | |            | |     | |
--   | (___   ___| |__   ___  __| |_   _| | ___ _ __
--    \___ \ / __| '_ \ / _ \/ _` | | | | |/ _ \ '__|
--    ____) | (__| | | |  __/ (_| | |_| | |  __/ |
--   |_____/ \___|_| |_|\___|\__,_|\__,_|_|\___|_|
---------------------------------------------------------------------------------------------------
-- This implements a round-robin scheduler to fill pipeline stage n with the output of FIFO n
---------------------------------------------------------------------------------------------------

  scheduler_comb : process(all)
    variable vs : cu_sched;
  begin
--------------------------------------------------------------------------------------------------- default assignments
    vs := rs;

    vs.ybus_en := '0';

    -- Select the proper input, also correct for latency of 1 of the hapl and read RAMs:
    if rs.feedback_rd_en = '0' then
      vs.pe_first := re.pairhmm_in;
    else
      vs.pe_first := re.fbpairhmm;
    end if;

    -- Control signals that also need a latency of 1 for this reason:
    vs.ybus_addr1      := rs.ybus_addr;
    vs.core_schedule   := rs.schedule;
    vs.feedback_rd_en1 := rs.feedback_rd_en;
    vs.ybus_en1        := rs.ybus_en;
    vs.sizey1          := rs.sizey;

--------------------------------------------------------------------------------------------------- round robin schedule
    -- Schedule is always running, this is to keep the PairHMM core running even when the scheduler
    -- itself is idle. This allows the scheduler to start a new batch while there is still an old
    -- batch somewhere in the Systolic Array

    -- Go to next pair
    vs.schedule := rs.schedule + 1;
    -- Wrap around (required when log2(PE_DEPTH) is not an integer
    if vs.schedule = PE_DEPTH then
      vs.schedule := (others => '0');
    end if;

--------------------------------------------------------------------------------------------------- state machine
    case rs.state is

      when idle =>
        -- Gather the sizes, bases and initial D row value from the other clock domain
        vs.sizey := r.sched.y_size(log2e(PAIRHMM_MAX_SIZE) downto 0);

        vs.sizex  := r.sched.x_size(log2e(PAIRHMM_MAX_SIZE) downto 0);
        vs.sizexp := r.sched.x_padded(log2e(PAIRHMM_MAX_SIZE) downto 0);

        vs.initial_array := r.sched_array;

        vs.cycle       := (others => '0');
        vs.basepair    := (others => '0');
        vs.element     := (others => '0');
        vs.supercolumn := (others => '0');

        vs.valid := '0';
        vs.cell  := PE_NORMAL;

        vs.fifo_rd_en := '0';
        vs.fifo_reads := (others => '0');

        vs.ybus_addr := (others => '0');

        vs.feedback_rd_en := '0';
        vs.feedback_wr_en := '0';
        vs.feedback_rst   := '1';

        -- Start everything when the FIFO's are filled and align with the scheduler
        -- Starting up takes two cycles, thus we wait until the scheduler is at PE_DEPTH - 2.
        if r.filled = '1' and rs.schedule = PE_DEPTH - 2 then
          vs.state        := startup;
          vs.feedback_rst := '0';
          vs.pairhmm_rst  := '0';
        end if;

      when startup =>
        vs.state      := processing;    -- Go to processing state
        vs.fifo_rd_en := '1';  -- Put the read-enable high for the first FIFO
        vs.valid      := '1';           -- Enable data valid on the next cycle
        vs.cell       := PE_TOP;  -- First cycle we will be at top of matrix
        vs.startflag  := '1';
        vs.ram        := not rs.ram;    -- Wrap to the other half of the RAM
        vs.ybus_en    := '1';

      when processing =>

        -- Unset the startflag
        vs.startflag := '0';

        -- Increase PairHMM cycle, except when this is the first cycle, which we can check by looking at the last bit of fifo_rd_en
        -- Everything inside this if statement is triggered when a new cell update cycle starts
        if vs.schedule = u(0, PE_DEPTH_BITS) and rs.startflag = '0' then
          vs.cycle    := rs.cycle + 1;     -- Increase the total cycle counter
          vs.basepair := rs.basepair + 1;  -- Increase the counter of Y

          if rs.element /= PAIRHMM_NUM_PES - 1 then
            vs.element   := rs.element + 1;  -- Increase processing highest active element in supercolumn counter
            vs.ybus_addr := rs.ybus_addr + 1;  -- Increase X Bus address
            vs.ybus_en   := '1';        -- Write to next element
          end if;

          -- If we are done with the last padded base of X
          if vs.basepair = rs.sizexp then
            --If this is not the last base
            if rs.cell /= PE_LAST then
              vs.supercolumn := rs.supercolumn + 1;  -- Advance to the next supercolumn
              vs.element     := (others => '0');  -- Reset the highest active element in supercolumn counter
              vs.ybus_addr   := (others => '0');
              vs.basepair    := (others => '0');  -- Reset the basepair counter of Y
              vs.sizey       := rs.sizey - PAIRHMM_NUM_PES;  -- Subtract size in the X direction
              vs.ybus_en     := '1';    -- Write to first element in next cycle
            end if;
            vs.fifo_rd_en := '0';       -- Stop reading from the FIFO
          end if;

          -- Default PE cell state is normal:
          vs.cell := PE_NORMAL;

          -- If the vertical basepair we're working on is 0, we are at the top of the matrix
          if vs.basepair = 0 then
            vs.cell := PE_TOP;
          end if;

          -- If we are at the last base of the read
          if vs.basepair = rs.sizex - 1 then
            vs.cell     := PE_BOTTOM;   -- Assert the "bottom" signal
            if rs.sizey <= PAIRHMM_NUM_PES then
              vs.cell := PE_LAST;       -- Assert the "last" signal
            end if;
          end if;

          -- If we fed the last base of the whole pair in the previous cell update cycle
          if rs.cell = PE_LAST then
            vs.valid := '0';            -- Next inputs are not valid anymore
            vs.cell  := PE_NORMAL;  -- Not last anymore TODO: this is a don't care?
            vs.state := done;
          end if;
        end if;

        -- Enable feedback FIFO writing when we passed the number of PE's the first time.
        if vs.cycle = PAIRHMM_NUM_PES then
          vs.feedback_wr_en := '1';
        end if;

        -- Enable feedback FIFO reading when we passed the number of padded bases the first time.
        if vs.cycle = rs.sizexp then
          vs.feedback_rd_en := '1';
        end if;

        -- Keep track of howmany reads we've done from the FIFO
        if vs.fifo_rd_en = '1' then
          vs.fifo_reads := rs.fifo_reads + 1;
        end if;

      when done =>
        vs.state          := idle;
        --vs.pairhmm_rst                  := '1'; -- Dont reset the PairHMM core here, because even after emptying the FIFO's, there may still be
        -- pairs in the systolic array
        -- Reset the feedback FIFO
        vs.feedback_rd_en := '0';
        vs.feedback_wr_en := '0';
        vs.feedback_rst   := '1';
      when others =>
        null;

    end case;
--------------------------------------------------------------------------------------------------- outputs
    qs <= vs;
  end process;
--------------------------------------------------------------------------------------------------- registers
  scheduler_reg : process(re.clk_kernel)
  begin
    if rising_edge(re.clk_kernel) then
      if i.cr.rst then
        rs.state          <= idle;
        rs.cycle          <= (others => '0');
        rs.basepair       <= (others => '0');
        rs.schedule       <= (others => '0');
        rs.fifo_rd_en     <= '0';
        rs.valid          <= '0';
        rs.cell           <= PE_NORMAL;
        rs.pairhmm_rst    <= '1';
        rs.feedback_rd_en <= '0';
        rs.feedback_wr_en <= '0';
        rs.feedback_rst   <= '1';
        rs.fifo_reads     <= (others => '0');
        rs.ram            <= '1';  -- Set to use top half of RAM since at start this will wrap to bottom
        rs.ybus_en        <= '0';
        rs.ybus_en1       <= '0';
      else
        rs <= qs;
      end if;
    end if;
  end process;

end architecture logic;
