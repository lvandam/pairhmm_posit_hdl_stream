# recompile
proc r  {} {

  # compile libs
  echo "Compiling libs"
  vcom -2008 -quiet ../afu/lib/functions.vhd
  vcom -2008 -quiet ../afu/lib/psl.vhd
  vcom -2008 -quiet ../afu/lib/wed.vhd

  # compile packages
  echo "Compiling packages"
  vcom -2008 -quiet ../afu/pkg/pe_package.vhd
  vcom -2008 -quiet ../afu/pkg/frame_package.vhd
  vcom -2008 -quiet ../afu/pkg/dma_package.vhd
  vcom -2008 -quiet ../afu/pkg/pairhmm_package.vhd
  vcom -2008 -quiet ../afu/pkg/cu_package.vhd
  vcom -2008 -quiet ../afu/pkg/mmio_package.vhd
  vcom -2008 -quiet ../afu/pkg/control_package.vhd

  # compile ip
  # clk
  vcom -2008 -quiet ../afu/rtl/psl_to_kernel_pll.vhd
  # fifo
  vlog -quiet ../cores/feedback_fifo/sim/feedback_fifo.v
  vlog -quiet ../cores/kernel_to_streaming_fifo/sim/kernel_to_streaming_fifo.v
  vlog -quiet ../cores/probabilities_fifo/sim/probabilities_fifo.v

  # compile posit units
  vlog -sv -quiet ../afu/rtl/posit/posit_pkg.sv
  vlog -quiet ../afu/rtl/posit/DSR_left_N_S.v
  vlog -quiet ../afu/rtl/posit/DSR_right_N_S.v
  vlog -quiet ../afu/rtl/posit/LOD_N.v
  vlog -quiet ../afu/rtl/posit/LZD_N.v
  vlog -quiet ../afu/rtl/posit/data_extract.v
  vlog -sv -quiet ../afu/rtl/posit/posit_adder_4.sv
  vlog -sv -quiet ../afu/rtl/posit/posit_adder_8.sv
  vlog -sv -quiet ../afu/rtl/posit/posit_mult_4.sv

  # compile rtl
  echo "Compiling rtl"
  vlog -quiet ../afu/rtl/asym_ram.v
  vcom -2008 -quiet ../afu/rtl/buffers.vhd
  vcom -2008 -quiet ../afu/rtl/pe.vhd
  vcom -2008 -quiet ../afu/rtl/ram.vhd
  vcom -2008 -quiet ../afu/rtl/fifo.vhd
  vcom -2008 -quiet ../afu/rtl/dma.vhd
  vcom -2008 -quiet ../afu/rtl/pairhmm.vhd
  vcom -2008 -quiet ../afu/rtl/cu.vhd
  vcom -2008 -quiet ../afu/rtl/control.vhd
  vcom -2008 -quiet ../afu/rtl/mmio.vhd
  vcom -2008 -quiet ../afu/rtl/frame.vhd
  vcom -2008 -quiet ../afu/rtl/afu.vhd

  # compile verilog files

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
