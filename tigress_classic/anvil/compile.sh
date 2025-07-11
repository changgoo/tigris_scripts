#!/bin/sh
source ~/.bashrc
set -e

debug_option=""
# debug_option="-debug"
module purge; module load anaconda; module load gcc; module load openmpi; module load fftw hdf5
HDF5DIR=$RCAC_HDF5_ROOT

# CC=g++
mpi_hdf5_include_path="$HDF5DIR/include"
cflag="-fopenmp-simd -fwhole-program -flto=auto -ffast-math -march=znver3 -fprefetch-loop-arrays"
options="${debug_option} -mpi -hdf5 --include=${mpi_hdf5_include_path}"

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
./configure.py --prob=$prob --nghost=4 -fft -fb --grav=blockfft --cflag="${cflag}" $options $phy_options

make clean
make all -j

cp bin/athena $current/${prob}_${physics}.exe

cd $current
set +e
