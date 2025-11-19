#!/bin/bash

for CC in icpx g++ g++-simd
do
    echo "Compiling with compiler: $CC"
    for physics in hydro mhd
    do
        echo "  Physics: $physics"
        ./compile.sh $CC $physics
    done
done
