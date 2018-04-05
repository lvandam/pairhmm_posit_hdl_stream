// Copyright 1986-2017 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2017.4 (lin64) Build 2086221 Fri Dec 15 20:54:30 MST 2017
// Date        : Wed Apr  4 15:33:38 2018
// Host        : ce-hpc02.ewi.tudelft.nl running 64-bit unknown
// Command     : write_verilog -force -mode synth_stub
//               /home/laurensvandam/pairhmm/Sources/cores/feedback_fifo/feedback_fifo_stub.v
// Design      : feedback_fifo
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7vx690tffg1157-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "fifo_generator_v13_2_1,Vivado 2017.4" *)
module feedback_fifo(clk, srst, din, wr_en, rd_en, dout, full, wr_ack, 
  overflow, empty, valid, underflow)
/* synthesis syn_black_box black_box_pad_pin="clk,srst,din[386:0],wr_en,rd_en,dout[386:0],full,wr_ack,overflow,empty,valid,underflow" */;
  input clk;
  input srst;
  input [386:0]din;
  input wr_en;
  input rd_en;
  output [386:0]dout;
  output full;
  output wr_ack;
  output overflow;
  output empty;
  output valid;
  output underflow;
endmodule
