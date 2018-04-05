---------------------------------------------------------------------------------------------------
--    _____          _____  _____   _    _  __  __  __  __
--   |  __ \  /\    |_   _||  __ \ | |  | ||  \/  ||  \/  |
--   | |__) |/  \     | |  | |__) || |__| || \  / || \  / |
--   |  ___// /\ \    | |  |  _  / |  __  || |\/| || |\/| |
--   | |   / ____ \  _| |_ | | \ \ | |  | || |  | || |  | |
--   |_|  /_/    \_\|_____||_|  \_\|_|  |_||_|  |_||_|  |_|
--
---------------------------------------------------------------------------------------------------
-- Processing element testbench

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.psl.all;
  use work.functions.all;
  use work.pe_package.all;

entity pe_tb is
end;

architecture bench of pe_tb is

  constant TB_THOLD  : time := 1 ns;
  constant TB_PERIOD : time := 10 ns;

  component pe
    port (
      i                     : in  pe_in;
      o                     : out pe_out
    );
  end component;

  signal i: pe_in   := pe_in_empty;
  signal o: pe_out;
  signal counter : integer := 0;

  signal clk : std_logic := '1';

begin

  uut: pe port map ( i => i,
                     o => o );

  clk         <= not clk after TB_PERIOD / 2;

  i.cr.clk    <= clk;

  cycle_counter : process(clk)
  begin
    if rising_edge(clk) then
      if i.cr.rst = '1' then
        counter <= 0;
      else
        counter <= counter + 1;
      end if;
    end if;
  end process;

  stimulus: process
  begin

    wait for TB_THOLD;

    i.cr.rst        <= '1';
    i.valid         <= '1';

    wait for 40 * TB_PERIOD;

    i.cr.rst        <= '0';
    i.valid         <= '1';

    wait for 2 * TB_PERIOD;

    i.mids.mtl      <= X"3F800000";
    i.mids.itl      <= X"3F800000";
    i.mids.dtl      <= X"3F800000";
    i.mids.mt       <= X"3F800000";
    i.mids.it       <= X"3F800000";
    i.mids.dt       <= X"3F800000";
    i.mids.ml       <= X"3F800000";
    i.mids.il       <= X"3F800000";
    i.mids.dl       <= X"3F800000";

    i.tmis.alpha    <= X"3F800000";
    i.tmis.beta     <= X"3F800000";
    i.tmis.gamma    <= X"3F800000";
    i.tmis.delta    <= X"3F800000";
    i.tmis.epsilon  <= X"3F800000";
    i.tmis.zeta     <= X"3F800000";
    i.tmis.eta      <= X"3F800000";

    i.emis.lambda   <= X"3F800000";
    i.emis.theta    <= X"3F800000";
    i.emis.upsilon  <= X"3F800000";

    wait for TB_PERIOD;

    i.cr.rst        <= '0';
    i.valid         <= '1';

    i.mids.mtl      <= X"00000000";
    i.mids.itl      <= X"00000000";
    i.mids.dtl      <= X"00000000";
    i.mids.mt       <= X"00000000";
    i.mids.it       <= X"00000000";
    i.mids.dt       <= X"00000000";
    i.mids.ml       <= X"00000000";
    i.mids.il       <= X"00000000";
    i.mids.dl       <= X"00000000";

    i.tmis.alpha    <= X"00000000";
    i.tmis.beta     <= X"00000000";
    i.tmis.gamma    <= X"00000000";
    i.tmis.delta    <= X"00000000";
    i.tmis.epsilon  <= X"00000000";
    i.tmis.zeta     <= X"00000000";
    i.tmis.eta      <= X"00000000";

    i.emis.lambda   <= X"00000000";
    i.emis.theta    <= X"00000000";
    i.emis.upsilon  <= X"00000000";

    wait for 29 * TB_PERIOD;

    i.cr.rst        <= '0';
    i.valid         <= '1';

    i.mids.mtl      <= X"3F800000";
    i.mids.itl      <= X"3F800000";
    i.mids.dtl      <= X"3F800000";
    i.mids.mt       <= X"3F800000";
    i.mids.it       <= X"3F800000";
    i.mids.dt       <= X"3F800000";
    i.mids.ml       <= X"3F800000";
    i.mids.il       <= X"3F800000";
    i.mids.dl       <= X"3F800000";

    i.tmis.alpha    <= X"3F800000";
    i.tmis.beta     <= X"3F800000";
    i.tmis.gamma    <= X"3F800000";
    i.tmis.delta    <= X"3F800000";
    i.tmis.epsilon  <= X"3F800000";
    i.tmis.zeta     <= X"3F800000";
    i.tmis.eta      <= X"3F800000";

    i.emis.lambda   <= X"3F800000";
    i.emis.theta    <= X"3F800000";
    i.emis.upsilon  <= X"3F800000";

    wait for TB_PERIOD;

    i.cr.rst        <= '0';
    i.valid         <= '1';

    i.mids.mtl      <= X"00000000";
    i.mids.itl      <= X"00000000";
    i.mids.dtl      <= X"00000000";
    i.mids.mt       <= X"00000000";
    i.mids.it       <= X"00000000";
    i.mids.dt       <= X"00000000";
    i.mids.ml       <= X"00000000";
    i.mids.il       <= X"00000000";
    i.mids.dl       <= X"00000000";

    i.tmis.alpha    <= X"00000000";
    i.tmis.beta     <= X"00000000";
    i.tmis.gamma    <= X"00000000";
    i.tmis.delta    <= X"00000000";
    i.tmis.epsilon  <= X"00000000";
    i.tmis.zeta     <= X"00000000";
    i.tmis.eta      <= X"00000000";

    i.emis.lambda   <= X"00000000";
    i.emis.theta    <= X"00000000";
    i.emis.upsilon  <= X"00000000";

    wait for 29 * TB_PERIOD;

    wait;
  end process;


end;
