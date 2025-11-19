#!/bin/bash

for CC in aocc g++ g++-simd
do
    echo "Compiling with compiler: $CC"
    for physics in hydro mhd
    do
        echo "  Physics: $physics"
        ./compile.sh $CC $physics
    done
done
