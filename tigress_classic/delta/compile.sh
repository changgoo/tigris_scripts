#!/bin/sh
# tigress-classic compilation script works for stellar and tiger3
#   alias for module_icpx an module_gcc should be in .bashrc,
#   otherwise uncomment the following
# source ~/.bashrc
set -e

module purge
module load gcc openmpi
module load fftw hdf5
cflag="-fopenmp-simd -fwhole-program -flto=auto -ffast-math -march=native -fprefetch-loop-arrays"
cflag=""

# CC=g++
echo $HDF5_HOME
mpi_hdf5_library_path="$HDF5_HOME/lib"
mpi_hdf5_include_path="$HDF5_HOME/include"

# disable cxi
unset OMPI_MCA_mtl_ofi_provider_include
export OMPI_MCA_mtl_ofi_provider_exclude=cxi

options="${debug_option} -mpi -hdf5 --lib_path=${mpi_hdf5_library_path} --include=${mpi_hdf5_include_path}"

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

