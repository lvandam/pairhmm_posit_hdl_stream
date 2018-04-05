---------------------------------------------------------------------------------------------------
--    _____      _      _    _ __  __ __  __
--   |  __ \    (_)    | |  | |  \/  |  \/  |
--   | |__) |_ _ _ _ __| |__| | \  / | \  / |
--   |  ___/ _` | | '__|  __  | |\/| | |\/| |
--   | |  | (_| | | |  | |  | | |  | | |  | |
--   |_|   \__,_|_|_|  |_|  |_|_|  |_|_|  |_|
---------------------------------------------------------------------------------------------------
-- Processing Element
---------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.psl.all;
  use work.functions.all;
  use work.pe_package.all;

entity pe is
  generic (
    FIRST                   :   std_logic             := '0';   -- Not first processing element by default
    DISABLE_THETA           :   std_logic             := '1';   -- Theta is disabled by default
    DISABLE_UPSILON         :   std_logic             := '1'    -- Upsilon is disabled by default
  );
  port (
    cr                      :   in  cr_in;
    i                       :   in  pe_in;
    o                       :   out pe_out
  );
end pe;

architecture rtl of pe is
  -- Intermediate signals
  signal step               :   step_type;

  -- Shift Registers (SRs)
  signal  initial_sr        :   initial_array_pe      := (others => (others => '0'));
  signal  mids_sr           :   mids_array            := (others => mids_empty);
  signal  tmis_sr           :   transmissions_array   := (others => tmis_empty);
  signal  emis_sr           :   emissions_array       := (others => emis_empty);
  signal  valid_sr          :   valid_array           := (others => '0');
  signal  cell_sr           :   cell_array            := (others => PE_NORMAL);
  signal  x_sr              :   bps                   := bps_empty;
  signal  y_sr              :   bps                   := bps_empty;

  -- To select the right input for the last Mult
  signal  distm             :   prob;

  -- Potential outputs depening on basepairs:
  signal  o_normal          :   pe_out;
  signal  o_bypass          :   pe_out;
  signal  o_buf             :   pe_out;

  -- Gamma delay SR to match the delay of alpha + beta adder
  type    add_gamma_sr_type is  array (0 to PE_ADD_CYCLES - 1) of prob;
  signal  add_gamma_sr      :   add_gamma_sr_type     := (others => (others => '0'));

  type    mul_sr_type       is  array (0 to PE_MUL_CYCLES - 1) of prob;
  signal  mul_theta_sr      :   mul_sr_type           := (others => (others => '0'));
  signal  mul_upsilon_sr    :   mul_sr_type           := (others => (others => '0'));

  type    fp_readys_type    is  array (0 to 13) of std_logic;
  type    fp_valids_type    is  array (0 to 13) of std_logic;

  signal  fp_areadys        :   fp_readys_type;
  signal  fp_breadys        :   fp_readys_type;
  signal  fp_valids         :   fp_valids_type;

  COMPONENT FPADD_12
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

  COMPONENT FPADD_6
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

  COMPONENT FPMULT
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

---------------------------------------------------------------------------------------------------
--    _____                   _
--   |_   _|                 | |
--     | |  _ __  _ __  _   _| |_ ___
--     | | | '_ \| '_ \| | | | __/ __|
--    _| |_| | | | |_) | |_| | |_\__ \
--   |_____|_| |_| .__/ \__,_|\__|___/
--               | |
--               |_|
---------------------------------------------------------------------------------------------------

  step.init.valid         <= i.valid;
  step.init.cell          <= i.cell;

  step.init.initial       <= i.initial;

  step.init.x             <= i.x;
  step.init.y             <= i.y;

  step.init.tmis          <= i.tmis;
  step.init.emis          <= i.emis;

----------------------------------------------------------------------------------------------------------------------- Coming from the left
  step.init.mids.ml       <= i.mids.ml when i.x /= BP_STOP else o_buf.mids.ml; -- or own output when x is stop
  step.init.mids.il       <= i.mids.il when i.x /= BP_STOP else o_buf.mids.il; -- or own output when x is stop
  step.init.mids.dl       <= i.mids.dl;

----------------------------------------------------------------------------------------------------------------------- Coming from the top
  -- All top inputs can be potentially zero when working on the first row of the matrix
  step.init.mids.mt       <=  step.emult.m when i.cell /= PE_TOP else
                              prob_zero;

  -- Initial Signal I depending on if Theta mult is Disabled is True
  ISTDT: if DISABLE_THETA = '1' generate
    step.init.mids.it     <=  mul_theta_sr(PE_MUL_CYCLES-1) when i.cell /= PE_TOP else
                              prob_zero;
  end generate;

  ISTDF: if DISABLE_THETA /= '1' generate
    step.init.mids.it     <= step.emult.i when i.cell /= PE_TOP else
                              prob_zero;
  end generate;
  -- Initial Signal D depending on if Upsilon mult is Disabled is True
  ISUDT: if DISABLE_UPSILON = '1' generate
    step.init.mids.dt     <= mul_upsilon_sr(PE_MUL_CYCLES-1) when i.cell /= PE_TOP else
                              i.initial;
  end generate;
  ISUDF: if DISABLE_UPSILON /= '1' generate
    step.init.mids.dt     <= step.emult.d when i.cell /= PE_TOP else
                              i.initial;
  end generate;
----------------------------------------------------------------------------------------------------------------------- Coming from the top left
  -- Initial Signal for top left; if this is the First PE we get M,I,D [i-1][j-1] from the inputs
  ISF: if FIRST = '1' generate
    step.init.mids.mtl <= mids_sr(PE_CYCLES-1).ml when i.cell /= PE_TOP else
                          i.mids.mtl;
    step.init.mids.itl <= mids_sr(PE_CYCLES-1).il when i.cell /= PE_TOP else
                          i.mids.itl;
  end generate;
  -- Initial Signal; if this is Not the First PE we get M,I,D [i-1][j-1] from the shift registers
  ISNF: if FIRST /= '1' generate
    step.init.mids.mtl <= mids_sr(PE_CYCLES-1).ml when i.cell /= PE_TOP else
                          prob_zero;
    step.init.mids.itl <= mids_sr(PE_CYCLES-1).il when i.cell /= PE_TOP else
                          prob_zero;
  end generate;

  -- Initial Signal for D:
  step.init.mids.dtl <= mids_sr(PE_CYCLES-1).dl when i.cell /= PE_TOP else
                          i.initial;

---------------------------------------------------------------------------------------------------
--     _____ _               __     __  __       _ _   _       _ _           _   _
--    / ____| |             /_ |_  |  \/  |     | | | (_)     | (_)         | | (_)
--   | (___ | |_ ___ _ __    | (_) | \  / |_   _| | |_ _ _ __ | |_  ___ __ _| |_ _  ___  _ __  ___
--    \___ \| __/ _ \ '_ \   | |   | |\/| | | | | | __| | '_ \| | |/ __/ _` | __| |/ _ \| '_ \/ __|
--    ____) | ||  __/ |_) |  | |_  | |  | | |_| | | |_| | |_) | | | (_| (_| | |_| | (_) | | | \__ \
--   |_____/ \__\___| .__/   |_(_) |_|  |_|\__,_|_|\__|_| .__/|_|_|\___\__,_|\__|_|\___/|_| |_|___/
--                  | |                                 | |
--                  |_|                                 |_|
---------------------------------------------------------------------------------------------------
-- Transmission probabilties multiplied with M, D, I
---------------------------------------------------------------------------------------------------

  mul_alpha               : FPMULT port map (
    aclk                  => cr.clk,
    --aclken                => i.en,
    --aresetn               => not(cr.rst),
    s_axis_a_tvalid       => step.init.valid,
    --s_axis_a_tready       => fp_areadys(0),
    s_axis_a_tdata        => step.init.tmis.alpha,
    s_axis_b_tvalid       => step.init.valid,
    --s_axis_b_tready       => fp_breadys(0),
    s_axis_b_tdata        => step.init.mids.mtl,
    m_axis_result_tvalid  => fp_valids(0),
    m_axis_result_tdata   => step.trans.almtl
  );

  mul_beta                : FPMULT port map (
    aclk                  => cr.clk,
    --aclken                => i.en,
    --aresetn               => not(cr.rst),
    s_axis_a_tvalid       => step.init.valid,
    --s_axis_a_tready       => fp_areadys(1),
    s_axis_a_tdata        => step.init.tmis.beta,
    s_axis_b_tvalid       => step.init.valid,
    --s_axis_b_tready       => fp_breadys(1),
    s_axis_b_tdata        => step.init.mids.itl,
    m_axis_result_tvalid  => fp_valids(1),
    m_axis_result_tdata   => step.trans.beitl
  );

  mul_gamma               : FPMULT port map (
    aclk                  => cr.clk,
    --aclken                => i.en,
    --aresetn               => not(cr.rst),
    s_axis_a_tvalid       => step.init.valid,
    --s_axis_a_tready       => fp_areadys(2),
    s_axis_a_tdata        => step.init.tmis.beta,
    s_axis_b_tvalid       => step.init.valid,
    --s_axis_b_tready       => fp_breadys(2),
    s_axis_b_tdata        => step.init.mids.dtl,
    m_axis_result_tvalid  => fp_valids(2),
    m_axis_result_tdata   => step.trans.gadtl
  );

  mul_delta               : FPMULT port map (
    aclk                  => cr.clk,
    --aclken                => i.en,
    --aresetn               => not(cr.rst),
    s_axis_a_tvalid       => step.init.valid,
    --s_axis_a_tready       => fp_areadys(3),
    s_axis_a_tdata        => step.init.tmis.delta,
    s_axis_b_tvalid       => step.init.valid,
    --s_axis_b_tready       => fp_breadys(3),
    s_axis_b_tdata        => step.init.mids.mt,
    m_axis_result_tvalid  => fp_valids(3),
    m_axis_result_tdata   => step.trans.demt
  );

  mul_epsilon             : FPMULT port map (
    aclk                  => cr.clk,
    --aclken                => i.en,
    --aresetn               => not(cr.rst),
    s_axis_a_tvalid       => step.init.valid,
    --s_axis_a_tready       => fp_areadys(4),
    s_axis_a_tdata        => step.init.tmis.epsilon,
    s_axis_b_tvalid       => step.init.valid,
    --s_axis_b_tready       => fp_breadys(4),
    s_axis_b_tdata        => step.init.mids.it,
    m_axis_result_tvalid  => fp_valids(4),
    m_axis_result_tdata   => step.trans.epit
  );

  mul_zeta                : FPMULT port map (
    aclk                  => cr.clk,
    --aclken                => i.en,
    --aresetn               => not(cr.rst),
    s_axis_a_tvalid       => step.init.valid,
    --s_axis_a_tready       => fp_areadys(5),
    s_axis_a_tdata        => step.init.tmis.zeta,
    s_axis_b_tvalid       => step.init.valid,
    --s_axis_b_tready       => fp_breadys(5),
    s_axis_b_tdata        => step.init.mids.ml,
    m_axis_result_tvalid  => fp_valids(5),
    m_axis_result_tdata   => step.trans.zeml
  );

  mul_eta                 : FPMULT port map (
    aclk                  => cr.clk,
    --aclken                => i.en,
    --aresetn               => not(cr.rst),
    s_axis_a_tvalid       => step.init.valid,
    --s_axis_a_tready       => fp_areadys(6),
    s_axis_a_tdata        => step.init.tmis.eta,
    s_axis_b_tvalid       => step.init.valid,
    --s_axis_b_tready       => fp_breadys(6),
    s_axis_b_tdata        => step.init.mids.dl,
    m_axis_result_tvalid  => fp_valids(6),
    m_axis_result_tdata   => step.trans.etdl
  );

---------------------------------------------------------------------------------------------------
--     _____ _               ___                  _     _ _ _   _
--    / ____| |             |__ \ _      /\      | |   | (_) | (_)
--   | (___ | |_ ___ _ __      ) (_)    /  \   __| | __| |_| |_ _  ___  _ __  ___
--    \___ \| __/ _ \ '_ \    / /      / /\ \ / _` |/ _` | | __| |/ _ \| '_ \/ __|
--    ____) | ||  __/ |_) |  / /_ _   / ____ \ (_| | (_| | | |_| | (_) | | | \__ \
--   |_____/ \__\___| .__/  |____(_) /_/    \_\__,_|\__,_|_|\__|_|\___/|_| |_|___/
--                  | |
--                  |_|
---------------------------------------------------------------------------------------------------
-- Addition of the multiplied probabilities
---------------------------------------------------------------------------------------------------

  -- Substep adding alpha + beta
  add_alpha_beta          : FPADD_6 port map (
    aclk                  => cr.clk,
    --aclken                => i.en,
    --aresetn               => not(cr.rst),
    s_axis_a_tvalid       => step.init.valid,
    --s_axis_a_tready       => fp_areadys(7),
    s_axis_a_tdata        => step.trans.almtl,
    s_axis_b_tvalid       => step.init.valid,
    --s_axis_b_tready       => fp_breadys(7),
    s_axis_b_tdata        => step.trans.beitl,
    m_axis_result_tvalid  => fp_valids(7),
    m_axis_result_tdata   => step.add.albetl
  );

  -- Substep adding alpha + beta + delayed gamma
  add_alpha_beta_gamma    : FPADD_6 port map (
    aclk                  => cr.clk,
    --aclken                => i.en,
    --aresetn               => not(cr.rst),
    s_axis_a_tvalid       => step.init.valid,
    --s_axis_a_tready       => fp_areadys(8),
    s_axis_a_tdata        => step.add.albetl,
    s_axis_b_tvalid       => step.init.valid,
    --s_axis_b_tready       => fp_breadys(8),
    s_axis_b_tdata        => add_gamma_sr(PE_ADD_CYCLES-1),
    m_axis_result_tvalid  => fp_valids(8),
    m_axis_result_tdata   => step.add.albegatl
  );

  add_delta_epsilon       : FPADD_12 port map (
    aclk                  => cr.clk,
    --aclken                => i.en,
    --aresetn               => not(cr.rst),
    s_axis_a_tvalid       => step.init.valid,
    --s_axis_a_tready       => fp_areadys(9),
    s_axis_a_tdata        => step.trans.demt,
    s_axis_b_tvalid       => step.init.valid,
    --s_axis_b_tready       => fp_breadys(9),
    s_axis_b_tdata        => step.trans.epit,
    m_axis_result_tvalid  => fp_valids(9),
    m_axis_result_tdata   => step.add.deept
  );

  add_zeta_eta            : FPADD_12 port map (
    aclk                  => cr.clk,
    --aclken                => i.en,
    --aresetn               => not(cr.rst),
    s_axis_a_tvalid       => step.init.valid,
    --s_axis_a_tready       => fp_areadys(10),
    s_axis_a_tdata        => step.trans.zeml,
    s_axis_b_tvalid       => step.init.valid,
    --s_axis_b_tready       => fp_breadys(10),
    s_axis_b_tdata        => step.trans.etdl,
    m_axis_result_tvalid  => fp_valids(10),
    m_axis_result_tdata   => step.add.zeett
  );

---------------------------------------------------------------------------------------------------
--     _____ _               ____      __  __       _ _   _       _ _           _   _
--    / ____| |             |___ \ _  |  \/  |     | | | (_)     | (_)         | | (_)
--   | (___ | |_ ___ _ __     __) (_) | \  / |_   _| | |_ _ _ __ | |_  ___ __ _| |_ _  ___  _ __  ___
--    \___ \| __/ _ \ '_ \   |__ <    | |\/| | | | | | __| | '_ \| | |/ __/ _` | __| |/ _ \| '_ \/ __|
--    ____) | ||  __/ |_) |  ___) |_  | |  | | |_| | | |_| | |_) | | | (_| (_| | |_| | (_) | | | \__ \
--   |_____/ \__\___| .__/  |____/(_) |_|  |_|\__,_|_|\__|_| .__/|_|_|\___\__,_|\__|_|\___/|_| |_|___/
--                  | |                                    | |
--                  |_|                                    |_|
---------------------------------------------------------------------------------------------------
-- Step 3: Multiplication of the emission probabilities
---------------------------------------------------------------------------------------------------

  -- Mux for the final multiplication:
  process(all)
  begin
    if    y_sr(PE_BCC-1) = x_sr(PE_BCC-1)
      or  y_sr(PE_BCC-1) = BP_N
      or  x_sr(PE_BCC-1) = BP_N
    then
      distm <= step.add.emis.distm_simi;
    else
      distm <= step.add.emis.distm_diff;
    end if;
  end process;

  mul_lambda              : FPMULT port map (
    aclk                  => cr.clk,
    --aclken                => i.en,
    --aresetn               => not(cr.rst),
    s_axis_a_tvalid       => step.init.valid,
    --s_axis_a_tready       => fp_areadys(11),
    s_axis_a_tdata        => step.add.albegatl,
    s_axis_b_tvalid       => step.init.valid,
    --s_axis_b_tready       => fp_breadys(11),
    s_axis_b_tdata        => distm,
    m_axis_result_tvalid  => fp_valids(11),
    m_axis_result_tdata   => step.emult.m

  );

  THETA_OFF: if DISABLE_THETA = '1' generate
    fp_areadys(12) <= '1';
    fp_breadys(12) <= '1';
    fp_valids(12)  <= '1';
  end generate;

  THETA_MULT: if DISABLE_THETA /= '1' generate
    mul_theta               : FPMULT port map (
      aclk                  => cr.clk,
      --aclken                => i.en,
      --aresetn               => not(cr.rst),
      s_axis_a_tvalid       => step.init.valid,
      --s_axis_a_tready       => fp_areadys(12),
      s_axis_a_tdata        => step.add.deept,
      s_axis_b_tvalid       => step.init.valid,
      --s_axis_b_tready       => fp_breadys(12),
      s_axis_b_tdata        => step.add.emis.theta,
      m_axis_result_tvalid  => fp_valids(12),
      m_axis_result_tdata   => step.emult.i
    );
  end generate;

  UPSILON_OFF: if DISABLE_UPSILON = '1' generate
    fp_areadys(13) <= '1';
    fp_breadys(13) <= '1';
    fp_valids(13)  <= '1';
  end generate;

  UPSILON_MULT: if DISABLE_UPSILON /= '1' generate
    mul_upsilon             : FPMULT port map (
      aclk                  => cr.clk,
      --aclken                => i.en,
      --aresetn               => not(cr.rst),
      s_axis_a_tvalid       => step.init.valid,
      --s_axis_a_tready       => fp_areadys(13),
      s_axis_a_tdata        => step.add.zeett,
      s_axis_b_tvalid       => step.init.valid,
      --s_axis_b_tready       => fp_breadys(13),
      s_axis_b_tdata        => step.add.emis.upsilon,
      m_axis_result_tvalid  => fp_valids(13),
      m_axis_result_tdata   => step.emult.d
    );
  end generate;

---------------------------------------------------------------------------------------------------
--    ____         __  __
--   |  _ \       / _|/ _|
--   | |_) |_   _| |_| |_ ___ _ __ ___
--   |  _ <| | | |  _|  _/ _ \ '__/ __|
--   | |_) | |_| | | | ||  __/ |  \__ \
--   |____/ \__,_|_| |_| \___|_|  |___/
---------------------------------------------------------------------------------------------------
-- Shift register for gamma to match the latency of alpha+beta adder
---------------------------------------------------------------------------------------------------
  add_gamma_shift_reg : process(cr.clk)
  begin
    if rising_edge(cr.clk) then
      if cr.rst = '1' then
        -- Reset shift register:
        add_gamma_sr    <= (others => (others => '0'));
      else
        add_gamma_sr(0) <= step.trans.gadtl;
        -- Shifts:
        for I in 1 to PE_ADD_CYCLES-1 loop
            add_gamma_sr(I)    <= add_gamma_sr(I-1);
        end loop;
      end if;
    end if;
  end process;

---------------------------------------------------------------------------------------------------
-- Shift register to match the latency of the lambda multiplier in case theta and upsilon
-- are always 1.0
---------------------------------------------------------------------------------------------------
  SKIP_THETA_SR: if DISABLE_THETA = '1' generate
    skip_mul_theta_sr : process(cr.clk)
    begin
      if rising_edge(cr.clk) then
        if cr.rst = '1' then
          -- Reset shift register:
          mul_theta_sr    <= (others => (others => '0'));
        else
          mul_theta_sr(0) <= step.add.deept;
          -- Shifts:
          for I in 1 to PE_MUL_CYCLES-1 loop
              mul_theta_sr(I)    <= mul_theta_sr(I-1);
          end loop;
        end if;
      end if;
    end process;
  end generate;

  SKIP_UPSILON_SR: if DISABLE_UPSILON = '1' generate
    skip_mul_upsilon_sr : process(cr.clk)
    begin
      if rising_edge(cr.clk) then
        if cr.rst = '1' then
          -- Reset shift register:
          mul_upsilon_sr    <= (others => (others => '0'));
        else
          mul_upsilon_sr(0) <= step.add.zeett;
          -- Shifts:
          for I in 1 to PE_MUL_CYCLES-1 loop
              mul_upsilon_sr(I)    <= mul_upsilon_sr(I-1);
          end loop;
        end if;
      end if;
    end process;
  end generate;

---------------------------------------------------------------------------------------------------
-- Shift register to do the following:
-- *  Delay the transmission and emission probabilities to insert them in the proper cycle.
-- *  Delay the M, I and D from the top left cell with one full iteration.
---------------------------------------------------------------------------------------------------
  constants_shift : process(cr.clk)
  begin
    if rising_edge(cr.clk) then
      if cr.rst = '1' then
        -- Reset shift register:
        initial_sr        <= (others => (others => '0'));
        mids_sr           <= (others => mids_empty);
        tmis_sr           <= (others => tmis_empty);
        emis_sr           <= (others => emis_empty);
        valid_sr          <= (others => '0');
        cell_sr           <= (others => PE_NORMAL);
        x_sr              <= bps_empty;
        y_sr              <= bps_empty;
      else
        -- Inputs:
        initial_sr(0)     <= step.init.initial;
        mids_sr(0)        <= step.init.mids;
        tmis_sr(0)        <= step.init.tmis;
        emis_sr(0)        <= step.init.emis;
        valid_sr(0)       <= step.init.valid;
        cell_sr(0)        <= step.init.cell;
        x_sr(0)           <= step.init.x;
        y_sr(0)           <= step.init.y;

        -- Shifts:
        for I in 1 to PE_CYCLES-1 loop
            initial_sr(I) <= initial_sr(I-1);
            mids_sr(I)    <= mids_sr(I-1);
            tmis_sr(I)    <= tmis_sr(I-1);
            emis_sr(I)    <= emis_sr(I-1);
            valid_sr(I)   <= valid_sr(I-1);
            cell_sr(I)    <= cell_sr(I-1);
            x_sr(I)       <= x_sr(I-1);
            y_sr(I)       <= y_sr(I-1);
        end loop;
      end if;
    end if;
  end process;

---------------------------------------------------------------------------------------------------
--     _____ _                   _
--    / ____(_)                 | |
--   | (___  _  __ _ _ __   __ _| |___
--    \___ \| |/ _` | '_ \ / _` | / __|
--    ____) | | (_| | | | | (_| | \__ \
--   |_____/|_|\__, |_| |_|\__,_|_|___/
--              __/ |
--             |___/
---------------------------------------------------------------------------------------------------

  step.add.tmis           <= tmis_sr(PE_MUL_CYCLES + 2 * PE_ADD_CYCLES - 1);
  step.add.emis           <= emis_sr(PE_MUL_CYCLES + 2 * PE_ADD_CYCLES - 1);

  step.emult.tmis         <= tmis_sr(PE_CYCLES-1);
  step.emult.emis         <= emis_sr(PE_CYCLES-1);

---------------------------------------------------------------------------------------------------
--    _   _                            _    ____        _               _
--   | \ | |                          | |  / __ \      | |             | |
--   |  \| | ___  _ __ _ __ ___   __ _| | | |  | |_   _| |_ _ __  _   _| |_ ___
--   | . ` |/ _ \| '__| '_ ` _ \ / _` | | | |  | | | | | __| '_ \| | | | __/ __|
--   | |\  | (_) | |  | | | | | | (_| | | | |__| | |_| | |_| |_) | |_| | |_\__ \
--   |_| \_|\___/|_|  |_| |_| |_|\__,_|_|  \____/ \__,_|\__| .__/ \__,_|\__|___/
--                                                         | |
--                                                         |_|
---------------------------------------------------------------------------------------------------
-- Outputs when this PE is not in bypass mode
---------------------------------------------------------------------------------------------------

  o_normal.valid          <= valid_sr(PE_CYCLES-1);
  o_normal.cell           <= cell_sr(PE_CYCLES-1);

  -- Probabilities
  o_normal.emis           <= step.emult.emis;
  o_normal.tmis          <= step.emult.tmis;

  -- Output M
  o_normal.mids.ml        <= step.emult.m;
  o_normal.mids.mtl       <= (others => '0');
  o_normal.mids.mt        <= step.emult.m;

  -- Output I depending on if Theta mult is Disabled is True
  TDT: if DISABLE_THETA = '1' generate
    o_normal.mids.il      <= mul_theta_sr(PE_MUL_CYCLES-1);
  end generate;
  TDF: if DISABLE_THETA /= '1' generate -- or False
    o_normal.mids.il      <= step.emult.i;
  end generate;

  o_normal.mids.itl       <= (others => '0');
  o_normal.mids.it        <= (others => '0');

  -- Output D depending on if Upsilon mult is Disabled is True
  UDT: if DISABLE_UPSILON = '1' generate
    o_normal.mids.dl      <= mul_upsilon_sr(PE_MUL_CYCLES-1);
  end generate;
  UDF: if DISABLE_UPSILON /= '1' generate -- or False
    o_normal.mids.dl      <= step.emult.i;
  end generate;

  o_normal.mids.dtl       <= (others => '0');
  o_normal.mids.dt        <= (others => '0');

  -- Output X & Y
  o_normal.x              <= x_sr(PE_CYCLES-1);
  o_normal.y              <= y_sr(PE_CYCLES-1);

  o_normal.initial        <= initial_sr(PE_CYCLES-1);

  -- Check if all the floating point units are ready
  --check_ready : process(all)
  --  variable rdy : std_logic := '1';
  --begin
  --  rdy := '1';
  --  for I in 0 to 13 loop
  --    rdy := rdy AND fp_areadys(I);
  --    rdy := rdy AND fp_breadys(I);
  --  end loop;
  --  o.ready <= rdy;
  --end process;

  o_normal.ready <= '1';

---------------------------------------------------------------------------------------------------
--    ____                               ____        _               _
--   |  _ \                             / __ \      | |             | |
--   | |_) |_   _ _ __   __ _ ___ ___  | |  | |_   _| |_ _ __  _   _| |_ ___
--   |  _ <| | | | '_ \ / _` / __/ __| | |  | | | | | __| '_ \| | | | __/ __|
--   | |_) | |_| | |_) | (_| \__ \__ \ | |__| | |_| | |_| |_) | |_| | |_\__ \
--   |____/ \__, | .__/ \__,_|___/___/  \____/ \__,_|\__| .__/ \__,_|\__|___/
--           __/ | |                                    | |
--          |___/|_|                                    |_|
---------------------------------------------------------------------------------------------------

  o_bypass.valid          <= valid_sr(PE_CYCLES-1);
  o_bypass.cell           <= cell_sr(PE_CYCLES-1);

  -- Probabilities
  -- TODO: We actually don't have to bypass these.
  -- But they probably get optimized away and dont incur extra muxing
  o_bypass.emis           <= emis_sr(PE_CYCLES-1);
  o_bypass.tmis           <= tmis_sr(PE_CYCLES-1);

  -- Output MIDs
  o_bypass.mids           <= mids_sr(PE_CYCLES-1);

  -- Output X & Y
  o_bypass.x              <= x_sr(PE_CYCLES-1);
  o_bypass.y              <= y_sr(PE_CYCLES-1);

  -- Initial D row value
  o_bypass.initial        <= initial_sr(PE_CYCLES-1);

  o_bypass.ready          <= '1';

--------------------------------------------------------------------------------------------------- Determine output:

  determine_out: process(all)
  begin
    if x_sr(PE_CYCLES-1) = BP_STOP
    or y_sr(PE_CYCLES-1) = BP_STOP
    then
      o_buf <= o_bypass;
    else
      o_buf <= o_normal;
    end if;
  end process;

  o <= o_buf;

---------------------------------------------------------------------------------------------------
end rtl;
