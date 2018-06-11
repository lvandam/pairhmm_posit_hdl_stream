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

entity pairhmm_unit is
  generic (
    -- Host bus properties
    BUS_ADDR_WIDTH : natural := 64;
    BUS_DATA_WIDTH : natural := 512;

    BUS_LEN_WIDTH      : natural := BOTTOM_LEN_WIDTH;
    BUS_BURST_STEP_LEN : natural := BOTTOM_BURST_STEP_LEN;
    BUS_BURST_MAX_LEN  : natural := BOTTOM_BURST_MAX_LEN;

    REG_WIDTH : natural := 32

   -- (Generic defaults are set for SystemVerilog compatibility)
    );

  port (
    clk     : in std_logic;
    reset_n : in std_logic;

    control_reset : in  std_logic;
    control_start : in  std_logic;
    reset_start   : out std_logic;

    busy : out std_logic;
    done : out std_logic;

    firstidx : in std_logic_vector(REG_WIDTH-1 downto 0);
    lastidx  : in std_logic_vector(REG_WIDTH-1 downto 0);

    off_hi : in std_logic_vector(REG_WIDTH-1 downto 0);
    off_lo : in std_logic_vector(REG_WIDTH-1 downto 0);

    utf8_hi : in std_logic_vector(REG_WIDTH-1 downto 0);
    utf8_lo : in std_logic_vector(REG_WIDTH-1 downto 0);

    ---------------------------------------------------------------------------
    -- Master bus Haplotype
    ---------------------------------------------------------------------------
    -- Read request channel
    bus_hapl_req_addr  : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    bus_hapl_req_len   : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    bus_hapl_req_valid : out std_logic;
    bus_hapl_req_ready : in  std_logic;

    -- Read response channel
    bus_hapl_rsp_data  : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    bus_hapl_rsp_resp  : in  std_logic_vector(1 downto 0);
    bus_hapl_rsp_last  : in  std_logic;
    bus_hapl_rsp_valid : in  std_logic;
    bus_hapl_rsp_ready : out std_logic;

    ---------------------------------------------------------------------------
    -- Master bus Reads
    ---------------------------------------------------------------------------
    -- Read request channel
    bus_read_req_addr  : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    bus_read_req_len   : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    bus_read_req_valid : out std_logic;
    bus_read_req_ready : in  std_logic;

    -- Read response channel
    bus_read_rsp_data  : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    bus_read_rsp_resp  : in  std_logic_vector(1 downto 0);
    bus_read_rsp_last  : in  std_logic;
    bus_read_rsp_valid : in  std_logic;
    bus_read_rsp_ready : out std_logic
    );
end pairhmm_unit;

architecture pairhmm_unit of pairhmm_unit is
  -- Register all ports to ease timing
  signal r_control_reset : std_logic;
  signal r_control_start : std_logic;
  signal r_reset_start   : std_logic;
  signal r_busy          : std_logic;
  signal r_done          : std_logic;
  signal r_firstidx      : std_logic_vector(REG_WIDTH - 1 downto 0);
  signal r_lastidx       : std_logic_vector(REG_WIDTH - 1 downto 0);
  signal r_off_hi        : std_logic_vector(REG_WIDTH - 1 downto 0);
  signal r_off_lo        : std_logic_vector(REG_WIDTH - 1 downto 0);
  signal r_utf8_hi       : std_logic_vector(REG_WIDTH - 1 downto 0);
  signal r_utf8_lo       : std_logic_vector(REG_WIDTH - 1 downto 0);


  -----------------------------------------------------------------------------
  -- Haplotype ColumnReader Interface
  -----------------------------------------------------------------------------
  constant INDEX_WIDTH_HAPL        : natural := 32;
  constant VALUE_ELEM_WIDTH_HAPL   : natural := 8;
  constant VALUES_PER_CYCLE_HAPL   : natural := 8;  -- burst size of 8
  constant NUM_STREAMS_HAPL        : natural := 2;  -- index stream, data stream
  constant VALUES_WIDTH_HAPL       : natural := VALUE_ELEM_WIDTH_HAPL * VALUES_PER_CYCLE_HAPL;
  constant VALUES_COUNT_WIDTH_HAPL : natural := log2ceil(VALUES_PER_CYCLE_HAPL) + 1;
  constant OUT_DATA_WIDTH_HAPL     : natural := INDEX_WIDTH_HAPL + VALUES_WIDTH_HAPL + VALUES_COUNT_WIDTH_HAPL;

  signal out_hapl_valid  : std_logic_vector(NUM_STREAMS_HAPL - 1 downto 0);
  signal out_hapl_ready  : std_logic_vector(NUM_STREAMS_HAPL - 1 downto 0);
  signal out_hapl_last   : std_logic_vector(NUM_STREAMS_HAPL - 1 downto 0);
  signal out_hapl_dvalid : std_logic_vector(NUM_STREAMS_HAPL - 1 downto 0);
  signal out_hapl_data   : std_logic_vector(OUT_DATA_WIDTH_HAPL - 1 downto 0);

  -----------------------------------------------------------------------------
  -- Reads ColumnReader Interface
  -----------------------------------------------------------------------------
  constant INDEX_WIDTH_READ        : natural := 32;
  constant VALUE_ELEM_WIDTH_READ   : natural := 264;  -- 8 bits for read basepair, 8*32 bits for probabilities
  constant VALUES_PER_CYCLE_READ   : natural := 1;
  constant NUM_STREAMS_READ        : natural := 3;  -- index stream, data stream en nog wat
  constant VALUES_WIDTH_READ       : natural := VALUE_ELEM_WIDTH_READ * VALUES_PER_CYCLE_READ;
  constant VALUES_COUNT_WIDTH_READ : natural := log2ceil(VALUES_PER_CYCLE_READ);  -- + 1
  constant OUT_DATA_WIDTH_READ     : natural := INDEX_WIDTH_READ + VALUES_WIDTH_READ + VALUES_COUNT_WIDTH_READ;

  signal out_read_valid  : std_logic_vector(1 downto 0);
  signal out_read_ready  : std_logic_vector(1 downto 0);
  signal out_read_last   : std_logic_vector(1 downto 0);
  signal out_read_dvalid : std_logic_vector(1 downto 0);
  signal out_read_data   : std_logic_vector(OUT_DATA_WIDTH_READ - 1 downto 0);


  -----------------------------------------------------------------------------
  -- STREAM STRUCTS
  -----------------------------------------------------------------------------
  type len_stream_in_t is record
    valid  : std_logic;
    dvalid : std_logic;
    last   : std_logic;
    data   : std_logic_vector(INDEX_WIDTH_HAPL - 1 downto 0);
  end record;

  type len_stream_out_t is record
    ready : std_logic;
  end record;

  type utf8_stream_in_t is record
    valid  : std_logic;
    dvalid : std_logic;
    last   : std_logic;
    count  : std_logic_vector(VALUES_COUNT_WIDTH_HAPL - 1 downto 0);
    data   : std_logic_vector(VALUES_WIDTH_HAPL - 1 downto 0);
  end record;

  type utf8_stream_out_t is record
    ready : std_logic;
  end record;


  -----------------------------------------------------------------------------
  -- HAPLO STREAMS
  -----------------------------------------------------------------------------
  -- Command Stream
  type command_hapl_t is record
    valid    : std_logic;
    ready    : std_logic;
    firstIdx : std_logic_vector(INDEX_WIDTH_HAPL - 1 downto 0);
    lastIdx  : std_logic_vector(INDEX_WIDTH_HAPL - 1 downto 0);
    ctrl     : std_logic_vector(2 * BUS_ADDR_WIDTH - 1 downto 0);
  end record;

  type str_hapl_elem_in_t is record
    len  : len_stream_in_t;
    utf8 : utf8_stream_in_t;
  end record;

  type str_hapl_elem_out_t is record
    len  : len_stream_out_t;
    utf8 : utf8_stream_out_t;
  end record;

  procedure conv_streams_hapl_in (
    signal valid            : in  std_logic_vector(NUM_STREAMS_HAPL - 1 downto 0);
    signal dvalid           : in  std_logic_vector(NUM_STREAMS_HAPL - 1 downto 0);
    signal last             : in  std_logic_vector(NUM_STREAMS_HAPL - 1 downto 0);
    signal data             : in  std_logic_vector(OUT_DATA_WIDTH_HAPL - 1 downto 0);
    signal str_hapl_elem_in : out str_hapl_elem_in_t
    ) is
  begin
    str_hapl_elem_in.len.data   <= data (INDEX_WIDTH_HAPL-1 downto 0);
    str_hapl_elem_in.len.valid  <= valid (0);
    str_hapl_elem_in.len.dvalid <= dvalid(0);
    str_hapl_elem_in.len.last   <= last (0);

    str_hapl_elem_in.utf8.count  <= data(VALUES_COUNT_WIDTH_HAPL + VALUES_WIDTH_HAPL + INDEX_WIDTH_HAPL - 1 downto VALUES_WIDTH_HAPL + INDEX_WIDTH_HAPL);
    str_hapl_elem_in.utf8.data   <= data(VALUES_WIDTH_HAPL + INDEX_WIDTH_HAPL - 1 downto INDEX_WIDTH_HAPL);
    str_hapl_elem_in.utf8.valid  <= valid(1);
    str_hapl_elem_in.utf8.dvalid <= dvalid(1);
    str_hapl_elem_in.utf8.last   <= last(1);
  end procedure;

  procedure conv_streams_hapl_out (
    signal str_hapl_elem_out : in  str_hapl_elem_out_t;
    signal out_ready         : out std_logic_vector(NUM_STREAMS_HAPL - 1 downto 0)
    ) is
  begin
    out_ready(0) <= str_hapl_elem_out.len.ready;
    out_ready(1) <= str_hapl_elem_out.utf8.ready;
  end procedure;

  signal str_hapl_elem_in  : str_hapl_elem_in_t;
  signal str_hapl_elem_out : str_hapl_elem_out_t;

  signal s_cmd_hapl_tmp : std_logic_vector(2 * BUS_ADDR_WIDTH + 2 * INDEX_WIDTH_HAPL - 1 downto 0);
  signal s_cmd_hapl     : command_hapl_t;
  signal cmd_hapl_ready : std_logic;

  -----------------------------------------------------------------------------
  -- READ STREAMS
  -----------------------------------------------------------------------------
  -- Command Stream
  type command_read_t is record
    valid    : std_logic;
    ready    : std_logic;
    firstIdx : std_logic_vector(INDEX_WIDTH_READ - 1 downto 0);
    lastIdx  : std_logic_vector(INDEX_WIDTH_READ - 1 downto 0);
    ctrl     : std_logic_vector(NUM_STREAMS_READ * BUS_ADDR_WIDTH - 1 downto 0);
  end record;

  type read_data_stream_in_t is record
    valid  : std_logic;
    dvalid : std_logic;
    last   : std_logic;
    count  : std_logic_vector(VALUES_COUNT_WIDTH_READ - 1 downto 0);
    data   : std_logic_vector(VALUES_WIDTH_READ - 1 downto 0);
  end record;

  type read_data_stream_out_t is record
    ready : std_logic;
  end record;

  type str_read_elem_in_t is record
    len  : len_stream_in_t;
    -- utf8 : utf8_stream_in_t;
    data : read_data_stream_in_t;
  end record;

  type str_read_elem_out_t is record
    len  : len_stream_out_t;
    -- utf8 : utf8_stream_out_t;
    data : utf8_stream_out_t;
  end record;

  procedure conv_streams_read_in (
    signal valid            : in  std_logic_vector(1 downto 0);
    signal dvalid           : in  std_logic_vector(1 downto 0);
    signal last             : in  std_logic_vector(1 downto 0);
    signal data             : in  std_logic_vector(OUT_DATA_WIDTH_READ - 1 downto 0);
    signal str_read_elem_in : out str_read_elem_in_t
    ) is
  begin
    -- TODO do something with the data
    str_read_elem_in.len.data   <= data (INDEX_WIDTH_READ - 1 downto 0);
    str_read_elem_in.len.valid  <= valid (0);
    str_read_elem_in.len.dvalid <= dvalid(0);
    str_read_elem_in.len.last   <= last (0);

    str_read_elem_in.data.count  <= data(VALUES_COUNT_WIDTH_READ + VALUES_WIDTH_READ + INDEX_WIDTH_READ - 1 downto VALUES_WIDTH_READ + INDEX_WIDTH_READ);
    str_read_elem_in.data.data   <= data(VALUES_WIDTH_READ + INDEX_WIDTH_READ - 1 downto INDEX_WIDTH_READ);
    str_read_elem_in.data.valid  <= valid(1);
    str_read_elem_in.data.dvalid <= dvalid(1);
    str_read_elem_in.data.last   <= last(1);
  end procedure;

  procedure conv_streams_read_out (
    signal str_read_elem_out : in  str_read_elem_out_t;
    signal out_ready         : out std_logic_vector(1 downto 0)
    ) is
  begin
    out_ready(0) <= str_read_elem_out.len.ready;
    out_ready(1) <= str_read_elem_out.data.ready;
  end procedure;

  signal str_read_elem_in  : str_read_elem_in_t;
  signal str_read_elem_out : str_read_elem_out_t;

  signal s_cmd_read_tmp : std_logic_vector(NUM_STREAMS_READ * BUS_ADDR_WIDTH + 2 * INDEX_WIDTH_READ - 1 downto 0);
  signal s_cmd_read     : command_read_t;
  signal cmd_read_ready : std_logic;

  -----------------------------------------------------------------------------
  -- UserCore
  -----------------------------------------------------------------------------
  type state_t is (STATE_IDLE, STATE_RESET_START, STATE_REQUEST, STATE_BUSY, STATE_DONE);

  type regex_in_t is record
    valid : std_logic;
    data  : std_logic_vector(VALUES_WIDTH_HAPL - 1 downto 0);
    mask  : std_logic_vector(VALUES_PER_CYCLE_HAPL - 1 downto 0);
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

  -- Control and status bits
  type cs_t is record
    reset_start : std_logic;
    done        : std_logic;
    busy        : std_logic;
  end record;

  type reg is record
    state : state_t;
    cs    : cs_t;

    command_hapl : command_hapl_t;
    command_read : command_read_t;

    regex : regex_t;

    str_hapl_elem_out : str_hapl_elem_out_t;
    str_hapl_elem_in  : str_hapl_elem_in_t;

    str_read_elem_out : str_read_elem_out_t;
    str_read_elem_in  : str_read_elem_in_t;

    processed : unsigned(REG_WIDTH - 1 downto 0);

    reset_units : std_logic;
  end record;

  signal r : reg;
  signal d : reg;

begin

  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- HAPLOTYPES
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- Command Stream Slice
  -----------------------------------------------------------------------------
  slice_inst_hapl : StreamSlice
    generic map (
      DATA_WIDTH => 2 * BUS_ADDR_WIDTH + 2 * INDEX_WIDTH_HAPL
      ) port map (
        clk       => clk,
        reset     => d.reset_units,
        in_valid  => d.command_hapl.valid,
        in_ready  => cmd_hapl_ready,
        in_data   => d.command_hapl.firstIdx & d.command_hapl.lastIdx & d.command_hapl.ctrl,
        out_valid => s_cmd_hapl.valid,
        out_ready => s_cmd_hapl.ready,
        out_data  => s_cmd_hapl_tmp
        );

  s_cmd_hapl.ctrl     <= s_cmd_hapl_tmp(2 * BUS_ADDR_WIDTH - 1 downto 0);
  s_cmd_hapl.lastIdx  <= s_cmd_hapl_tmp(2 * BUS_ADDR_WIDTH + INDEX_WIDTH_HAPL - 1 downto 2 * BUS_ADDR_WIDTH);
  s_cmd_hapl.firstIdx <= s_cmd_hapl_tmp(2 * BUS_ADDR_WIDTH + 2 * INDEX_WIDTH_HAPL - 1 downto 2 * BUS_ADDR_WIDTH + INDEX_WIDTH_HAPL);

  -----------------------------------------------------------------------------
  -- ColumnReader
  -----------------------------------------------------------------------------
  hapl_cr : ColumnReader
    generic map (
      BUS_ADDR_WIDTH     => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH      => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH     => BUS_DATA_WIDTH,
      BUS_BURST_STEP_LEN => BUS_BURST_STEP_LEN,
      BUS_BURST_MAX_LEN  => BUS_BURST_MAX_LEN,
      INDEX_WIDTH        => INDEX_WIDTH_HAPL,
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

      cmd_valid    => s_cmd_hapl.valid,
      cmd_ready    => s_cmd_hapl.ready,
      cmd_firstIdx => s_cmd_hapl.firstIdx,
      cmd_lastIdx  => s_cmd_hapl.lastIdx,
      cmd_ctrl     => s_cmd_hapl.ctrl,
      cmd_tag      => (others => '0'),  -- CMD_TAG_ENABLE is false

      unlock_valid => open,
      unlock_ready => '1',
      unlock_tag   => open,

      busReq_valid => bus_hapl_req_valid,
      busReq_ready => bus_hapl_req_ready,
      busReq_addr  => bus_hapl_req_addr,
      busReq_len   => bus_hapl_req_len,

      busResp_valid => bus_hapl_rsp_valid,
      busResp_ready => bus_hapl_rsp_ready,
      busResp_data  => bus_hapl_rsp_data,
      busResp_last  => bus_hapl_rsp_last,

      out_valid  => out_hapl_valid,
      out_ready  => out_hapl_ready,
      out_last   => out_hapl_last,
      out_dvalid => out_hapl_dvalid,
      out_data   => out_hapl_data
      );

  -----------------------------------------------------------------------------
  -- Stream Conversion
  -----------------------------------------------------------------------------
  -- Output
  str_hapl_elem_out <= d.str_hapl_elem_out;

  -- Convert the stream inputs and outputs to something readable
  conv_streams_hapl_in(out_hapl_valid, out_hapl_dvalid, out_hapl_last, out_hapl_data, str_hapl_elem_in);
  conv_streams_hapl_out(str_hapl_elem_out, out_hapl_ready);


  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- READS
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- Command Stream Slice
  -----------------------------------------------------------------------------
  slice_inst_read : StreamSlice
    generic map (
      DATA_WIDTH => NUM_STREAMS_READ * BUS_ADDR_WIDTH + 2 * INDEX_WIDTH_READ
      ) port map (
        clk       => clk,
        reset     => d.reset_units,
        in_valid  => d.command_read.valid,
        in_ready  => cmd_read_ready,
        in_data   => d.command_read.firstIdx & d.command_read.lastIdx & d.command_read.ctrl,
        out_valid => s_cmd_read.valid,
        out_ready => s_cmd_read.ready,
        out_data  => s_cmd_read_tmp
        );

  s_cmd_read.ctrl     <= s_cmd_read_tmp(NUM_STREAMS_READ * BUS_ADDR_WIDTH - 1 downto 0);
  s_cmd_read.lastIdx  <= s_cmd_read_tmp(NUM_STREAMS_READ * BUS_ADDR_WIDTH + INDEX_WIDTH_READ - 1 downto NUM_STREAMS_READ * BUS_ADDR_WIDTH);
  s_cmd_read.firstIdx <= s_cmd_read_tmp(NUM_STREAMS_READ * BUS_ADDR_WIDTH + 2 * INDEX_WIDTH_READ - 1 downto NUM_STREAMS_READ * BUS_ADDR_WIDTH + INDEX_WIDTH_READ);

  -----------------------------------------------------------------------------
  -- ColumnReader
  -----------------------------------------------------------------------------
  read_cr : ColumnReader
    generic map (
      BUS_ADDR_WIDTH     => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH      => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH     => BUS_DATA_WIDTH,
      BUS_BURST_STEP_LEN => BUS_BURST_STEP_LEN,
      BUS_BURST_MAX_LEN  => BUS_BURST_MAX_LEN,
      INDEX_WIDTH        => INDEX_WIDTH_READ,
      -- CFG                => "listprim(8;epc=8)",  -- char array (haplos), 8 per cycle
      CFG                => "list(struct(prim(8),prim(256)))",  -- struct array (reads)
      CMD_TAG_ENABLE     => false,
      CMD_TAG_WIDTH      => 1
      )
    port map (
      bus_clk   => clk,
      bus_reset => r.reset_units,
      acc_clk   => clk,
      acc_reset => r.reset_units,

      cmd_valid    => s_cmd_read.valid,
      cmd_ready    => s_cmd_read.ready,
      cmd_firstIdx => s_cmd_read.firstIdx,
      cmd_lastIdx  => s_cmd_read.lastIdx,
      cmd_ctrl     => s_cmd_read.ctrl,
      cmd_tag      => (others => '0'),  -- CMD_TAG_ENABLE is false

      unlock_valid => open,
      unlock_ready => '1',
      unlock_tag   => open,

      busReq_valid => bus_read_req_valid,
      busReq_ready => bus_read_req_ready,
      busReq_addr  => bus_read_req_addr,
      busReq_len   => bus_read_req_len,

      busResp_valid => bus_read_rsp_valid,
      busResp_ready => bus_read_rsp_ready,
      busResp_data  => bus_read_rsp_data,
      busResp_last  => bus_read_rsp_last,

      out_valid  => out_read_valid,
      out_ready  => out_read_ready,
      out_last   => out_read_last,
      out_dvalid => out_read_dvalid,
      out_data   => out_read_data
      );

  -----------------------------------------------------------------------------
  -- Stream Conversion
  -----------------------------------------------------------------------------
  -- Output
  str_read_elem_out <= d.str_read_elem_out;

  -- Convert the stream inputs and outputs to something readable
  conv_streams_read_in(out_read_valid, out_read_dvalid, out_read_last, out_read_data, str_read_elem_in);
  conv_streams_read_out(str_read_elem_out, out_read_ready);


  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- CONTROL & STATUS
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
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

      r_firstidx <= firstidx;
      r_lastidx  <= lastidx;

      r_off_hi <= off_hi;
      r_off_lo <= off_lo;

      r_utf8_hi <= utf8_hi;
      r_utf8_lo <= utf8_lo;

      if control_reset = '1' then
        r.state       <= STATE_IDLE;
        r.reset_units <= '1';
      end if;
    end if;
  end process;

  sm_comb : process(r,
                    cmd_hapl_ready,
                    cmd_read_ready,
                    str_hapl_elem_in,
                    str_read_elem_in,
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
    v                    := r;
    -- Inputs:
    v.command_hapl.ready := cmd_hapl_ready;
    v.command_read.ready := cmd_read_ready;

    v.str_hapl_elem_in := str_hapl_elem_in;
    v.str_read_elem_in := str_read_elem_in;

    -- Default outputs:
    v.command_hapl.valid := '0';
    v.command_read.valid := '0';

    v.str_hapl_elem_out.len.ready  := '0';
    v.str_hapl_elem_out.utf8.ready := '0';

    v.str_read_elem_out.len.ready  := '0';
    v.str_read_elem_out.data.ready := '0';

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
        v.command_hapl.ctrl(127 downto 96) := r_off_hi;
        v.command_hapl.ctrl(95 downto 64)  := r_off_lo;
        v.command_read.ctrl(127 downto 96) := (others => '0');  -- TODO
        v.command_read.ctrl(95 downto 64)  := (others => '0');  -- TODO
        -- LSBs are data buffer address
        v.command_hapl.ctrl(63 downto 32)  := r_utf8_hi;
        v.command_hapl.ctrl(31 downto 0)   := r_utf8_lo;
        v.command_read.ctrl(63 downto 32)  := (others => '0');  -- TODO
        v.command_read.ctrl(31 downto 0)   := (others => '0');  -- TODO

        -- Next two argument registers are first and last index
        v.command_hapl.firstIdx := r_firstidx;
        v.command_read.firstIdx := (others => '0');  -- TODO

        v.command_hapl.lastIdx := r_lastidx;
        v.command_read.lastIdx := (others => '0');  -- TODO

        -- Make command valid
        v.command_hapl.valid := '1';
        v.command_read.valid := '0';

        -- Wait for command accepted
        if v.command_hapl.ready = '1' then
          dumpStdOut("Requested haplotype arrays: " & integer'image(int(v.command_hapl.firstIdx)) & " ... " & integer'image(int(v.command_hapl.lastIdx)));
          v.state := STATE_BUSY;
        end if;

      when STATE_BUSY =>
        v.cs.done        := '0';
        v.cs.busy        := '1';
        v.cs.reset_start := '0';
        v.reset_units    := '0';

        -- Always ready to receive length
        v.str_hapl_elem_out.len.ready := '1';
        v.str_read_elem_out.len.ready := '1';  -- TODO

        if v.str_hapl_elem_in.len.valid = '1' then
          -- Do something when this is the last string
          dumpStdOut("LAST STRING");
        end if;
        if (v.str_hapl_elem_in.len.last = '1' and (v.processed = u(v.command_hapl.lastIdx) - u(v.command_hapl.firstIdx)))  -- TODO Laurens: add another condition to finish
        then
          dumpStdOut("Pair HMM unit is done");
          v.state := STATE_DONE;
        end if;

        -- Always ready to receive utf8 char (haplo basepair)
        v.str_hapl_elem_out.utf8.ready := '1';
        v.str_read_elem_out.data.ready := '1';  -- TODO

        if v.str_hapl_elem_in.utf8.valid = '1' then
          -- Do something for every utf8 char (haplo basepair)
          dumpStdOut(slv8char(v.str_hapl_elem_in.utf8.data(7 downto 0)) &
                     slv8char(v.str_hapl_elem_in.utf8.data(15 downto 8)) &
                     slv8char(v.str_hapl_elem_in.utf8.data(23 downto 16)) &
                     slv8char(v.str_hapl_elem_in.utf8.data(31 downto 24)) &
                     slv8char(v.str_hapl_elem_in.utf8.data(39 downto 32)) &
                     slv8char(v.str_hapl_elem_in.utf8.data(47 downto 40)) &
                     slv8char(v.str_hapl_elem_in.utf8.data(55 downto 48)) &
                     slv8char(v.str_hapl_elem_in.utf8.data(63 downto 56))
                     );
        end if;

        if v.str_hapl_elem_in.utf8.last = '1' then
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
end pairhmm_unit;
