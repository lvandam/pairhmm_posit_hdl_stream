
-- Copyright (C) Delft University of Technology - All Rights Reserved
-- (until further notice)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.Streams.all;
use work.Utils.all;
use work.Arrow.all;
use work.ColumnReaderConfig.all;
use work.ColumnReaderConfigParse.all;

entity HaplColumnReader is
  generic (

    ---------------------------------------------------------------------------
    -- Bus metrics and configuration
    ---------------------------------------------------------------------------
    -- Bus address width.
    BUS_ADDR_WIDTH              : natural := 32;

    -- Bus burst length width.
    BUS_LEN_WIDTH               : natural := 8;

    -- Bus data width.
    BUS_DATA_WIDTH              : natural := 32;

    -- Number of beats in a burst step.
    BUS_BURST_STEP_LEN          : natural := 4;

    -- Maximum number of beats in a burst.
    BUS_BURST_MAX_LEN           : natural := 16;

    ---------------------------------------------------------------------------
    -- Arrow metrics and configuration
    ---------------------------------------------------------------------------
    -- Index field width.
    INDEX_WIDTH                 : natural := 32;

    ---------------------------------------------------------------------------
    -- Column metrics and configuration
    ---------------------------------------------------------------------------
    -- Enables or disables command stream tag system. When enabled, an
    -- additional output stream is created that returns tags supplied along
    -- with the command stream when all BufferReaders finish making bus
    -- requests for the command. This can be used to support chunking later.
    CMD_TAG_ENABLE              : boolean := false;

    -- Command stream tag width. Must be at least 1 to avoid null vectors.
    CMD_TAG_WIDTH               : natural := 1

  );
  port (

    ---------------------------------------------------------------------------
    -- Clock domains
    ---------------------------------------------------------------------------
    -- Rising-edge sensitive clock and active-high synchronous reset for the
    -- bus and control logic side of the BufferReader.
    bus_clk                     : in  std_logic;
    bus_reset                   : in  std_logic;

    -- Rising-edge sensitive clock and active-high synchronous reset for the
    -- accelerator side.
    acc_clk                     : in  std_logic;
    acc_reset                   : in  std_logic;

    ---------------------------------------------------------------------------
    -- Command streams
    ---------------------------------------------------------------------------
    -- Command stream input (bus clock domain). firstIdx and lastIdx represent
    -- a range of elements to be fetched from memory. firstIdx is inclusive,
    -- lastIdx is exclusive for normal buffers and inclusive for index buffers,
    -- in all cases resulting in lastIdx - firstIdx elements. The ctrl vector
    -- is a concatenation of the base address for each buffer and the null
    -- bitmap present flags, dependent on CFG.
    cmd_valid                   : in  std_logic;
    cmd_ready                   : out std_logic;
    cmd_firstIdx                : in  std_logic_vector(INDEX_WIDTH-1 downto 0);
    cmd_lastIdx                 : in  std_logic_vector(INDEX_WIDTH-1 downto 0);
    cmd_noNulls                 : in  std_logic;
    cmd_nullBase                : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    cmd_idxBase                 : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    cmd_valBase                 : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    cmd_tag                     : in  std_logic_vector(CMD_TAG_WIDTH-1 downto 0);

    -- Unlock stream (bus clock domain). Produces the chunk tags supplied by
    -- the command stream when all BufferReaders finish processing the command.
    unlock_valid                : out std_logic;
    unlock_ready                : in  std_logic := '1';
    unlock_tag                  : out std_logic_vector(CMD_TAG_WIDTH-1 downto 0);

    ---------------------------------------------------------------------------
    -- Bus access ports
    ---------------------------------------------------------------------------
    -- Bus access port (bus clock domain).
    busReq_valid                : out std_logic;
    busReq_ready                : in  std_logic;
    busReq_addr                 : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    busReq_len                  : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    busResp_valid               : in  std_logic;
    busResp_ready               : out std_logic;
    busResp_data                : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    busResp_last                : in  std_logic;

    ---------------------------------------------------------------------------
    -- User streams
    ---------------------------------------------------------------------------
    out_valid                   : out std_logic;
    out_ready                   : in  std_logic;
    out_last                    : out std_logic;
    out_dvalid                  : out std_logic;
    out_notNull                 : out std_logic;
    out_len                     : out std_logic_vector(INDEX_WIDTH-1 downto 0);

    out_el_valid                : out std_logic;
    out_el_ready                : in  std_logic;
    out_el_last                 : out std_logic;
    out_el_dvalid               : out std_logic;
    out_el_cnt                  : out std_logic_vector(0 downto 0);
    out_el_val0                 : out std_logic_vector(7 downto 0)

  );
end HaplColumnReader;

architecture Behavioral of HaplColumnReader is

  signal cmd_ctrl               : std_logic_vector(3*BUS_ADDR_WIDTH downto 0);
  signal out_valids             : std_logic_vector(1 downto 0);
  signal out_readys             : std_logic_vector(1 downto 0);
  signal out_lasts              : std_logic_vector(1 downto 0);
  signal out_dvalids            : std_logic_vector(1 downto 0);
  signal out_datas              : std_logic_vector(INDEX_WIDTH+9 downto 0);

begin

  cmd_ctrl(3*BUS_ADDR_WIDTH)    <= cmd_noNulls;
  cmd_ctrl(3*BUS_ADDR_WIDTH-1 downto 2*BUS_ADDR_WIDTH)<= cmd_nullBase;
  cmd_ctrl(2*BUS_ADDR_WIDTH-1 downto BUS_ADDR_WIDTH)<= cmd_idxBase;
  cmd_ctrl(BUS_ADDR_WIDTH-1 downto 0)<= cmd_valBase;
  out_el_valid                  <= out_valids(1);
  out_valid                     <= out_valids(0);
  out_readys(1)                 <= out_el_ready;
  out_readys(0)                 <= out_ready;
  out_el_last                   <= out_lasts(1);
  out_last                      <= out_lasts(0);
  out_el_dvalid                 <= out_dvalids(1);
  out_dvalid                    <= out_dvalids(0);
  out_el_cnt                    <= out_datas(INDEX_WIDTH+9 downto INDEX_WIDTH+9);
  out_el_val0                   <= out_datas(INDEX_WIDTH+8 downto INDEX_WIDTH+1);
  out_notNull                   <= out_datas(INDEX_WIDTH);
  out_len                       <= out_datas(INDEX_WIDTH-1 downto 0);

  -- Wrap an arbiter and register slices around the requested column reader.
  hapl_inst: ColumnReaderLevel
    generic map (
      BUS_ADDR_WIDTH            => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH             => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH            => BUS_DATA_WIDTH,
      BUS_BURST_STEP_LEN        => BUS_BURST_STEP_LEN,
      BUS_BURST_MAX_LEN         => BUS_BURST_MAX_LEN,
      INDEX_WIDTH               => INDEX_WIDTH,
      CFG                       => "arb(null(listprim(8)))",
      CMD_TAG_ENABLE            => CMD_TAG_ENABLE,
      CMD_TAG_WIDTH             => CMD_TAG_WIDTH
    )
    port map (
      bus_clk                   => bus_clk,
      bus_reset                 => bus_reset,
      acc_clk                   => acc_clk,
      acc_reset                 => acc_reset,

      cmd_valid                 => cmd_valid,
      cmd_ready                 => cmd_ready,
      cmd_firstIdx              => cmd_firstIdx,
      cmd_lastIdx               => cmd_lastIdx,
      cmd_ctrl                  => cmd_ctrl,
      cmd_tag                   => cmd_tag,

      unlock_valid              => unlock_valid,
      unlock_ready              => unlock_ready,
      unlock_tag                => unlock_tag,

      busReq_valid(0)           => busReq_valid,
      busReq_ready(0)           => busReq_ready,
      busReq_addr               => busReq_addr,
      busReq_len                => busReq_len,
      busResp_valid(0)          => busResp_valid,
      busResp_ready(0)          => busResp_ready,
      busResp_data              => busResp_data,
      busResp_last(0)           => busResp_last,

      out_valid                 => out_valids,
      out_ready                 => out_readys,
      out_last                  => out_lasts,
      out_dvalid                => out_dvalids,
      out_data                  => out_datas
    );

end Behavioral;
