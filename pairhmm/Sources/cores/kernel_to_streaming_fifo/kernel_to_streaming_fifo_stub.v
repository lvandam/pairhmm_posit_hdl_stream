// Copyright 1986-2017 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2017.4 (lin64) Build 2086221 Fri Dec 15 20:54:30 MST 2017
// Date        : Mon Apr  9 18:38:09 2018
// Host        : laurens-ubuntu running 64-bit Ubuntu 16.04.4 LTS
// Command     : write_verilog -force -mode synth_stub
//               /home/laurens/Desktop/project_1/project_1.srcs/sources_1/ip/kernel_to_streaming_fifo/kernel_to_streaming_fifo_stub.v
// Design      : kernel_to_streaming_fifo
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7vx690tffg1157-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "fifo_generator_v13_2_1,Vivado 2017.4" *)
module kernel_to_streaming_fifo(wr_clk, rd_clk, din, wr_en, rd_en, dout, full, wr_ack, 
  overflow, empty, valid, underflow)
/* synthesis syn_black_box black_box_pad_pin="wr_clk,rd_clk,din[127:0],wr_en,rd_en,dout[1023:0],full,wr_ack,overflow,empty,valid,underflow" */;
  input wr_clk;
  input rd_clk;
  input [127:0]din;
  input wr_en;
  input rd_en;
  output [1023:0]dout;
  output full;
  output wr_ack;
  output overflow;
  output empty;
  output valid;
  output underflow;
endmodule
