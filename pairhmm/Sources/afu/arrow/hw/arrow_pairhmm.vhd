library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;

library work;
use work.Streams.all;
use work.Utils.all;
use work.Arrow.all;

use work.SimUtils.all;

use work.arrow_pairhmm_pkg.all;

entity arrow_pairhmm is
  generic (
    -- Host bus properties
    BUS_ADDR_WIDTH : natural := 64;
    BUS_DATA_WIDTH : natural := 512;

    -- MMIO bus properties
    SLV_BUS_ADDR_WIDTH : natural := 32;
    SLV_BUS_DATA_WIDTH : natural := 32

   -- (Generic defaults are set for SystemVerilog compatibility)
    );

  port (
    clk     : in std_logic;
    reset_n : in std_logic;

    ---------------------------------------------------------------------------
    -- AXI4 master
    --
    -- To be connected to the DDR controllers (through CL_DMA_PCIS_SLV)
    ---------------------------------------------------------------------------
    -- Read address channel
    m_axi_araddr  : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    m_axi_arlen   : out std_logic_vector(7 downto 0);
    m_axi_arvalid : out std_logic;
    m_axi_arready : in  std_logic;
    m_axi_arsize  : out std_logic_vector(2 downto 0);

    -- Read data channel
    m_axi_rdata  : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    m_axi_rresp  : in  std_logic_vector(1 downto 0);
    m_axi_rlast  : in  std_logic;
    m_axi_rvalid : in  std_logic;
    m_axi_rready : out std_logic;

    ---------------------------------------------------------------------------
    -- AXI4-lite slave
    --
    -- To be connected to "sh_cl_sda" a.k.a. "AppPF Bar 1"
    ---------------------------------------------------------------------------
    -- Write adress
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;
    s_axi_awaddr  : in  std_logic_vector(SLV_BUS_ADDR_WIDTH-1 downto 0);

    -- Write data
    s_axi_wvalid : in  std_logic;
    s_axi_wready : out std_logic;
    s_axi_wdata  : in  std_logic_vector(SLV_BUS_DATA_WIDTH-1 downto 0);
    s_axi_wstrb  : in  std_logic_vector((SLV_BUS_DATA_WIDTH/8)-1 downto 0);

    -- Write response
    s_axi_bvalid : out std_logic;
    s_axi_bready : in  std_logic;
    s_axi_bresp  : out std_logic_vector(1 downto 0);

    -- Read address
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;
    s_axi_araddr  : in  std_logic_vector(SLV_BUS_ADDR_WIDTH-1 downto 0);

    -- Read data
    s_axi_rvalid : out std_logic;
    s_axi_rready : in  std_logic;
    s_axi_rdata  : out std_logic_vector(SLV_BUS_DATA_WIDTH-1 downto 0);
    s_axi_rresp  : out std_logic_vector(1 downto 0)
    );
end entity arrow_pairhmm;

architecture rtl of arrow_pairhmm is

  signal reset : std_logic;

begin
  -- Bottom buses
  constant BB : natural := 16;

  -----------------------------------------------------------------------------
  -- Memory Mapped Input/Output
  -----------------------------------------------------------------------------

  -----------------------------------
  -- Fletcher registers
  ----------------------------------- Default registers
  --   1 status (uint64)        =  2
  --   1 control (uint64)       =  2
  --   1 return (uint64)        =  2
  ----------------------------------- Buffer addresses
  --   1 index buf address      =  2
  --   1 data  buf address      =  2
  ----------------------------------- Custom registers
  --  1 first & last idx       = 2
  --  1 regex results          = 1
  -----------------------------------
  -- Total:                       13 regs
  constant NUM_FLETCHER_REGS : natural := 13;

  -- The LSB index in the slave address
  constant SLV_ADDR_LSB : natural := log2floor(SLV_BUS_DATA_WIDTH/4) - 1;

  -- The MSB index in the slave address
  constant SLV_ADDR_MSB : natural := SLV_ADDR_LSB + log2floor(NUM_FLETCHER_REGS);

  -- Fletcher register offsets
  constant REG_STATUS_HI : natural := 0;
  constant REG_STATUS_LO : natural := 1;

  -- The offsets of the bits to signal busy and done for each of the units
  constant STATUS_BUSY_OFFSET : natural := 0;
  constant STATUS_DONE_OFFSET : natural := CORES;

  constant REG_CONTROL_HI : natural := 2;
  constant REG_CONTROL_LO : natural := 3;

  -- The offsets of the bits to signal start and reset to each of the units
  constant CONTROL_START_OFFSET : natural := 0;
  constant CONTROL_RESET_OFFSET : natural := CORES;

  -- Return register
  constant REG_RETURN_HI : natural := 4;
  constant REG_RETURN_LO : natural := 5;

  -- Offset buffer address
  constant REG_OFF_ADDR_HI : natural := 6;
  constant REG_OFF_ADDR_LO : natural := 7;

  -- Data buffer address
  constant REG_UTF8_ADDR_HI : natural := 8;
  constant REG_UTF8_ADDR_LO : natural := 9;

  -- Register offsets to indices for each RegExp unit to work on
  constant REG_FIRST_IDX : natural := 10;
  constant REG_LAST_IDX  : natural := 26;

  -- Register offset for each RegExp unit to put its result
  constant REG_RESULT : natural := 42;

  -- Memory mapped register file
  type mm_regs_t is array (0 to NUM_FLETCHER_REGS-1) of std_logic_vector(SLV_BUS_DATA_WIDTH-1 downto 0);
  signal mm_regs : mm_regs_t;

  -- Helper signals to do handshaking on the slave port
  signal read_address    : natural range 0 to NUM_FLETCHER_REGS-1;
  signal write_valid     : std_logic;
  signal read_valid      : std_logic := '0';
  signal write_processed : std_logic;

  -----------------------------------------------------------------------------
  -- AXI Interconnect Master Ports
  -----------------------------------------------------------------------------
  type bus_bottom_array_t is array (0 to BB-1) of bus_bottom_t;
  type axi_mid_array_t is array (0 to BB-1) of axi_mid_t;

  signal bus_bottom_array : bus_bottom_array_t;
  signal axi_mid_array    : axi_mid_array_t;
  signal axi_top          : axi_top_t;

  -----------------------------------------------------------------------------
  -- Registers
  -----------------------------------------------------------------------------
  type reg_array_t is array (0 to CORES-1) of std_logic_vector(31 downto 0);

  signal reg_array_firstidx : reg_array_t;
  signal reg_array_lastidx  : reg_array_t;
  signal reg_array_off_hi   : reg_array_t;
  signal reg_array_off_lo   : reg_array_t;
  signal reg_array_utf8_hi  : reg_array_t;
  signal reg_array_utf8_lo  : reg_array_t;

  -----------------------------------------------------------------------------
-- ColumnReader Interface
-----------------------------------------------------------------------------
  constant OFFSET_WIDTH       : natural := 32;
  constant VALUE_ELEM_WIDTH   : natural := 8;
  constant VALUES_PER_CYCLE   : natural := 4;
  constant NUM_STREAMS        : natural := 2;
  constant VALUES_WIDTH       : natural := VALUE_ELEM_WIDTH * VALUES_PER_CYCLE;
  constant VALUES_COUNT_WIDTH : natural := log2ceil(VALUES_PER_CYCLE)+1;
  constant OUT_DATA_WIDTH     : natural := OFFSET_WIDTH + VALUES_WIDTH + VALUES_COUNT_WIDTH;

  signal out_valid  : std_logic_vector(NUM_STREAMS-1 downto 0);
  signal out_ready  : std_logic_vector(NUM_STREAMS-1 downto 0);
  signal out_last   : std_logic_vector(NUM_STREAMS-1 downto 0);
  signal out_dvalid : std_logic_vector(NUM_STREAMS-1 downto 0);
  signal out_data   : std_logic_vector(OUT_DATA_WIDTH-1 downto 0);

  -- Command Stream
  type command_t is record
    valid    : std_logic;
    ready    : std_logic;
    firstIdx : std_logic_vector(OFFSET_WIDTH-1 downto 0);
    lastIdx  : std_logic_vector(OFFSET_WIDTH-1 downto 0);
    ctrl     : std_logic_vector(2*BUS_ADDR_WIDTH-1 downto 0);
  end record;

  signal s_cmd : command_t;

  begin

    reset <= '1' when reset_n = '0' else '0';

    -----------------------------------------------------------------------------
    -- Memory Mapped Slave Registers
    -----------------------------------------------------------------------------
    write_valid <= s_axi_awvalid and s_axi_wvalid and not write_processed;

    s_axi_awready <= write_valid;
    s_axi_wready  <= write_valid;
    s_axi_bresp   <= "00";              -- Always OK
    s_axi_bvalid  <= write_processed;

    s_axi_arready <= not read_valid;

    -- Mux for reading
    -- Might want to insert a reg slice before getting it to the ColumnReaders
    -- and UserCore
    s_axi_rdata  <= mm_regs(read_address);
    s_axi_rvalid <= read_valid;
    s_axi_rresp  <= "00";               -- Always OK

    -- Reads
    read_from_regs : process(clk) is
      variable address : natural range 0 to NUM_FLETCHER_REGS-1;
    begin
      address := int(s_axi_araddr(SLV_ADDR_MSB downto SLV_ADDR_LSB));

      if rising_edge(clk) then
        if reset_n = '0' then
          read_valid <= '0';
        else
          if s_axi_arvalid = '1' and read_valid = '0' then
            dumpStdOut("Read request from MMIO: " & integer'image(address) & " value " & integer'image(int(mm_regs(address))));
            read_address <= address;
            read_valid   <= '1';
          elsif s_axi_rready = '1' then
            read_valid <= '0';
          end if;
        end if;
      end if;
    end process;

    -- Writes

    -- TODO: For registers that are split up over two addresses, this is not
    -- very pretty. There should probably be some synchronization mechanism
    -- to only apply the write after both HI and LO addresses have been
    -- written.
    -- Also we don't care about byte enables at the moment.
    write_to_regs : process(clk) is
      variable address : natural range 0 to NUM_FLETCHER_REGS;
    begin

      address := int(s_axi_awaddr(SLV_ADDR_MSB downto SLV_ADDR_LSB));

      if rising_edge(clk) then
        if write_valid = '1' then
          dumpStdOut("Write to MMIO: " & integer'image(address));

          case address is
            -- Read only addresses do nothing
            when REG_STATUS_HI =>
            when REG_STATUS_LO =>
            when REG_RETURN_HI =>
            when REG_RETURN_LO =>
            when REG_RESULT to REG_RESULT + NUM_REGEX - 1 =>
            -- All others are writeable:
            when others =>
              mm_regs(address) <= s_axi_wdata;
          end case;
        end if;

        -- Read only register values:

        -- Status registers
        mm_regs(REG_STATUS_HI) <= (others => '0');

        mm_regs(REG_STATUS_LO)(STATUS_BUSY_OFFSET + CORES - 1 downto STATUS_BUSY_OFFSET) <= bit_array_busy;
        mm_regs(REG_STATUS_LO)(STATUS_DONE_OFFSET + CORES - 1 downto STATUS_DONE_OFFSET) <= bit_array_done;

        -- Return registers
        mm_regs(REG_RETURN_HI) <= (others => '0');
        mm_regs(REG_RETURN_LO) <= (others => '0');  -- PUT RESULT HERE (TO WRITE TO HOST)

        -- Result registers
        mm_regs(REG_RESULT) <= (others => '0');  -- PUT RESULT HERE (TO WRITE TO HOST)

        if reset_n = '0' then
          mm_regs(REG_CONTROL_LO) <= (others => '0');
          mm_regs(REG_CONTROL_HI) <= (others => '0');
        end if;
      end if;
    end process;

    -- Write response
    write_resp_proc : process(clk) is
    begin
      if rising_edge(clk) then
        if reset_n = '0' then
          write_processed <= '0';
        else
          if write_valid = '1' then
            write_processed <= '1';
          elsif s_axi_bready = '1' then
            write_processed <= '0';
          end if;
        end if;
      end if;
    end process;

    -----------------------------------------------------------------------------
    -- Master
    -----------------------------------------------------------------------------
    -- Read address channel
    axi_top.arready <= m_axi_arready;

    m_axi_arvalid <= axi_top.arvalid;
    m_axi_araddr  <= axi_top.araddr;

    m_axi_arlen <= axi_top.arlen;

    m_axi_arsize <= "110";              --6 for 2^6*8 bits = 512 bits

    -- Read data channel
    m_axi_rready <= axi_top.rready;

    axi_top.rvalid <= m_axi_rvalid;
    axi_top.rdata  <= m_axi_rdata;
    axi_top.rresp  <= m_axi_rresp;
    axi_top.rlast  <= m_axi_rlast;

    --
    -- COLUMN READERS
    --
    -- Reads
    cr_haplos : HaplColumnReader
      generic map (
      BUS_ADDR_WIDTH              : natural := 32;
      BUS_LEN_WIDTH               : natural := 8;
      BUS_DATA_WIDTH              : natural := 32;
      BUS_BURST_STEP_LEN          : natural := 4;
      BUS_BURST_MAX_LEN           : natural := 16;
      INDEX_WIDTH                 : natural := 32;
      CMD_TAG_ENABLE              : boolean := false;
      CMD_TAG_WIDTH               : natural := 1
        );
    port map (
      bus_clk   => clk,
      bus_reset => reset_n,
      acc_clk   => clk,
      acc_reset => reset_n,

      cmd_valid    => s_cmd.valid,
      cmd_ready    => s_cmd.ready,
      cmd_firstIdx => s_cmd.firstIdx,
      cmd_lastIdx  => s_cmd.lastIdx,
      cmd_idxBase                 : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      cmd_valBase                 : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
      cmd_tag      => (others => '0'),  -- CMD_TAG_ENABLE is false

      unlock_valid => open,
      unlock_ready => '1',
      unlock_tag   => open,

      busReq_valid => bus_req_valid,
      busReq_ready => bus_req_ready,
      busReq_addr  => bus_req_addr,
      busReq_len   => bus_req_len,

      busResp_valid => bus_rsp_valid,
      busResp_ready => bus_rsp_ready,
      busResp_data  => bus_rsp_data,
      busResp_last  => bus_rsp_last,

      out_valid  => out_valid,
      out_ready  => out_ready,
      out_last   => out_last,
      out_dvalid => out_dvalid,
      out_data   => out_data
      out_len                     : out std_logic_vector(INDEX_WIDTH-1 downto 0);
      );




  end architecture;
