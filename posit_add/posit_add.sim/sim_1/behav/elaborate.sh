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
ExecStep $xv_path/bin/xelab -wto 2570ef0e721043cdaae16d02868fc0c5 -m64 --debug typical --relax --mt 8 -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip --snapshot posit_adder_8bit_tb_v_behav xil_defaultlib.posit_adder_8bit_tb_v xil_defaultlib.glbl -log elaborate.log
