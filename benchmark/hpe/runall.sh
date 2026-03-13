#!/bin/bash

CC=${1:-icpx}
physics=${2:-mhd}
mbres=${3:-mb64}
for res in 1 2 4 8 16 32 64 96 128
do
  #for mbres in mb64
  #do
    echo "Running blast_hydro-scaling.sh with res=$res and mbres=$mbres"
    echo "NTASKS set to $NTASKS"
    qsub -v NTASKS=$res,CC=icpx,PHYSICS=mhd,MBRES=mb64 blast-scaling_pbs.sh
  #done
done
