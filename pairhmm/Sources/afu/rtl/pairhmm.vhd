---------------------------------------------------------------------------------------------------
--    _____      _      _    _ __  __ __  __
--   |  __ \    (_)    | |  | |  \/  |  \/  |
--   | |__) |_ _ _ _ __| |__| | \  / | \  / |
--   |  ___/ _` | | '__|  __  | |\/| | |\/| |
--   | |  | (_| | | |  | |  | | |  | | |  | |
--   |_|   \__,_|_|_|  |_|  |_|_|  |_|_|  |_|
---------------------------------------------------------------------------------------------------
-- PairHMM core in which the systolic array is generated
---------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.psl.all;
  use work.functions.all;
  use work.pe_package.all;
  use work.pairhmm_package.all;

entity pairhmm is
  port (
    cr  : in  cr_in;
    i   : in  pairhmm_in;
    o   : out pairhmm_out
  );
end entity pairhmm;

architecture logic of pairhmm is

  type      pe_ins_type     is  array (0 to PAIRHMM_NUM_PES - 1) of pe_in;
  type      pe_outs_type    is  array (0 to PAIRHMM_NUM_PES - 1) of pe_out;

  signal    pe_ins          : pe_ins_type;
  signal    pe_outs         : pe_outs_type;

  signal    en              : std_logic;

  signal    x               : x_array_type    := x_array_empty;

  -- Match X ram latency of 2:
  signal    pairhmm_in_reg  : pe_in     := pe_in_empty;
  signal    schedule_reg    : unsigned(PE_DEPTH_BITS-1 downto 0);
  signal    x_reg           : bp_type;
  signal    pe_y_data_regs  : pe_y_data_regs_type := pe_y_data_regs_empty;

  signal    pe_out_reg      : pe_out;

  type      result_array_type is array (0 to PE_DEPTH-1) of prob;
  type      i_delay_type      is array (0 to 2*PE_ADD_CYCLES-1) of prob;

  signal    i_delay         : i_delay_type;
  signal    i_valid_delay   : std_logic_vector(2*PE_ADD_CYCLES-1 downto 0);
  signal    result_rst      : std_logic := '0';



  signal    addm_ina        : prob;
  signal    addm_ina_valid  : std_logic;
  signal    addm_inb        : prob;
  signal    addm_inb_valid  : std_logic;
  signal    addm_out, addm_out_buf        : prob; -- Laurens: 1 extra delay (11 -> 12 cycles latency)
  signal    addm_out_valid, addm_out_valid_buf  : std_logic;

  signal    addi_ina        : prob;
  signal    addi_ina_valid  : std_logic;
  signal    addi_inb        : prob;
  signal    addi_inb_valid  : std_logic;
  signal    addi_out, addi_out_buf        : prob;
  signal    addi_out_valid, addi_out_valid_buf  : std_logic;

  signal    res_acc         : prob;
  signal    res_acc_valid   : std_logic;

  type      res_array       is array (0 to PAIRHMM_NUM_PES-1) of prob;

  signal    res_rst         : std_logic;
  signal    resm            : res_array;
  signal    resi            : res_array;

  signal    resbusm         : prob;
  signal    resbusi         : prob;

  signal    rm              : prob;
  signal    ri              : prob;

  signal    acc             : acc_state := resetting;
  signal    lastlast        : std_logic;
  signal    lastlast1       : std_logic;

    COMPONENT FPADD_11
      PORT (
        aclk : IN STD_LOGIC;
        s_axis_a_tvalid : IN STD_LOGIC;
        s_axis_a_tdata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        s_axis_b_tvalid : IN STD_LOGIC;
        s_axis_b_tdata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        m_axis_result_tvalid : OUT STD_LOGIC;
        m_axis_result_tdata : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
      );
    END COMPONENT;
begin

  -- Connect input to the input register before the first PE
  pe_ins(0).en              <= pairhmm_in_reg.en;
  pe_ins(0).valid           <= pairhmm_in_reg.valid;
  pe_ins(0).cell            <= pairhmm_in_reg.cell;
  pe_ins(0).initial         <= pairhmm_in_reg.initial;
  pe_ins(0).tmis            <= pairhmm_in_reg.tmis;
  pe_ins(0).emis            <= pairhmm_in_reg.emis;
  pe_ins(0).mids            <= pairhmm_in_reg.mids;
  pe_ins(0).y               <= pe_y_data_regs(0)(idx(schedule_reg));
  pe_ins(0).x               <= x_reg;

  -- Generate all the PE's
  P:
  for K in 0 to PAIRHMM_NUM_PES-1 generate

    -- Instantiate First PE
    F: if K = 0 generate
      PECORE: entity work.pe generic map (FIRST => '1') port map (cr => cr, i => pe_ins(K), o => pe_outs(K));
    end generate;

    -- Instantiate Other PE's
    O: if K /= 0 generate
      PECORE: entity work.pe port map (cr => cr, i => pe_ins(K), o => pe_outs(K));
    end generate;

    -- Attach output of current PE to Next PE
    -- but only if it's not the last PE
    N: if K /= PAIRHMM_NUM_PES-1 generate
      pe_ins(K+1).en        <= en;
      pe_ins(K+1).valid     <= pe_outs(K).valid;
      pe_ins(K+1).cell      <= pe_outs(K).cell;
      pe_ins(K+1).initial   <= pe_outs(K).initial;
      pe_ins(K+1).tmis      <= pe_outs(K).tmis;
      pe_ins(K+1).emis      <= pe_outs(K).emis;
      pe_ins(K+1).mids      <= pe_outs(K).mids;
      pe_ins(K+1).x         <= pe_outs(K).x;
      pe_ins(K+1).y         <= pe_y_data_regs(K+1)(idx(schedule_reg));
    end generate;

  end generate;

  -- Connect last PE outputs to pairhmm outputs

  o.last                    <= pe_out_reg;
  o.ready                   <= pe_out_reg.ready;

  regs: process(cr.clk)
  begin
    if rising_edge(cr.clk) then
      if cr.rst = '1' then
        pe_out_reg.valid    <= '0';
      else
        pe_out_reg          <= pe_outs(PAIRHMM_NUM_PES - 1);

        -- Clock in all inputs
        if i.ybus.wren = '1' then
          pe_y_data_regs(idx(i.ybus.addr))  <= i.ybus.data;
        end if;

        pairhmm_in_reg                    <= i.first;
        x_reg                             <= i.x;
        schedule_reg                      <= i.schedule;
      end if;
    end if;
  end process;

---------------------------------------------------------------------------------------------------
--  _____                 _ _                                            _       _
-- |  __ \               | | |       /\                                 | |     | |
-- | |__) |___  ___ _   _| | |_     /  \   ___ ___ _   _ _ __ ___  _   _| | __ _| |_ ___  _ __
-- |  _  // _ \/ __| | | | | __|   / /\ \ / __/ __| | | | '_ ` _ \| | | | |/ _` | __/ _ \| '__|
-- | | \ \  __/\__ \ |_| | | |_   / ____ \ (_| (__| |_| | | | | | | |_| | | (_| | || (_) | |
-- |_|  \_\___||___/\__,_|_|\__| /_/    \_\___\___|\__,_|_| |_| |_|\__,_|_|\__,_|\__\___/|_|
---------------------------------------------------------------------------------------------------

  -- Result bus
  process(cr.clk)
    variable vbusm : prob;
    variable vbusi : prob;
  begin
    if rising_edge(cr.clk) then
      -- Go over all PEs
      for K in 0 to PAIRHMM_NUM_PES-1 loop
        -- If its output is at the bottom
        if  (    pe_outs(K).cell = PE_BOTTOM  -- add when it's bottom PE
            or  pe_outs(K).cell = PE_LAST)    -- or last PE
            and pe_outs(K).y /= BP_STOP       -- but not when the PE is bypassing in the horizontal direction
        then
          resm(K) <= pe_outs(K).mids.ml;
          resi(K) <= pe_outs(K).mids.il;
        else
          resm(K) <= (others => '0');
          resi(K) <= (others => '0');
        end if;
      end loop;

      -- OR everything, latency is 1
      vbusm := (others => '0');
      vbusi := (others => '0');
      for K in 0 to PAIRHMM_NUM_PES-1 loop
        vbusm := vbusm or resm(K);
        vbusi := vbusi or resi(K);
      end loop;

      -- Place on bus, latency is 2
      resbusm <= vbusm;
      resbusi <= vbusi;

      -- Check if last PE is at last cell update
      if pe_outs(PAIRHMM_NUM_PES-1).cell = PE_LAST then lastlast  <= '1';
      else lastlast  <= '0';
      end if;

      lastlast1 <= lastlast; -- match latency of 2
    end if;
  end process;

  add_m : FPADD_11 port map (
    aclk                    => cr.clk,
    s_axis_a_tvalid         => addm_ina_valid,
    s_axis_a_tdata          => addm_ina,
    s_axis_b_tvalid         => addm_inb_valid,
    s_axis_b_tdata          => addm_inb,
    m_axis_result_tvalid    => addm_out_valid,
    m_axis_result_tdata     => addm_out
  );

  add_i : FPADD_11 port map (
    aclk                    => cr.clk,
    s_axis_a_tvalid         => addi_ina_valid,
    s_axis_a_tdata          => addi_ina,
    s_axis_b_tvalid         => addi_inb_valid,
    s_axis_b_tdata          => addi_inb,
    m_axis_result_tvalid    => addi_out_valid,
    m_axis_result_tdata     => addi_out
  );

  process(cr.clk)
    variable rescounter : integer range 0 to PE_DEPTH := 0;
    variable prevlast : std_logic;
  begin
    if rising_edge(cr.clk) then
      if cr.rst = '1' then
        acc <= resetting;
        o.score_valid <= '0';
      else
        -- Delayed signals:
        i_valid_delay(0)    <= lastlast1;
        rm                  <= resbusm;
        i_delay(0)          <= resbusi;
        -- Laurens: 1 extra delay (11 -> 12 cycles latency)
        addm_out_buf <= addm_out;
        addm_out_valid_buf <= addm_out_valid;
        addi_out_buf <= addi_out;
        addi_out_valid_buf <= addi_out_valid;

        for K in 1 to 2*PE_ADD_CYCLES - 1 loop
          i_delay(K)        <= i_delay(K-1);
          i_valid_delay(K)  <= i_valid_delay(K-1);
        end loop;

        -- Small state machine:
        case acc is
          when adding =>
            if lastlast = '0' and prevlast = '1' then
              acc         <= resetting;
              res_rst     <= '1';
            end if;

          when resetting =>
            rescounter          := rescounter + 1;
            if rescounter = PE_DEPTH then
              rescounter  := 0;
              acc         <= adding;
              res_rst     <= '0';
            end if;

        end case;

        prevlast := lastlast1;

        o.score       <= addi_out_buf;
        o.score_valid <= addi_out_valid_buf;
      end if;
    end if;
  end process;

  res_acc                   <= addi_out_buf        when res_rst = '0' else
                               (others => '0');

  addm_ina                  <= res_acc;
  addm_ina_valid            <= '1';

  addm_inb                  <= resbusm;
  addm_inb_valid            <= '1';

  addi_ina                  <= addm_out_buf;
  addi_ina_valid            <= addm_out_valid_buf;

  addi_inb                  <= i_delay(2*PE_ADD_CYCLES-1);
  addi_inb_valid            <= i_valid_delay(2*PE_ADD_CYCLES-1);

end architecture logic;
