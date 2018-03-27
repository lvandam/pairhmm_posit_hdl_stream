#!/bin/bash -f
xv_path="/opt/applics/xilinx-vivado-2017.1/Vivado/2017.1"
ExecStep()
{
"$@"
RETVAL=$?
if [ $RETVAL -ne 0 ]
then
exit $RETVAL
fi
}
ExecStep $xv_path/bin/xsim posit_adder_8bit_tb_v_behav -key {Behavioral:sim_1:Functional:posit_adder_8bit_tb_v} -tclbatch posit_adder_8bit_tb_v.tcl -log simulate.log
