#!/bin/bash

CC=${1:-aocc}
physics=${2:-hydro}
for res in 1 2 4 8 16 32 64
do
  for mbres in mb16 mb32 mb64 mb128
  do
    echo "Running blast_hydro-scaling.sh with res=$res and mbres=$mbres"
    NTASKS=$res
    echo "NTASKS set to $NTASKS"
    NTASKS=$res ./blast-scaling.sh $mbres $CC $physics
  done
done