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
ExecStep $xv_path/bin/xelab -wto 0cf0669fc6af4ee9943ea9c429f4cd74 -m64 --debug typical --relax --mt 8 -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip --snapshot TB_AHBspi_behav xil_defaultlib.TB_AHBspi xil_defaultlib.glbl -log elaborate.log
