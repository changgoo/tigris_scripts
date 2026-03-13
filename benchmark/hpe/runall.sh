#!/bin/bash

CC=${1:-icpx}
physics=${2:-mhd}
mbres=${3:-mb64}
for res in 64 96 
#for res in 1 2 4 8 16 32 64 96 128
do
  for machine in 6960P_32GB
  #for mbres in mb64
  do
    echo "Running blast-scaling.sh with res=$res and mbres=$mbres"
    echo "NTASKS set to $res"
    qsub -v MACHINE=$machine,NTASKS=$res,CC=$CC,PHYSICS=$physics,MBRES=$mbres -l select=1:ncpus=144:sales_op=$machine blast-scaling.sh
  done
done
