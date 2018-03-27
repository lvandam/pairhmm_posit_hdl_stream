# recompile
proc r  {} {

  # compile libs
  echo "Compiling libs"
  vcom -2008 -quiet ../pairhmm_sa/lib/functions.vhd
  vcom -2008 -quiet ../afu/lib/psl.vhd
  vcom -2008 -quiet ../pairhmm_sa/lib/wed.vhd

  # compile packages
  echo "Compiling packages"
  vcom -2008 -quiet ../pairhmm_sa/pkg/pe_package.vhd
  vcom -2008 -quiet ../afu/pkg/frame_package.vhd
  vcom -2008 -quiet ../pairhmm_sa/pkg/pairhmm_package.vhd
  vcom -2008 -quiet ../afu/pkg/dma_package.vhd
  vcom -2008 -quiet ../afu/pkg/cu_package.vhd
  vcom -2008 -quiet ../afu/pkg/mmio_package.vhd
  vcom -2008 -quiet ../afu/pkg/control_package.vhd


  # compile ip
  # clk
  vcom -2008 -quiet ../pairhmm_sa/rtl/psl_to_kernel_pll.vhd
  # fifo
  vlog -quiet ../cores/feedback_fifo/sim/feedback_fifo.v
  vlog -quiet ../cores/kernel_to_streaming_fifo/sim/kernel_to_streaming_fifo.v
  vlog -quiet ../cores/probabilities_fifo/sim/probabilities_fifo.v
  # pipelined unsigned add/subtract
  vcom -2008 ../cores/ADDSUB151_8/sim/ADDSUB151_8.vhd
  vcom -2008 ../cores/ADDSUB256_8/sim/ADDSUB256_8.vhd

  # compile posit units
  vlog -quiet ../posit/lib/shift_left.v
  vlog -quiet ../posit/lib/shift_right.v
  vlog -quiet ../posit/lib/LOD_N.sv
  vlog -quiet ../posit/lib/LZD_N.sv

  #vlog -sv -quiet ../posit/es2/posit_defines.sv
  #vlog -sv -quiet ../posit/es2/posit_extract.sv
  #vlog -sv -quiet ../posit/es2/positmult_4.sv
  #vlog -sv -quiet ../posit/es2/positadd_4.sv
  #vlog -sv -quiet ../posit/es2/positadd_8.sv
  #vlog -sv -quiet ../posit/es2/posit_extract_accum.sv
  #vlog -sv -quiet ../posit/es2/positaccum_16.sv

 vlog -sv -quiet ../posit/es3/posit_defines_es3.sv
 vlog -sv -quiet ../posit/es3/posit_extract_es3.sv
 vlog -sv -quiet ../posit/es3/positmult_4_es3.sv
 vlog -sv -quiet ../posit/es3/positadd_4_es3.sv
 vlog -sv -quiet ../posit/es3/positadd_8_es3.sv
 vlog -sv -quiet ../posit/es3/posit_extract_accum_es3.sv
 vlog -sv -quiet ../posit/es3/positaccum_16_es3.sv

  # compile rtl
  echo "Compiling rtl"
  vlog -quiet ../pairhmm_sa/rtl/asym_ram.v
  vcom -2008 -quiet ../afu/rtl/buffers.vhd
  vcom -2008 -quiet ../pairhmm_sa/rtl/pe.vhd
  vcom -2008 -quiet ../afu/rtl/ram.vhd
  vcom -2008 -quiet ../afu/rtl/fifo.vhd
  vcom -2008 -quiet ../afu/rtl/dma.vhd
  vcom -2008 -quiet ../pairhmm_sa/rtl/pairhmm.vhd
  vcom -2008 -quiet ../afu/rtl/cu.vhd
  vcom -2008 -quiet ../afu/rtl/control.vhd
  vcom -2008 -quiet ../afu/rtl/mmio.vhd
  vcom -2008 -quiet ../afu/rtl/frame.vhd
  vcom -2008 -quiet ../afu/rtl/afu.vhd

  # compile top level
  echo "Compiling top level"
  vlog -quiet       pslse/afu_driver/verilog/top.v

}

# simulate
proc s  {} {
  vsim -L fifo_generator_v13_2_1 -L unisim -t ns -novopt -c -pli pslse/afu_driver/src/veriuser.sl +nowarnTSCALE work.top
  view wave
  radix h
  log * -r
  do wave.do
  view structure
  view signals
  view wave
  run -all
}

# shortcut for recompilation + simulation
proc rs {} {
  r
  s
}

# init libs
vlib work
vmap work work

# automatically recompile on first call
r
