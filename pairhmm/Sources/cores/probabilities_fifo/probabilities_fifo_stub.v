// Copyright 1986-2017 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2017.4 (win64) Build 2086221 Fri Dec 15 20:55:39 MST 2017
// Date        : Tue Apr  3 18:09:05 2018
// Host        : DESKTOP-63O3FVS running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               c:/Users/laure/project_1/project_1.srcs/sources_1/ip/probabilities_fifo_1/probabilities_fifo_stub.v
// Design      : probabilities_fifo
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7vx690tffg1157-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "fifo_generator_v13_2_1,Vivado 2017.4" *)
module probabilities_fifo(rst, wr_clk, rd_clk, din, wr_en, rd_en, dout, full, 
  wr_ack, overflow, empty, valid, underflow)
/* synthesis syn_black_box black_box_pad_pin="rst,wr_clk,rd_clk,din[1023:0],wr_en,rd_en,dout[255:0],full,wr_ack,overflow,empty,valid,underflow" */;
  input rst;
  input wr_clk;
  input rd_clk;
  input [1023:0]din;
  input wr_en;
  input rd_en;
  output [255:0]dout;
  output full;
  output wr_ack;
  output overflow;
  output empty;
  output valid;
  output underflow;
endmodule
