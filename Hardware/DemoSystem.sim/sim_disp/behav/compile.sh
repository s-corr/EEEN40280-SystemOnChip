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
echo "xvlog -m64 --relax -prj TB_AHBdisp_vlog.prj"
ExecStep $xv_path/bin/xvlog -m64 --relax -prj TB_AHBdisp_vlog.prj 2>&1 | tee compile.log
