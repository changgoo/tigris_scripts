#!/bin/sh
set -e
module load mpi-hpe/mpt comp-intel hdf5/1.8.18_mpt
#debug_option="-debug"
debug_option=""

options="${debug_option} -mpi -hdf5 --fftw_path=$HOME/fftw"

myoptions=$2

current=`pwd`
cd $HOME/tigris/

prob=tigress_classic
./configure.py --prob=$prob --nghost=4 -fft -fb --grav=blockfft $options $2

make clean
make all -j

cp bin/athena $current/${prob}.exe

cd $currnet
set +e
