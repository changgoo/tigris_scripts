#!/bin/sh
# tigress-classic compilation script works for stellar and tiger3
#   alias for module_icpx an module_gcc should be in .bashrc,
#   otherwise uncomment the following
# example alias .bashrc:
# alias module_icpx='module purge; module load anaconda3/2023.3 intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10'
# alias module_gcc='module purge; module load anaconda3/2023.3 fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4'
source ~/.bashrc
set -e

CC=$1
if [ "$CC" == "icpx" ] ; then
    module_icpx
    debug_option=""
elif [ "$CC" == "g++" ] ; then
    module_gcc
    debug_option=""
else
    module_gcc
    CC=g++
    debug_option="-debug"
fi
echo "CC is set to $CC"

# CC=g++
echo $HDF5DIR
mpi_hdf5_library_path="$HDF5DIR/lib64"
mpi_hdf5_include_path="$HDF5DIR/include"

options="${debug_option} -mpi -hdf5 --cxx=$CC --lib_path=${mpi_hdf5_library_path} --include=${mpi_hdf5_include_path}"

physics=$2
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

cp bin/athena $current/${prob}_${physics}_$CC$debug_option.exe

cd $current
set +e
