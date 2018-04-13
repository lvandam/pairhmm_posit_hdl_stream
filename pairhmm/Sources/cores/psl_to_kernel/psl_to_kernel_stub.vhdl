-- Copyright 1986-2017 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2017.4 (lin64) Build 2086221 Fri Dec 15 20:54:30 MST 2017
-- Date        : Fri Apr 13 11:32:56 2018
-- Host        : laurens-ubuntu running 64-bit Ubuntu 16.04.4 LTS
-- Command     : write_vhdl -force -mode synth_stub
--               /home/laurens/Desktop/project_1/project_1.srcs/sources_1/ip/psl_to_kernel/psl_to_kernel_stub.vhdl
-- Design      : psl_to_kernel
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7vx690tffg1157-2
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity psl_to_kernel is
  Port ( 
    clk_kernel : out STD_LOGIC;
    clk_psl : in STD_LOGIC
  );

end psl_to_kernel;

architecture stub of psl_to_kernel is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "clk_kernel,clk_psl";
begin
end;
