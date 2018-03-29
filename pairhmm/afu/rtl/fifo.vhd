library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.functions.all;
  use work.psl.all;

entity fifo is
  generic (
    width               : integer   := 1;
    depth               : integer   := 1;
    wr                  : std_logic := '0';
    fd                  : natural   := 1;
    style               : string    := "block"
  );
  port (
    cr                  : in  cr_in;
    put                 : in  std_logic;
    data_in             : in  std_logic_vector(width - 1 downto 0);
    pull                : in  std_logic;
    data_out            : out std_logic_vector(width - 1 downto 0);
    empty               : out std_logic;
    full                : out std_logic
  );
end fifo;

architecture logic of fifo is

  type fifo_int is record
    put_address         : unsigned(depth downto 0);
    pull_address        : unsigned(depth downto 0);
    empty               : std_logic;
    full                : std_logic;
  end record;

  signal q,  r          : fifo_int;

begin

  comb : process(all)
    variable v          : fifo_int;
  begin

    v                   := r;

    v.put_address       := r.put_address + u(put);
    v.pull_address      := r.pull_address + u(pull);

    v.empty             := is_empty(v.put_address, v.pull_address);
    v.full              := is_full(v.put_address + fd, v.pull_address) or is_full(v.put_address + fd + 1, v.pull_address);

    empty               <= r.empty;
    full                <= r.full;

    q                   <= v;

  end process comb;

  ram : entity work.ram_dual generic map (width, depth, wr, style)
  port map (
    clk                 => cr.clk,
    put                 => put,
    write_address       => r.put_address(depth - 1 downto 0),
    data_in             => data_in,
    read_address        => q.pull_address(depth - 1 downto 0),
    data_out            => data_out
  );

  reg : process(cr)
  begin
    if rising_edge(cr.clk) then
      if cr.rst then
        r.put_address   <= (others => '0');
        r.pull_address  <= (others => '0');
        r.empty         <= '1';
        r.full          <= '0';
      else
        r               <= q;
      end if;
    end if;
  end process;

end architecture logic;

-----------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.functions.all;
  use work.psl.all;

entity fifo_unsigned is
  generic (
    width               : integer   := 1;
    depth               : integer   := 1;
    wr                  : std_logic := '0';
    fd                  : natural   := 1;
    style               : string    := "block"
  );
  port (
    cr                  : in  cr_in;
    put                 : in  std_logic;
    data_in             : in  unsigned(width - 1 downto 0);
    pull                : in  std_logic;
    data_out            : out unsigned(width - 1 downto 0);
    empty               : out std_logic;
    full                : out std_logic
  );
end fifo_unsigned;

architecture logic of fifo_unsigned is

  type fifo_int is record
    put_address         : unsigned(depth downto 0);
    pull_address        : unsigned(depth downto 0);
    empty               : std_logic;
    full                : std_logic;
  end record;

  signal q,  r          : fifo_int;

begin

  comb : process(all)
    variable v          : fifo_int;
  begin

    v                   := r;

    v.put_address       := r.put_address + u(put);
    v.pull_address      := r.pull_address + u(pull);

    v.empty             := is_empty(v.put_address, v.pull_address);
    v.full              := is_full(v.put_address + fd, v.pull_address) or is_full(v.put_address + fd + 1, v.pull_address);

    empty               <= r.empty;
    full                <= r.full;

    q                   <= v;

  end process comb;

  ram : entity work.ram_dual_unsigned generic map (width, depth, wr, style)
  port map (
    clk                 => cr.clk,
    put                 => put,
    write_address       => r.put_address(depth - 1 downto 0),
    data_in             => data_in,
    read_address        => q.pull_address(depth - 1 downto 0),
    data_out            => data_out
  );

  reg : process(cr)
  begin
    if rising_edge(cr.clk) then
      if cr.rst then
        r.put_address   <= (others => '0');
        r.pull_address  <= (others => '0');
        r.empty         <= '1';
        r.full          <= '0';
      else
        r               <= q;
      end if;
    end if;
  end process;

end architecture logic;

-----------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.functions.all;
  use work.psl.all;

entity fifo_synchr is
  generic (
    width               : integer   := 1;
    depth               : integer   := 1;
    wr                  : std_logic := '0';
    fd                  : natural   := 1;
    style               : string    := "block"
  );
  port (
    cr                  : in  cr_in;
    put                 : in  std_logic;
    data_in             : in  std_logic_vector(width - 1 downto 0);
    pull                : in  std_logic;
    data_out            : out std_logic_vector(width - 1 downto 0);
    empty               : out std_logic;
    full                : out std_logic
  );
end fifo_synchr;

architecture logic of fifo_synchr is
  type      mem_type is array (2**depth-1 downto 0) of std_logic_vector(width - 1 downto 0);
begin
  fifo_proc: process(cr.clk)
    variable aput         : unsigned(depth downto 0) := (others => '0');
    variable apull        : unsigned(depth downto 0) := (others => '0');
    variable mem          : mem_type;
    --attribute ram_style : string;
    --attribute ram_style of mem : variable is style;
  begin
    if rising_edge(cr.clk) then
      if cr.rst = '1' then
        aput      := (others => '0');
        apull     := (others => '0');
        data_out  <= (others => '0');
        empty     <= '1';
        full      <= '0';
      else


        -- Writing into fifo
        if put then
          --if      aput'high = apull'high
          --    or  aput(aput'high - 1 downto 0) /= apull(apull'high - 1 downto 0)
          --then
          if not full then

            mem(to_integer(aput(depth-1 downto 0))) := data_in;

            aput := aput + 1;
          end if;
        end if;

        -- Reading from fifo
        if pull then
          --if      aput'high /= apull'high
          --    or  aput(aput'high - 1 downto 0) /= apull(apull'high - 1 downto 0)
          --then
          if not empty then
            apull := apull + 1;
          end if;
        end if;

        data_out <= mem(to_integer(apull(depth-1 downto 0)));

        -- Check if empty, full
				if aput(aput'high - 1 downto 0) = apull(apull'high - 1 downto 0) then
					if aput'high /= apull'high then
						full <= '1';
					else
						empty <= '1';
					end if;
				else
					empty	<= '0';
					full	<= '0';
				end if;

      end if;
    end if;
  end process;

end architecture logic;

-----------------------------------------------------------------------------------------------------------------------
