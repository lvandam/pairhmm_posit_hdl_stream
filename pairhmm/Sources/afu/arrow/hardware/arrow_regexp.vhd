-- Copyright 2018 Delft University of Technology
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;

library work;
use work.Streams.all;
use work.Utils.all;
use work.Arrow.all;

use work.SimUtils.all;

use work.arrow_regexp_pkg.all;

-- In our programming model it is required to have an interface to a
-- memory (host memory, wether or not copied, as long as it retains the
-- Arrow format) and a slave interface for the memory mapped registers.
--
-- This unit uses AXI interconnect to do both, where the slave interface
-- is AXI4-lite and the master interface an AXI4 full interface. For high
-- throughput, the master interface should support bursts.

entity arrow_regexp is
  generic (
    -- Host bus properties
    BUS_ADDR_WIDTH : natural := 64;
    BUS_DATA_WIDTH : natural := 512;

    -- MMIO bus properties
    SLV_BUS_ADDR_WIDTH : natural := 32;
    SLV_BUS_DATA_WIDTH : natural := 32;

    REG_WIDTH : natural := 32

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
end arrow_regexp;

architecture arrow_regexp of arrow_regexp is
  -----------------------------------------------------------------------------
  -- Memory Mapped Input/Output
  -----------------------------------------------------------------------------

  -----------------------------------
  -- Fletcher registers
  ----------------------------------- Default registers
  --   1 status (uint64)        =  2
  --   1 control (uint64)       =  2
  --   1 return (uint64)        =  2
  ----------------------------------- Haplotype column
  --   1 offsets buf address    =  2
  --   1 data  buf address      =  2
  --   1 first idx & last idx   =  2
  ----------------------------------- Read column
  --   1 offsets buf address    =  2
  --   1 data  buf address      =  2
  --   1 first idx & last idx   =  2

  ----------------------------------- Custom registers
  --   1 results                =  2
  -----------------------------------
  -- Total:                       14 regs
  constant NUM_FLETCHER_REGS : natural := 18;

  -- The LSB index in the slave address
  constant SLV_ADDR_LSB : natural := log2floor(SLV_BUS_DATA_WIDTH / 4) - 1;

  -- The MSB index in the slave address
  constant SLV_ADDR_MSB : natural := SLV_ADDR_LSB + log2floor(NUM_FLETCHER_REGS);

  -- Fletcher register offsets
  constant REG_STATUS_HI : natural := 0;
  constant REG_STATUS_LO : natural := 1;

  -- Control register offsets
  constant REG_CONTROL_HI : natural := 2;
  constant REG_CONTROL_LO : natural := 3;

  -- Return register
  constant REG_RETURN_HI : natural := 4;
  constant REG_RETURN_LO : natural := 5;

  -- Index/Offset buffer address
  constant REG_OFF_ADDR_HI : natural := 6;
  constant REG_OFF_ADDR_LO : natural := 7;

  -- Data buffer address
  constant REG_UTF8_ADDR_HI : natural := 8;
  constant REG_UTF8_ADDR_LO : natural := 9;

  -- START OF ARGUMENTS (REGISTER 5)
  -- Register offsets to indices for each RegExp unit to work on
  constant REG_FIRST_IDX : natural := 10;
  constant REG_LAST_IDX  : natural := 11;

  -- READS
  constant REG_READ_FIRST_IDX1 : natural := 12;
  constant REG_READ_LAST_IDX1  : natural := 13;

  constant REG_READ_FIRST_IDX2 : natural := 14;
  constant REG_READ_LAST_IDX2  : natural := 15;



  -- Register offset for each RegExp unit to put its result
  constant REG_RESULT : natural := 16;

  -- The offsets of the bits to signal busy and done for each of the units
  constant STATUS_BUSY_OFFSET : natural := 0;
  constant STATUS_DONE_OFFSET : natural := 1;

  -- The offsets of the bits to signal start and reset to each of the units
  constant CONTROL_START_OFFSET : natural := 0;
  constant CONTROL_RESET_OFFSET : natural := 1;

  -- Memory mapped register file
  type mm_regs_t is array (0 to NUM_FLETCHER_REGS - 1) of std_logic_vector(SLV_BUS_DATA_WIDTH - 1 downto 0);
  signal mm_regs : mm_regs_t;

  -- Helper signals to do handshaking on the slave port
  signal read_address    : natural range 0 to NUM_FLETCHER_REGS - 1;
  signal write_valid     : std_logic;
  signal read_valid      : std_logic := '0';
  signal write_processed : std_logic;

  signal axi_top : axi_top_t;

  -- Register all ports to ease timing
  signal busy, done, reset_start : std_logic;
  signal r_control_reset         : std_logic;
  signal r_control_start         : std_logic;
  signal r_reset_start           : std_logic;
  signal r_busy                  : std_logic;
  signal r_done                  : std_logic;
  signal r_firstidx              : std_logic_vector(REG_WIDTH - 1 downto 0);
  signal r_lastidx               : std_logic_vector(REG_WIDTH - 1 downto 0);
  signal r_off_hi                : std_logic_vector(REG_WIDTH - 1 downto 0);
  signal r_off_lo                : std_logic_vector(REG_WIDTH - 1 downto 0);
  signal r_utf8_hi               : std_logic_vector(REG_WIDTH - 1 downto 0);
  signal r_utf8_lo               : std_logic_vector(REG_WIDTH - 1 downto 0);

  -----------------------------------------------------------------------------
  -- Haplotype ColumnReader Interface
  -----------------------------------------------------------------------------
  constant INDEX_WIDTH        : natural := 32;
  constant VALUE_ELEM_WIDTH   : natural := 8;
  constant VALUES_PER_CYCLE   : natural := 8;  -- burst size of 8
  constant NUM_STREAMS        : natural := 2;  -- index stream, data stream
  constant VALUES_WIDTH       : natural := VALUE_ELEM_WIDTH * VALUES_PER_CYCLE;
  constant VALUES_COUNT_WIDTH : natural := log2ceil(VALUES_PER_CYCLE) + 1;
  constant OUT_DATA_WIDTH     : natural := INDEX_WIDTH + VALUES_WIDTH + VALUES_COUNT_WIDTH;

  signal out_valid  : std_logic_vector(NUM_STREAMS - 1 downto 0);
  signal out_ready  : std_logic_vector(NUM_STREAMS - 1 downto 0);
  signal out_last   : std_logic_vector(NUM_STREAMS - 1 downto 0);
  signal out_dvalid : std_logic_vector(NUM_STREAMS - 1 downto 0);
  signal out_data   : std_logic_vector(OUT_DATA_WIDTH - 1 downto 0);

  -- Command Stream
  type command_t is record
    valid    : std_logic;
    ready    : std_logic;
    firstIdx : std_logic_vector(INDEX_WIDTH - 1 downto 0);
    lastIdx  : std_logic_vector(INDEX_WIDTH - 1 downto 0);
    ctrl     : std_logic_vector(2 * BUS_ADDR_WIDTH - 1 downto 0);
  end record;

  -- Output Streams
  type len_stream_in_t is record
    valid  : std_logic;
    dvalid : std_logic;
    last   : std_logic;
    data   : std_logic_vector(INDEX_WIDTH - 1 downto 0);
  end record;

  type utf8_stream_in_t is record
    valid  : std_logic;
    dvalid : std_logic;
    last   : std_logic;
    count  : std_logic_vector(VALUES_COUNT_WIDTH - 1 downto 0);
    data   : std_logic_vector(VALUES_WIDTH - 1 downto 0);
  end record;

  type str_elem_in_t is record
    len  : len_stream_in_t;
    utf8 : utf8_stream_in_t;
  end record;

  procedure conv_streams_in (
    signal valid       : in  std_logic_vector(NUM_STREAMS - 1 downto 0);
    signal dvalid      : in  std_logic_vector(NUM_STREAMS - 1 downto 0);
    signal last        : in  std_logic_vector(NUM_STREAMS - 1 downto 0);
    signal data        : in  std_logic_vector(OUT_DATA_WIDTH - 1 downto 0);
    signal str_elem_in : out str_elem_in_t
    ) is
  begin
    str_elem_in.len.data   <= data (INDEX_WIDTH-1 downto 0);
    str_elem_in.len.valid  <= valid (0);
    str_elem_in.len.dvalid <= dvalid(0);
    str_elem_in.len.last   <= last (0);

    str_elem_in.utf8.count  <= data(VALUES_COUNT_WIDTH + VALUES_WIDTH + INDEX_WIDTH - 1 downto VALUES_WIDTH + INDEX_WIDTH);
    str_elem_in.utf8.data   <= data(VALUES_WIDTH + INDEX_WIDTH - 1 downto INDEX_WIDTH);
    str_elem_in.utf8.valid  <= valid(1);
    str_elem_in.utf8.dvalid <= dvalid(1);
    str_elem_in.utf8.last   <= last(1);
  end procedure;

  type len_stream_out_t is record
    ready : std_logic;
  end record;

  type utf8_stream_out_t is record
    ready : std_logic;
  end record;

  type str_elem_out_t is record
    len  : len_stream_out_t;
    utf8 : utf8_stream_out_t;
  end record;

  procedure conv_streams_out (
    signal str_elem_out : in  str_elem_out_t;
    signal out_ready    : out std_logic_vector(NUM_STREAMS - 1 downto 0)
    ) is
  begin
    out_ready(0) <= str_elem_out.len.ready;
    out_ready(1) <= str_elem_out.utf8.ready;
  end procedure;

  signal str_elem_in  : str_elem_in_t;
  signal str_elem_out : str_elem_out_t;

  type regex_in_t is record
    valid : std_logic;
    data  : std_logic_vector(VALUES_WIDTH - 1 downto 0);
    mask  : std_logic_vector(VALUES_PER_CYCLE - 1 downto 0);
    last  : std_logic;
  end record;

  type regex_out_t is record
    valid : std_logic;
    match : std_logic;
    error : std_logic;
  end record;

  type regex_t is record
    input  : regex_in_t;
    output : regex_out_t;
  end record;

  signal regex_output : regex_out_t;

  -----------------------------------------------------------------------------
  -- READS ColumnReader Interface
  -----------------------------------------------------------------------------
  constant INDEX_WIDTH_READS        : natural := 32;
  constant VALUE_ELEM_WIDTH_READS   : natural := 8;
  constant VALUES_PER_CYCLE_READS   : natural := 1;  -- burst size of 1
  constant NUM_STREAMS_READS        : natural := 3;  -- len, read, prob
  constant VALUES_WIDTH_READ       : natural := VALUE_ELEM_WIDTH_READS * VALUES_PER_CYCLE_READS;
  constant VALUES_COUNT_WIDTH_READS : natural := log2ceil(VALUES_PER_CYCLE_READS) + 1;
  constant OUT_DATA_WIDTH_READS     : natural := INDEX_WIDTH_READS + VALUES_WIDTH_READ + VALUES_COUNT_WIDTH_READS;

  constant VALUES_WIDTH_PROBS_READS       : natural := 8 * 32; -- 8 probabilities of 32 bit

  -- signal out_valid  : std_logic_vector(NUM_STREAMS - 1 downto 0);
  -- signal out_ready  : std_logic_vector(NUM_STREAMS - 1 downto 0);
  -- signal out_last   : std_logic_vector(NUM_STREAMS - 1 downto 0);
  -- signal out_dvalid : std_logic_vector(NUM_STREAMS - 1 downto 0);
  -- signal out_data   : std_logic_vector(OUT_DATA_WIDTH - 1 downto 0);
  type len_stream_reads_in_t is record
    valid  : std_logic;
    dvalid : std_logic;
    last   : std_logic;
    data   : std_logic_vector(INDEX_WIDTH - 1 downto 0);
  end record;

  type readbp_stream_in_t is record
    valid  : std_logic;
    dvalid : std_logic;
    last   : std_logic;
    count  : std_logic_vector(VALUES_COUNT_WIDTH - 1 downto 0);
    data   : std_logic_vector(VALUES_WIDTH - 1 downto 0);
  end record;

  type probs_stream_in_t is record
    valid  : std_logic;
    dvalid : std_logic;
    last   : std_logic;
    count  : std_logic_vector(VALUES_COUNT_WIDTH - 1 downto 0);
    data   : std_logic_vector(VALUES_WIDTH - 1 downto 0);
  end record;

  type str_reads_in_t is record
    len    : len_stream_reads_in_t;
    readbp : readbp_stream_in_t;
    probs  : probs_stream_in_t;
  end record;

  signal str_reads_in : str_reads_in_t;
  procedure conv_streams_reads_in (
    signal valid        : in  std_logic_vector(NUM_STREAMS_READS - 1 downto 0);
    signal dvalid       : in  std_logic_vector(NUM_STREAMS_READS - 1 downto 0);
    signal last         : in  std_logic_vector(NUM_STREAMS_READS - 1 downto 0);
    signal data         : in  std_logic_vector(OUT_DATA_WIDTH - 1 downto 0);
    signal str_reads_in : out str_reads_in_t
    ) is
  begin
    str_reads_in.len.data   <= data (INDEX_WIDTH-1 downto 0);
    str_reads_in.len.valid  <= valid (0);
    str_reads_in.len.dvalid <= dvalid(0);
    str_reads_in.len.last   <= last (0);

    str_reads_in.readbp.count  <= data(VALUES_COUNT_WIDTH + VALUES_WIDTH + INDEX_WIDTH - 1 downto VALUES_WIDTH + INDEX_WIDTH);
    str_reads_in.readbp.data   <= data(VALUES_WIDTH_READ + INDEX_WIDTH - 1 downto INDEX_WIDTH);
    str_reads_in.readbp.valid  <= valid(1);
    str_reads_in.readbp.dvalid <= dvalid(1);
    str_reads_in.readbp.last   <= last(1);

    str_reads_in.probs.count  <= data(VALUES_COUNT_WIDTH + VALUES_WIDTH + INDEX_WIDTH - 1 downto VALUES_WIDTH + INDEX_WIDTH);
    str_reads_in.probs.data   <= data(VALUES_WIDTH + INDEX_WIDTH - 1 downto INDEX_WIDTH);
    str_reads_in.probs.valid  <= valid(2);
    str_reads_in.probs.dvalid <= dvalid(2);
    str_reads_in.probs.last   <= last(2);
  end procedure;

  -----------------------------------------------------------------------------
  -- UserCore
  -----------------------------------------------------------------------------
  type state_t is (STATE_IDLE, STATE_RESET_START, STATE_REQUEST, STATE_BUSY, STATE_DONE);

  -- Control and status bits
  type cs_t is record
    reset_start : std_logic;
    done        : std_logic;
    busy        : std_logic;
  end record;

  type reg is record
    state : state_t;
    cs    : cs_t;

    command : command_t;

    regex : regex_t;

    str_elem_out : str_elem_out_t;
    str_elem_in  : str_elem_in_t;

    processed : unsigned(REG_WIDTH-1 downto 0);

    reset_units : std_logic;
  end record;

  signal r : reg;
  signal d : reg;

  -----------------------------------------------------------------------------
  -- Registers
  -----------------------------------------------------------------------------
  signal control_reset : std_logic;
  signal control_start : std_logic;

  -- Read request channel
  signal req_addr             : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal req_len              : std_logic_vector(BOTTOM_LEN_WIDTH-1 downto 0);
  signal req_valid, req_ready : std_logic;

  -- Read response channel
  signal rsp_data                       : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
  signal bus_rsp_resp                   : std_logic_vector(1 downto 0);
  signal rsp_ready, rsp_last, rsp_valid : std_logic;

  signal usercore_reset_start : std_logic;

  -----------------------------------------------------------------------------
  -- Application constants
  -----------------------------------------------------------------------------
  constant BUS_BURST_STEP_LEN : natural := BOTTOM_BURST_STEP_LEN;
  constant BUS_BURST_MAX_LEN  : natural := BOTTOM_BURST_MAX_LEN;
  constant BUS_LEN_WIDTH      : natural := BOTTOM_LEN_WIDTH;  -- 1 more than AXI

  signal cmd_ready : std_logic;

  signal s_cmd_tmp : std_logic_vector(2 * BUS_ADDR_WIDTH + 2 * INDEX_WIDTH - 1 downto 0);
  signal s_cmd     : command_t;

begin
  -----------------------------------------------------------------------------
  -- Memory Mapped Slave Registers
  -----------------------------------------------------------------------------
  write_valid <= s_axi_awvalid and s_axi_wvalid and not write_processed;

  s_axi_awready <= write_valid;
  s_axi_wready  <= write_valid;
  s_axi_bresp   <= "00";                -- Always OK
  s_axi_bvalid  <= write_processed;

  s_axi_arready <= not read_valid;

  -- Mux for reading
  -- Might want to insert a reg slice before getting it to the ColumnReaders
  -- and UserCore
  s_axi_rdata  <= mm_regs(read_address);
  s_axi_rvalid <= read_valid;
  s_axi_rresp  <= "00";                 -- Always OK

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
          when REG_STATUS_HI =>         -- no-op
          when REG_STATUS_LO =>         -- no-op
          when REG_RETURN_HI =>         -- no-op
          when REG_RETURN_LO =>         -- no-op
          when REG_RESULT    =>         -- no-op

          -- All others are writeable:
          when others =>
            mm_regs(address) <= s_axi_wdata;
        end case;
      else
        if usercore_reset_start = '1' then
          mm_regs(REG_CONTROL_LO)(0) <= '0';
        end if;
      end if;

      -- Read only register values:

      -- Status registers
      mm_regs(REG_STATUS_HI) <= (others => '0');

      mm_regs(REG_STATUS_LO)(SLV_BUS_DATA_WIDTH - 1 downto STATUS_DONE_OFFSET + 1) <= (others => '0');
      mm_regs(REG_STATUS_LO)(STATUS_DONE_OFFSET)                                   <= done;
      mm_regs(REG_STATUS_LO)(STATUS_BUSY_OFFSET)                                   <= busy;

      -- Return registers
      mm_regs(REG_RETURN_HI) <= (others => '0');
      mm_regs(REG_RETURN_LO) <= (others => '1');  -- result here
      mm_regs(REG_RESULT)    <= (others => '1');  -- result here

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

  -- Slice up (without backpressure) the control signals
  reg_settings : process(clk)
  begin
    if rising_edge(clk) then
      -- Control bits
      control_start <= mm_regs(REG_CONTROL_LO)(CONTROL_START_OFFSET);
      control_reset <= mm_regs(REG_CONTROL_LO)(CONTROL_RESET_OFFSET);
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

  m_axi_arsize <= "110";                --6 for 2^6*8 bits = 512 bits

  -- Read data channel
  m_axi_rready <= axi_top.rready;

  axi_top.rvalid <= m_axi_rvalid;
  axi_top.rdata  <= m_axi_rdata;
  axi_top.rresp  <= m_axi_rresp;
  axi_top.rlast  <= m_axi_rlast;

  -- Convert axi read address channel and read response channel
  -- Scales "len" and "size" according to the master data width
  -- and converts the Fletcher bus "len" to AXI bus "len"
  read_converter_inst : axi_read_converter generic map (
    ADDR_WIDTH        => BUS_ADDR_WIDTH,
    ID_WIDTH          => 1,
    MASTER_DATA_WIDTH => BUS_DATA_WIDTH,
    MASTER_LEN_WIDTH  => 8,
    SLAVE_DATA_WIDTH  => BUS_DATA_WIDTH,
    SLAVE_LEN_WIDTH   => BUS_LEN_WIDTH,
    SLAVE_MAX_BURST   => BUS_BURST_MAX_LEN,
    ENABLE_FIFO       => false
    )
    port map (
      clk             => clk,
      reset_n         => reset_n,
      s_bus_req_addr  => req_addr,
      s_bus_req_len   => req_len,
      s_bus_req_valid => req_valid,
      s_bus_req_ready => req_ready,
      s_bus_rsp_data  => rsp_data,
      s_bus_rsp_last  => rsp_last,
      s_bus_rsp_valid => rsp_valid,
      s_bus_rsp_ready => rsp_ready,
      m_axi_araddr    => axi_top.araddr,
      m_axi_arlen     => axi_top.arlen,
      m_axi_arvalid   => axi_top.arvalid,
      m_axi_arready   => axi_top.arready,
      m_axi_arsize    => axi_top.arsize,
      m_axi_rdata     => axi_top.rdata,
      m_axi_rlast     => axi_top.rlast,
      m_axi_rvalid    => axi_top.rvalid,
      m_axi_rready    => axi_top.rready
      );

  -----------------------------------------------------------------------------
  -- Command Stream Slice
  -----------------------------------------------------------------------------
  slice_inst : StreamSlice
    generic map (
      DATA_WIDTH => 2 * BUS_ADDR_WIDTH + 2 * INDEX_WIDTH
      ) port map (
        clk       => clk,
        reset     => d.reset_units,
        in_valid  => d.command.valid,
        in_ready  => cmd_ready,
        in_data   => d.command.firstIdx & d.command.lastIdx & d.command.ctrl,
        out_valid => s_cmd.valid,
        out_ready => s_cmd.ready,
        out_data  => s_cmd_tmp
        );

  s_cmd.ctrl     <= s_cmd_tmp(2 * BUS_ADDR_WIDTH-1 downto 0);
  s_cmd.lastIdx  <= s_cmd_tmp(2 * BUS_ADDR_WIDTH + INDEX_WIDTH - 1 downto 2 * BUS_ADDR_WIDTH);
  s_cmd.firstIdx <= s_cmd_tmp(2 * BUS_ADDR_WIDTH + 2 * INDEX_WIDTH - 1 downto 2 * BUS_ADDR_WIDTH + INDEX_WIDTH);


  -----------------------------------------------------------------------------
  -- ColumnReader Haplotypes
  -----------------------------------------------------------------------------
  hapl_cr : ColumnReader
    generic map (
      BUS_ADDR_WIDTH     => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH      => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH     => BUS_DATA_WIDTH,
      BUS_BURST_STEP_LEN => BUS_BURST_STEP_LEN,
      BUS_BURST_MAX_LEN  => BUS_BURST_MAX_LEN,
      INDEX_WIDTH        => INDEX_WIDTH,
      CFG                => "listprim(8;epc=8)",  -- char array (haplos), 8 per cycle
      -- CFG                => "list(struct(prim(8),prim(256)))",  -- struct array (reads)
      CMD_TAG_ENABLE     => false,
      CMD_TAG_WIDTH      => 1
      )
    port map (
      bus_clk   => clk,
      bus_reset => r.reset_units,
      acc_clk   => clk,
      acc_reset => r.reset_units,

      cmd_valid    => s_cmd.valid,
      cmd_ready    => s_cmd.ready,
      cmd_firstIdx => s_cmd.firstIdx,
      cmd_lastIdx  => s_cmd.lastIdx,
      cmd_ctrl     => s_cmd.ctrl,
      cmd_tag      => (others => '0'),  -- CMD_TAG_ENABLE is false

      unlock_valid => open,
      unlock_ready => '1',
      unlock_tag   => open,

      busReq_valid => req_valid,
      busReq_ready => req_ready,
      busReq_addr  => req_addr,
      busReq_len   => req_len,

      busResp_valid => rsp_valid,
      busResp_ready => rsp_ready,
      busResp_data  => rsp_data,
      busResp_last  => rsp_last,

      out_valid  => out_valid,
      out_ready  => out_ready,
      out_last   => out_last,
      out_dvalid => out_dvalid,
      out_data   => out_data
      );

  -- Output
  str_elem_out <= d.str_elem_out;

  -- Convert the stream inputs and outputs to something readable
  conv_streams_in(out_valid, out_dvalid, out_last, out_data, str_elem_in);
  conv_streams_out(str_elem_out, out_ready);

  -- Control & Status
  r_reset_start <= r.cs.reset_start;
  r_done        <= r.cs.done;
  r_busy        <= r.cs.busy;

  sm_seq : process(clk) is
  begin
    if rising_edge(clk) then
      r <= d;

      r_control_reset <= control_reset;
      r_control_start <= control_start;
      reset_start     <= r_reset_start;

      busy <= r_busy;
      done <= r_done;

      r_firstidx <= mm_regs(REG_FIRST_IDX);
      r_lastidx  <= mm_regs(REG_LAST_IDX);

      r_off_hi <= mm_regs(REG_OFF_ADDR_HI);
      r_off_lo <= mm_regs(REG_OFF_ADDR_LO);

      r_utf8_hi <= mm_regs(REG_UTF8_ADDR_HI);
      r_utf8_lo <= mm_regs(REG_UTF8_ADDR_LO);

      if control_reset = '1' then
        r.state       <= STATE_IDLE;
        r.reset_units <= '1';
      end if;
    end if;
  end process;

  sm_comb : process(r,
                    cmd_ready,
                    str_elem_in,
                    r_firstidx,
                    r_lastidx,
                    r_off_hi,
                    r_off_lo,
                    r_utf8_hi,
                    r_utf8_lo,
                    r_control_start,
                    r_control_reset)
    is
    variable v : reg;
  begin
    v               := r;
    -- Inputs:
    v.command.ready := cmd_ready;
    v.str_elem_in   := str_elem_in;

    -- Default outputs:
    v.command.valid := '0';

    v.str_elem_out.len.ready  := '0';
    v.str_elem_out.utf8.ready := '0';

    v.regex.input.valid := '0';
    v.regex.input.last  := '0';

    case v.state is
      when STATE_IDLE =>
        v.cs.done        := '0';
        v.cs.busy        := '0';
        v.cs.reset_start := '0';

        v.reset_units := '1';

        v.processed := (others => '0');

        if control_start = '1' then
          v.state          := STATE_RESET_START;
          v.cs.reset_start := '1';
        end if;

      when STATE_RESET_START =>
        v.cs.done := '0';
        v.cs.busy := '1';

        v.reset_units := '0';

        if control_start = '0' then
          v.state := STATE_REQUEST;
        end if;

      when STATE_REQUEST =>
        v.cs.done        := '0';
        v.cs.busy        := '1';
        v.cs.reset_start := '0';
        v.reset_units    := '0';

        -- First four argument registers are buffer addresses
        -- MSBs are index buffer address
        v.command.ctrl(127 downto 96) := r_off_hi;
        v.command.ctrl(95 downto 64)  := r_off_lo;
        -- LSBs are data buffer address
        v.command.ctrl(63 downto 32)  := r_utf8_hi;
        v.command.ctrl(31 downto 0)   := r_utf8_lo;

        -- Next two argument registers are first and last index
        v.command.firstIdx := r_firstidx;
        v.command.lastIdx  := r_lastidx;

        -- Make command valid
        v.command.valid := '1';

        -- Wait for command accepted
        if v.command.ready = '1' then
          dumpStdOut("Requested haplotype arrays: " & integer'image(int(v.command.firstIdx)) & " ... " & integer'image(int(v.command.lastIdx)));
          v.state := STATE_BUSY;
        end if;

      when STATE_BUSY =>
        v.cs.done        := '0';
        v.cs.busy        := '1';
        v.cs.reset_start := '0';
        v.reset_units    := '0';

        -- Always ready to receive length
        v.str_elem_out.len.ready := '1';

        if v.str_elem_in.len.valid = '1' then
          -- Do something when this is the last string
          dumpStdOut("LAST STRING");
        end if;
        if (v.str_elem_in.len.last = '1')  -- and (v.processed = u(v.command.lastIdx) - u(v.command.firstIdx)) -- TODO Laurens: add another condition to finish
        then
          dumpStdOut("Pair HMM unit is done");
          v.state := STATE_DONE;
        end if;

        -- Always ready to receive utf8 char (haplo basepair)
        v.str_elem_out.utf8.ready := '1';

        if v.str_elem_in.utf8.valid = '1' then
          -- Do something for every utf8 char (haplo basepair)
          dumpStdOut(slv8char(v.str_elem_in.utf8.data(7 downto 0)) &
                     slv8char(v.str_elem_in.utf8.data(15 downto 8)) &
                     slv8char(v.str_elem_in.utf8.data(23 downto 16)) &
                     slv8char(v.str_elem_in.utf8.data(31 downto 24)) &
                     slv8char(v.str_elem_in.utf8.data(39 downto 32)) &
                     slv8char(v.str_elem_in.utf8.data(47 downto 40)) &
                     slv8char(v.str_elem_in.utf8.data(55 downto 48)) &
                     slv8char(v.str_elem_in.utf8.data(63 downto 56))
                     );
        end if;

        if v.str_elem_in.utf8.last = '1' then
          -- Do something when this is the last utf8 char
          dumpStdOut("LAST CHAR");
        end if;

      when STATE_DONE =>
        v.cs.done        := '1';
        v.cs.busy        := '0';
        v.cs.reset_start := '0';
        v.reset_units    := '0';  -- See issue #4, otherwise this could be '1'

        if r_control_reset = '1' or r_control_start = '1' then
          v.state := STATE_IDLE;
        end if;
    end case;

    d <= v;
  end process;

end arrow_regexp;
