---------------------------------------------------------------------------------------------------
--    _____          _____  _____   _    _  __  __  __  __ 
--   |  __ \  /\    |_   _||  __ \ | |  | ||  \/  ||  \/  |
--   | |__) |/  \     | |  | |__) || |__| || \  / || \  / |
--   |  ___// /\ \    | |  |  _  / |  __  || |\/| || |\/| |
--   | |   / ____ \  _| |_ | | \ \ | |  | || |  | || |  | |
--   |_|  /_/    \_\|_____||_|  \_\|_|  |_||_|  |_||_|  |_|
--                                                         
---------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.psl.all;
  use work.functions.all;
  use work.pe_package.all;
  use work.pairhmm_package.all;

entity pairhmm_tb is 
end pairhmm_tb;

architecture bench of pairhmm_tb is
  
  constant TB_THOLD  : time := 1 ns;
  constant TB_PERIOD : time := 10 ns;

  component pe
    port (
      i                     : in  pairhmm_in;
      o                     : out pairhmm_out
    );
  end component;

  signal i        : pairhmm_in    := pairhmm_in_empty;
  signal o        : pairhmm_out;
  signal counter  : integer       := 0;
  
  signal clk : std_logic := '1';

begin

  uut: pairhmm port map ( i => i,
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
       
    i.cr.rst              <= '1';
    i.first.valid         <= '0';
    
    wait for TB_PERIOD;
     
    i.cr.rst              <= '0';
    i.first.valid         <= '0';
    
    wait until o.ready = '1';
        
    wait for TB_THOLD;
   
   i.x_all                <= x_all_actg;
   
   -- P0 First
    i.first.valid         <= '1';
    i.first.start         <= '1';         -- only at start for first pe
    i.first.mids.mtl      <= X"3f800000"; -- only at start for first pe
    i.first.tmis.alpha    <= X"3f000000";
    i.first.tmis.beta     <= X"3f000000";
    i.first.tmis.gamma    <= X"3f000000";
    i.first.tmis.delta    <= X"3f000000";
    i.first.tmis.epsilon  <= X"3f000000";
    i.first.tmis.zeta     <= X"3f000000";
    i.first.tmis.eta      <= X"3f000000";
    i.first.emis.lambda   <= X"3f000000";
    i.first.emis.theta    <= X"3f000000";
    i.first.emis.upsilon  <= X"3f000000";
    
    wait for 1 * TB_PERIOD;
    
    -- P1 First
    i.first.valid         <= '1';
    i.first.start         <= '1';         -- only at start for first pe
    i.first.mids.mtl      <= X"3f800000"; -- only at start for first pe
    i.first.tmis.alpha    <= X"3ea7f62b";
    i.first.tmis.beta     <= X"3eaf8d49";
    i.first.tmis.gamma    <= X"3eb76587";
    i.first.tmis.delta    <= X"3ebf8056";
    i.first.tmis.epsilon  <= X"3ec7df2a";
    i.first.tmis.zeta     <= X"3ed0837b";
    i.first.tmis.eta      <= X"3ed96ec7";
    i.first.emis.lambda   <= X"3ee2a28d";
    i.first.emis.theta    <= X"3eec2052";
    i.first.emis.upsilon  <= X"3ef5e99f";
    
    wait for 1 * TB_PERIOD;
    
    -- P2 First
    i.first.valid         <= '1';
    i.first.start         <= '1';         -- only at start for first pe
    i.first.mids.mtl      <= X"3f800000"; -- only at start for first pe
    i.first.tmis.alpha    <= X"3e5c6633";
    i.first.tmis.beta     <= X"3e70c4f0";
    i.first.tmis.gamma    <= X"3e836250";
    i.first.tmis.delta    <= X"3e8f40c1";
    i.first.tmis.epsilon  <= X"3e9c0cb6";
    i.first.tmis.zeta     <= X"3ea9d5ec";
    i.first.tmis.eta      <= X"3eb8acfd";
    i.first.emis.lambda   <= X"3ec8a368";
    i.first.emis.theta    <= X"3ed9cb9b";
    i.first.emis.upsilon  <= X"3eec38ff";
    
    wait for 1 * TB_PERIOD;
    
    -- P3 First
    i.first.valid         <= '1';
    i.first.start         <= '1';         -- only at start for first pe
    i.first.mids.mtl      <= X"3f800000"; -- only at start for first pe
    i.first.tmis.alpha    <= X"3e109a9b";
    i.first.tmis.beta     <= X"3e251b82";
    i.first.tmis.gamma    <= X"3e3c3ec5";
    i.first.tmis.delta    <= X"3e565241";
    i.first.tmis.epsilon  <= X"3e73abd4";
    i.first.tmis.zeta     <= X"3e8a550a";
    i.first.tmis.eta      <= X"3e9cda8c";
    i.first.emis.lambda   <= X"3eb19fa7";
    i.first.emis.theta    <= X"3ec8e332";
    i.first.emis.upsilon  <= X"3ee2ea1e";
    
    wait for 1 * TB_PERIOD;
    
    i.first.start         <= '0';
    i.first.mids.mtl      <= X"00000000"; 
    
    -- P0 Second
    i.first.valid         <= '1';
    i.first.tmis.alpha    <= X"3ee66666";
    i.first.tmis.beta     <= X"3ee8f5c3";
    i.first.tmis.gamma    <= X"3eeb851f";
    i.first.tmis.delta    <= X"3eee147b";
    i.first.tmis.epsilon  <= X"3ef0a3d7";
    i.first.tmis.zeta     <= X"3ef33333";
    i.first.tmis.eta      <= X"3ef5c28f";
    i.first.emis.lambda   <= X"3ef851ec";
    i.first.emis.theta    <= X"3efae148";
    i.first.emis.upsilon  <= X"3efd70a4";
    
    wait for 1 * TB_PERIOD;
    
    -- P1 Second
    i.first.valid         <= '1';
    i.first.tmis.alpha    <= X"3e972a5a";
    i.first.tmis.beta     <= X"3e9fc092";
    i.first.tmis.gamma    <= X"3ea8b991";
    i.first.tmis.delta    <= X"3eb218a2";
    i.first.tmis.epsilon  <= X"3ebbe122";
    i.first.tmis.zeta     <= X"3ec61682";
    i.first.tmis.eta      <= X"3ed0bc44";
    i.first.emis.lambda   <= X"3edbd5fe";
    i.first.emis.theta    <= X"3ee7675a";
    i.first.emis.upsilon  <= X"3ef37415";
    
    wait for 1 * TB_PERIOD;
    
    -- P2 Second
    i.first.valid         <= '1';
    i.first.tmis.alpha    <= X"3e465bfa";
    i.first.tmis.beta     <= X"3e5b199d";
    i.first.tmis.gamma    <= X"3e71bf22";
    i.first.tmis.delta    <= X"3e8539a9";
    i.first.tmis.epsilon  <= X"3e92afca";
    i.first.tmis.zeta     <= X"3ea15806";
    i.first.tmis.eta      <= X"3eb149e8";
    i.first.emis.lambda   <= X"3ec29e81";
    i.first.emis.theta    <= X"3ed5707e";
    i.first.emis.upsilon  <= X"3ee9dc44";
    
    wait for 1 * TB_PERIOD;
    
    -- P3 Second
    i.first.valid         <= '1';
    i.first.tmis.alpha    <= X"3e0224be";
    i.first.tmis.beta     <= X"3e163f6e";
    i.first.tmis.gamma    <= X"3e2d2f82";
    i.first.tmis.delta    <= X"3e47519e";
    i.first.tmis.epsilon  <= X"3e650d0a";
    i.first.tmis.zeta     <= X"3e836a63";
    i.first.tmis.eta      <= X"3e96945d";
    i.first.emis.lambda   <= X"3eac4b81";
    i.first.emis.theta    <= X"3ec4dea7";
    i.first.emis.upsilon  <= X"3ee0a538";
    
    wait for 1 * TB_PERIOD;
    
    -- P0 Third
    i.first.valid         <= '1';
    i.first.tmis.alpha    <= X"3ecf5c29";
    i.first.tmis.beta     <= X"3ed3fe5d";
    i.first.tmis.gamma    <= X"3ed8adac";
    i.first.tmis.delta    <= X"3edd6a16";
    i.first.tmis.epsilon  <= X"3ee2339c";
    i.first.tmis.zeta     <= X"3ee70a3d";
    i.first.tmis.eta      <= X"3eebedfa";
    i.first.emis.lambda   <= X"3ef0ded3";
    i.first.emis.theta    <= X"3ef5dcc6";
    i.first.emis.upsilon  <= X"3efae7d5";
    
    wait for 1 * TB_PERIOD;
    
    -- P1 Third
    i.first.valid         <= '1';
    i.first.tmis.alpha    <= X"3e880c84";
    i.first.tmis.beta     <= X"3e915fe1";
    i.first.tmis.gamma    <= X"3e9b3a15";
    i.first.tmis.delta    <= X"3ea5a126";
    i.first.tmis.epsilon  <= X"3eb09b4e";
    i.first.tmis.zeta     <= X"3ebc2efb";
    i.first.tmis.eta      <= X"3ec862d1";
    i.first.emis.lambda   <= X"3ed53da7";
    i.first.emis.theta    <= X"3ee2c691";
    i.first.emis.upsilon  <= X"3ef104d8";
    
    wait for 1 * TB_PERIOD;
    
    -- P2 Third
    i.first.valid         <= '1';
    i.first.tmis.alpha    <= X"3e3285fb";
    i.first.tmis.beta     <= X"3e47618d";
    i.first.tmis.gamma    <= X"3e5e682a";
    i.first.tmis.delta    <= X"3e77cc87";
    i.first.tmis.epsilon  <= X"3e89e2ae";
    i.first.tmis.zeta     <= X"3e9946d3";
    i.first.tmis.eta      <= X"3eaa3279";
    i.first.emis.lambda   <= X"3ebcc7d4";
    i.first.emis.theta    <= X"3ed12baf";
    i.first.emis.upsilon  <= X"3ee78595";
    
    wait for 1 * TB_PERIOD;
    
    -- P3 Third
    i.first.valid         <= '1';
    i.first.tmis.alpha    <= X"3dea4224";
    i.first.tmis.beta     <= X"3e08b9b9";
    i.first.tmis.gamma    <= X"3e1f54ab";
    i.first.tmis.delta    <= X"3e395dd3";
    i.first.tmis.epsilon  <= X"3e574ed1";
    i.first.tmis.zeta     <= X"3e79b089";
    i.first.tmis.eta      <= X"3e908e6e";
    i.first.emis.lambda   <= X"3ea72047";
    i.first.emis.theta    <= X"3ec0eeae";
    i.first.emis.upsilon  <= X"3ede6620";
    
    wait for 1 * TB_PERIOD;
    
    -- P0 Fourth
    i.first.valid         <= '1';
    i.first.tmis.alpha    <= X"3eba9fbe";
    i.first.tmis.beta     <= X"3ec0ea07";
    i.first.tmis.gamma    <= X"3ec75819";
    i.first.tmis.delta    <= X"3ecdea57";
    i.first.tmis.epsilon  <= X"3ed4a127";
    i.first.tmis.zeta     <= X"3edb7cee";
    i.first.tmis.eta      <= X"3ee27e0f";
    i.first.emis.lambda   <= X"3ee9a4f0";
    i.first.emis.theta    <= X"3ef0f1f5";
    i.first.emis.upsilon  <= X"3ef86584";
    
    wait for 1 * TB_PERIOD;
    
    -- P1 Fourth
    i.first.valid         <= '1';
    i.first.tmis.alpha    <= X"3e74e355";
    i.first.tmis.beta     <= X"3e844a73";
    i.first.tmis.gamma    <= X"3e8ecf09";
    i.first.tmis.delta    <= X"3e9a0911";
    i.first.tmis.epsilon  <= X"3ea602a1";
    i.first.tmis.zeta     <= X"3eb2c63c";
    i.first.tmis.eta      <= X"3ec05edd";
    i.first.emis.lambda   <= X"3eced7f7";
    i.first.emis.theta    <= X"3ede3d7a";
    i.first.emis.upsilon  <= X"3eee9bd6";
    
    wait for 1 * TB_PERIOD;
    
    -- P2 Fourth
    i.first.valid         <= '1';
    i.first.tmis.alpha    <= X"3e20abc8";
    i.first.tmis.beta     <= X"3e356fcf";
    i.first.tmis.gamma    <= X"3e4c9d45";
    i.first.tmis.delta    <= X"3e6673f9";
    i.first.tmis.epsilon  <= X"3e819cc2";
    i.first.tmis.zeta     <= X"3e919ce2";
    i.first.tmis.eta      <= X"3ea363a7";
    i.first.emis.lambda   <= X"3eb71dfe";
    i.first.emis.theta    <= X"3eccfcbb";
    i.first.emis.upsilon  <= X"3ee534e3";
    
    wait for 1 * TB_PERIOD;
    
    -- P3 Fourth
    i.first.valid         <= '1';
    i.first.tmis.alpha    <= X"3dd2d520";
    i.first.tmis.beta     <= X"3df8d723";
    i.first.tmis.gamma    <= X"3e129593";
    i.first.tmis.delta    <= X"3e2c640e";
    i.first.tmis.epsilon  <= X"3e4a63b0";
    i.first.tmis.zeta     <= X"3e6d3482";
    i.first.tmis.eta      <= X"3e8ac62c";
    i.first.emis.lambda   <= X"3ea21cc0";
    i.first.emis.theta    <= X"3ebd12dd";
    i.first.emis.upsilon  <= X"3edc2cc9";
    
    wait for 1 * TB_PERIOD;
    
    i.first.valid         <= '0';
    i.first.start         <= '0';         -- only at start for first pe
    i.first.mids.mtl      <= X"00000000"; -- only at start for first pe
    i.first.tmis.alpha    <= X"00000000";
    i.first.tmis.beta     <= X"00000000";
    i.first.tmis.gamma    <= X"00000000";
    i.first.tmis.delta    <= X"00000000";
    i.first.tmis.epsilon  <= X"00000000";
    i.first.tmis.zeta     <= X"00000000";
    i.first.tmis.eta      <= X"00000000";
    i.first.emis.lambda   <= X"00000000";
    i.first.emis.theta    <= X"00000000";
    i.first.emis.upsilon  <= X"00000000";
    
    
    wait for 100 * TB_PERIOD;
         
  end process;


end architecture;

