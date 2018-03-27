#!/bin/bash

set -x

VERILOG_PATH=${PWD}/../src

iverilog -o posit_add -I${VERILOG_PATH} ${VERILOG_PATH}/posit_adder_8bit_tb.v ${VERILOG_PATH}/posit_adder.v

vvp posit_add
