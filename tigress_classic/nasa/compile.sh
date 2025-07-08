#!/bin/sh
set -e
module load mpi-hpe/mpt comp-intel hdf5/1.8.18_mpt

options="-mpi -hdf5 --fftw_path=$HOME/fftw"

physics=$1
if [ "$physics" == "hydro" ] ; then
    phy_options=""
elif [ "$physics" == "mhd" ] ; then
    phy_options="-b"
elif [ "$physics" == "crmhd" ] ; then
    phy_options="-b --cr=mg"
else
    echo "physics is set to hydro"
    physics=hydro
fi

current=`pwd`
SRCDIR=$HOME/tigris/
cd $SRCDIR

prob=tigress_classic
./configure.py --prob=$prob --nghost=4 -fft -fb --grav=blockfft $options $phy_options

make clean
make all -j4

cp bin/athena $current/${prob}_${physics}.exe

cd $currnet
set +e
