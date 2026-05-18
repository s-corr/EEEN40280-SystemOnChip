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
ExecStep $xv_path/bin/xsim TB_AHBspi_behav -key {Behavioral:sim_spi:Functional:TB_AHBspi} -tclbatch TB_AHBspi.tcl -view /home/dGnome/Code/College/Year5/EmbbedDes/EEEN40280-SystemOnChip/Hardware/TB_AHBspi_behav.wcfg -log simulate.log
