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
echo "xvlog -m64 --relax -prj posit_adder_8bit_tb_v_vlog.prj"
ExecStep $xv_path/bin/xvlog -m64 --relax -prj posit_adder_8bit_tb_v_vlog.prj 2>&1 | tee compile.log
