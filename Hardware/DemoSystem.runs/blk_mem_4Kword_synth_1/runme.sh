#!/bin/sh

# 
# Vivado(TM)
# runme.sh: a Vivado-generated Runs Script for UNIX
# Copyright 1986-2015 Xilinx, Inc. All Rights Reserved.
# 

if [ -z "$PATH" ]; then
  PATH=/home/dGnome/Applications/Vivado_2015p2/Vivado/2015.2/ids_lite/ISE/bin/lin64:/home/dGnome/Applications/Vivado_2015p2/Vivado/2015.2/bin
else
  PATH=/home/dGnome/Applications/Vivado_2015p2/Vivado/2015.2/ids_lite/ISE/bin/lin64:/home/dGnome/Applications/Vivado_2015p2/Vivado/2015.2/bin:$PATH
fi
export PATH

if [ -z "$LD_LIBRARY_PATH" ]; then
  LD_LIBRARY_PATH=/home/dGnome/Applications/Vivado_2015p2/Vivado/2015.2/ids_lite/ISE/lib/lin64
else
  LD_LIBRARY_PATH=/home/dGnome/Applications/Vivado_2015p2/Vivado/2015.2/ids_lite/ISE/lib/lin64:$LD_LIBRARY_PATH
fi
export LD_LIBRARY_PATH

HD_PWD=`dirname "$0"`
cd "$HD_PWD"

HD_LOG=runme.log
/bin/touch $HD_LOG

ISEStep="./ISEWrap.sh"
EAStep()
{
     $ISEStep $HD_LOG "$@" >> $HD_LOG 2>&1
     if [ $? -ne 0 ]
     then
         exit
     fi
}

EAStep vivado -log blk_mem_4Kword.vds -m64 -mode batch -messageDb vivado.pb -notrace -source blk_mem_4Kword.tcl
