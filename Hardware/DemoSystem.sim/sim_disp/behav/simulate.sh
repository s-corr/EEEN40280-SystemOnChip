#!/bin/sh -f
xv_path="/home/dGnome/Applications/Vivado_2015p2/Vivado/2015.2"
ExecStep()
{
"$@"
RETVAL=$?
if [ $RETVAL -ne 0 ]
then
exit $RETVAL
fi
}
ExecStep $xv_path/bin/xsim TB_AHBdisp_behav -key {Behavioral:sim_disp:Functional:TB_AHBdisp} -tclbatch TB_AHBdisp.tcl -view /home/dGnome/Code/College/EmbbedDes/EEEN40280-SystemOnChip/Hardware/TB_AHBdisp_behav.wcfg -log simulate.log
