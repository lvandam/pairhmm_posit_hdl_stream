library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.functions.all;
  use work.psl.all;
  use work.cu_package.all;
  use work.dma_package.all;
  use work.pairhmm_package.all;
  use work.pe_package.all;
  
library xil_defaultlib;
  
entity cu is
  port (
    i                       : in  cu_in;
    o                       : out cu_out
  );
end entity cu;

architecture logic of cu is

  signal q, r               : cu_int;
  signal re                 : cu_ext;
  
  signal if_rv              : unsigned(31 downto 0) := (others => '0');
  signal of_wa              : unsigned(31 downto 0) := (others => '0');

begin

  comb : process(all)
    variable v              : cu_int;
  begin

----------------------------------------------------------------------------------------------------------------------- default assignments

    v                                 := r;
    v.o.read.valid                    := '0';
    v.o.read.pause                    := '0';
    v.o.write.request.valid           := '0';
    v.o.write.data.valid              := '0';
    v.next_batch                      := '0';
    
    -- Set status registers and counters:
    v.o.pairhmm.status                  := re.pairhmm.regs.o.status;
    v.o.pairhmm.reqs(63 downto 32)      := slv(v.wreqs);
    v.o.pairhmm.reqs(31 downto  0)      := slv(v.rreqs);
    v.o.pairhmm.reps(63 downto 32)      := slv(v.wreps);
    v.o.pairhmm.reps(31 downto  0)      := slv(v.rreps);
    v.o.pairhmm.fifo_rvs(63 downto 32)  := slv(v.of_rv);
    v.o.pairhmm.fifo_rvs(31 downto  0)  := slv(v.if_rv);
    v.o.pairhmm.fifo_was(63 downto 32)  := slv(v.of_wa);
    v.o.pairhmm.fifo_was(31 downto  0)  := slv(v.if_wa);
    
----------------------------------------------------------------------------------------------------------------------- state machine

    case r.state is
      when idle     =>
        if i.start then
          v.state           := loadxys;
          v.wed             := i.wed;
          v.o.done          := '0';
          
          -- Get all the reads. The number of cachelines to read is
          -- 2 * (for X and Y)
          -- the number of cachelines for a maximum size string
          -- the depth of the PE pipeline (number of pairs in parallel)
          read_cachelines   (v.o.read, v.wed.source, 2 * PAIRHMM_STRING_CACHELINES * PE_DEPTH);
        end if;
        
        v.xy_reads          := (others => '0');
        
      when loadxys   =>
        v.xy_reads          := r.xy_reads + u(i.read.valid);
        
        if i.read.valid = '1' then
          --v.x_all(I + PAIRHMM_BASEPAIRS_PER_CACHELINE * to_integer((r.xy_reads(r.xy_reads'HIGH downto log2(PE_DEPTH))))(to_integer(log2(r.xy_reads(PE_DEPTH - 1 downto 0)))) := (others => '0');
        end if;
        
        if v.xy_reads = PAIRHMM_STRING_CACHELINES * PE_DEPTH then
          v.state           := streamps;
        end if;
                        
      when streamps =>
        
        
      when done     =>
        
        
      when others => null;
    end case;
    
----------------------------------------------------------------------------------------------------------------------- Outputs

    -- drive input registers
    q                       <= v;

    -- outputs
    o                       <= r.o;

  end process;
      
----------------------------------------------------------------------------------------------------------------------- PLL

  kernel_pll : entity xil_defaultlib.psl_to_kernel_pll port map ( 
    clk_psl            => i.cr.clk,
    clk_kernel         => re.clk_kernel
);
 
----------------------------------------------------------------------------------------------------------------------- FIFOs

  input_fifo : entity xil_defaultlib.streaming_to_kernel_fifo port map (
    -- Higher frequency domain
    wr_clk    => i.cr.clk,
    rst       => q.in_fifo.rst,
    wr_en     => q.in_fifo.wr_en,
    wr_ack    => re.in_fifo.wr_ack,
    din       => re.in_fifo.din,
    full      => re.in_fifo.full,
    overflow  => re.in_fifo.overflow,
    
    -- Lower frequency domain:
    rd_clk    => re.clk_kernel,
    rd_en     => re.in_fifo.rd_en,
    valid     => re.in_fifo.valid,
    dout      => re.in_fifo.dout,
    empty     => re.in_fifo.empty,
    underflow => re.in_fifo.underflow
  );
  
  -- Connect input fifo signals:
  re.in_fifo.din              <= i.read.data;
  
  re.pairhmm.block_in         <= re.in_fifo.dout;
  re.pairhmm.block_in_valid   <= re.in_fifo.valid;

  output_fifo : entity xil_defaultlib.kernel_to_streaming_fifo port map (    
    -- Lower frequency domain
    wr_clk    => re.clk_kernel,
    wr_en     => re.out_fifo.wr_en,
    wr_ack    => re.out_fifo.wr_ack,
    din       => re.out_fifo.din,
    full      => re.out_fifo.full,
    overflow  => re.out_fifo.overflow,
    
    -- Higher frequency domain
    rd_clk    => i.cr.clk,    
    rst       => q.out_fifo.rst,
    rd_en     => q.out_fifo.rd_en,
    valid     => re.out_fifo.valid,
    dout      => re.out_fifo.dout,    
    empty     => re.out_fifo.empty,
    underflow => re.out_fifo.underflow
  );
  
  -- Connect output fifo signals:
  re.out_fifo.din           <= re.pairhmm.block_out;
  re.out_fifo.wr_en         <= re.pairhmm.block_out_valid;

----------------------------------------------------------------------------------------------------------------------- Lower clock domain
  lcd_combinatorial : process(all)
  begin
    if re.in_fifo.empty = '0' then
      re.in_fifo.rd_en  <= '1';
    else
      re.in_fifo.rd_en  <= '0';
    end if;
  end process;
  
  lcd_sequential    : process(re.clk_kernel)
  begin
    if rising_edge(re.clk_kernel) then
      if q.lcd_rst = '1' then
        if_rv <= (others => '0');
        of_wa <= (others => '0');
      else
        if re.in_fifo.valid = '1' then
          if_rv <= if_rv + 1;
        end if;
        if re.out_fifo.wr_ack = '1' then
          of_wa <= of_wa + 1;
        end if;
      end if;
    end if;
  end process;
  
  -- Connect input registers to pairhmm
  re.pairhmm.regs.i           <= i.pairhmm;
  
  pairhmm_core : entity work.pairhmm port map (
    i => re.pairhmm.i,
    o => re.pairhmm.o
  );
  
  -- Aggregate conversion (TODO: write a procedure)
  re.pairhmm.i <= (
    cr => (
      clk       => re.clk_kernel,
      rst       => q.lcd_rst
    ),      
    first => (
      cr => (
        clk     => re.clk_kernel,
        rst     => q.lcd_rst
      ),
      start     => '1',
      valid     => re.pairhmm.block_in_valid,
      tmis => (
        alpha   => re.pairhmm.block_in( 31 downto   0),
        beta    => re.pairhmm.block_in( 63 downto  32),
        gamma   => re.pairhmm.block_in( 95 downto  64),
        delta   => re.pairhmm.block_in(127 downto  96),
        epsilon => re.pairhmm.block_in(159 downto 128),
        zeta    => re.pairhmm.block_in(191 downto 160),
        eta     => re.pairhmm.block_in(223 downto 192)
      ),                                          
      emis => (                                   
        lambda  => re.pairhmm.block_in(255 downto 224),
        theta   => re.pairhmm.block_in(287 downto 256),
        upsilon => re.pairhmm.block_in(319 downto 288)
      ),                                          
      mids => (                                   
        mtl     => re.pairhmm.block_in(351 downto 320),
        itl     => re.pairhmm.block_in(383 downto 352),
        dtl     => re.pairhmm.block_in(415 downto 384),
        mt      => re.pairhmm.block_in(447 downto 416),
        it      => re.pairhmm.block_in(479 downto 448),
        dt      => re.pairhmm.block_in(511 downto 480),
        ml      => re.pairhmm.block_in(543 downto 512),
        il      => re.pairhmm.block_in(575 downto 544),
        dl      => re.pairhmm.block_in(607 downto 576)
      )                                           
    )
  );
  
  re.pairhmm.block_out_valid           <= re.pairhmm.o.last.valid;
  re.pairhmm.block_out( 31 downto   0) <= re.pairhmm.o.last.tmis.alpha;
  re.pairhmm.block_out( 63 downto  32) <= re.pairhmm.o.last.tmis.beta;   
  re.pairhmm.block_out( 95 downto  64) <= re.pairhmm.o.last.tmis.gamma;
  re.pairhmm.block_out(127 downto  96) <= re.pairhmm.o.last.tmis.delta;  
  re.pairhmm.block_out(159 downto 128) <= re.pairhmm.o.last.tmis.epsilon;
  re.pairhmm.block_out(191 downto 160) <= re.pairhmm.o.last.tmis.zeta;   
  re.pairhmm.block_out(223 downto 192) <= re.pairhmm.o.last.tmis.eta;    
  re.pairhmm.block_out(255 downto 224) <= re.pairhmm.o.last.emis.lambda; 
  re.pairhmm.block_out(287 downto 256) <= re.pairhmm.o.last.emis.theta;  
  re.pairhmm.block_out(319 downto 288) <= re.pairhmm.o.last.emis.upsilon;
  re.pairhmm.block_out(351 downto 320) <= re.pairhmm.o.last.mids.mtl;
  re.pairhmm.block_out(383 downto 352) <= re.pairhmm.o.last.mids.itl;
  re.pairhmm.block_out(415 downto 384) <= re.pairhmm.o.last.mids.dtl;
  re.pairhmm.block_out(447 downto 416) <= re.pairhmm.o.last.mids.mt; 
  re.pairhmm.block_out(479 downto 448) <= re.pairhmm.o.last.mids.it; 
  re.pairhmm.block_out(511 downto 480) <= re.pairhmm.o.last.mids.dt; 
  re.pairhmm.block_out(543 downto 512) <= re.pairhmm.o.last.mids.ml; 
  re.pairhmm.block_out(575 downto 544) <= re.pairhmm.o.last.mids.il; 
  re.pairhmm.block_out(607 downto 576) <= re.pairhmm.o.last.mids.dl;
  re.pairhmm.block_out(639 downto 608) <= re.pairhmm.o.score;
      
----------------------------------------------------------------------------------------------------------------------- reset & registers

  reg : process(i.cr)
  begin
    if rising_edge(i.cr.clk) then
      if i.cr.rst then
        cu_reset(r);
      else
        r                   <= q;
      end if;
    end if;
  end process;

end architecture logic;
