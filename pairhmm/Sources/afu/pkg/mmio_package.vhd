library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.psl.all;
  use work.cu_package.all;

package mmio_package is

----------------------------------------------------------------------------------------------------------------------- parameters

  -- doubleword (64-bit) mmio's must have even addresses
  constant MMIO_REG_ADDRESS   : unsigned(PSL_MMIO_ADDRESS_WIDTH - 1 downto 0) := x"fffffe";
  constant MMIO_PAIRHMM_CONTROL : unsigned(PSL_MMIO_ADDRESS_WIDTH - 1 downto 0) := x"000000";
  constant MMIO_PAIRHMM_SIZE    : unsigned(PSL_MMIO_ADDRESS_WIDTH - 1 downto 0) := x"000002";
  constant MMIO_PAIRHMM_STATUS  : unsigned(PSL_MMIO_ADDRESS_WIDTH - 1 downto 0) := x"000004";
  constant MMIO_PAIRHMM_REQS    : unsigned(PSL_MMIO_ADDRESS_WIDTH - 1 downto 0) := x"000006";
  constant MMIO_PAIRHMM_REPS    : unsigned(PSL_MMIO_ADDRESS_WIDTH - 1 downto 0) := x"000008";
  constant MMIO_PAIRHMM_FIFO    : unsigned(PSL_MMIO_ADDRESS_WIDTH - 1 downto 0) := x"00000A";
  constant MMIO_PAIRHMM_FIFO_RVS: unsigned(PSL_MMIO_ADDRESS_WIDTH - 1 downto 0) := x"00000C";
  constant MMIO_PAIRHMM_FIFO_WAS: unsigned(PSL_MMIO_ADDRESS_WIDTH - 1 downto 0) := x"00000E";

----------------------------------------------------------------------------------------------------------------------- io

  type mmio_ac_in is record
    data                    : std_logic_vector(PSL_MMIO_DATA_WIDTH - 1 downto 0);
  end record;

  type mmio_in is record
    cr                      : cr_in;
    ac                      : mmio_ac_in;
    ha                      : psl_mmio_in;
    mmio_regs               : pairhmm_mmio_regs_out;
  end record;

  type mmio_out is record
    ah                      : psl_mmio_out;
    mmio_regs               : pairhmm_mmio_regs_in;
  end record;

----------------------------------------------------------------------------------------------------------------------- internals

  type mmio_int is record
    ack                     : std_logic;
    cfg_read                : std_logic;
    cfg_write               : std_logic;
    cfg_data                : std_logic_vector(PSL_MMIO_DATA_WIDTH - 1 downto 0);
    mmio_read               : std_logic;
    mmio_write              : std_logic;
    mmio_dw                 : std_logic;
    mmio_wdata              : std_logic_vector(PSL_MMIO_DATA_WIDTH - 1 downto 0);
    mmio_rdata              : std_logic_vector(PSL_MMIO_DATA_WIDTH - 1 downto 0);
    reg                     : std_logic_vector(PSL_MMIO_DATA_WIDTH - 1 downto 0);
    mmio_regs               : pairhmm_mmio_regs;
  end record;

----------------------------------------------------------------------------------------------------------------------- functions + procedures

  procedure mmio_reset (signal r : inout mmio_int);

end package mmio_package;

package body mmio_package is

  procedure mmio_reset (signal r : inout mmio_int) is
  begin
    r.ack                   <= '0';
    r.cfg_read              <= '0';
    r.cfg_write             <= '0';
    r.cfg_data              <= (others => '0');
    r.mmio_read             <= '0';
    r.mmio_write            <= '0';
    r.mmio_dw               <= '0';
    r.mmio_wdata            <= (others => '0');
    r.mmio_rdata            <= (others => '0');
    r.reg                   <= (others => '0');
  end procedure mmio_reset;

end package body mmio_package;
