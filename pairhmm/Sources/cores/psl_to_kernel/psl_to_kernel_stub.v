// Copyright 1986-2017 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2017.4 (lin64) Build 2086221 Fri Dec 15 20:54:30 MST 2017
// Date        : Fri Apr 13 11:32:56 2018
// Host        : laurens-ubuntu running 64-bit Ubuntu 16.04.4 LTS
// Command     : write_verilog -force -mode synth_stub
//               /home/laurens/Desktop/project_1/project_1.srcs/sources_1/ip/psl_to_kernel/psl_to_kernel_stub.v
// Design      : psl_to_kernel
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7vx690tffg1157-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module psl_to_kernel(clk_kernel, clk_psl)
/* synthesis syn_black_box black_box_pad_pin="clk_kernel,clk_psl" */;
  output clk_kernel;
  input clk_psl;
endmodule
