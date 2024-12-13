#!/bin/sh
# tigress-classic compilation script works for stellar and tiger3
#   alias for module_icpx an module_gcc should be in .bashrc,
#   otherwise uncomment the following
# alias module_icpx='module purge; module load anaconda3/2023.3 intel-oneapi/2024.2 intel-mpi/oneapi/2021.13 hdf5/oneapi-2024.2/intel-mpi/1.14.4 fftw/oneapi-2024.2/3.3.10'
# alias module_gcc='module purge; module load anaconda3/2023.3 fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/openmpi-4.1.6/1.14.4'
source ~/.bashrc
set -e

CC=$1
if [ "$CC" == "icpx" ] ; then
    module_icpx
    mpi_hdf5='hdf5/oneapi-2024.2/intel-mpi/1.14.4'
    debug_option=""
elif [ "$CC" == "g++" ] ; then
    module_gcc
    mpi_hdf5='hdf5/gcc/intel-mpi/1.14.4'
    debug_option=""
else
    module_gcc
    mpi_hdf5='hdf5/gcc/intel-mpi/1.14.4'
    # mpi_hdf5='hdf5/gcc/intel-mpi/1.10.6'
    CC=g++
    debug_option="-debug"
fi
echo "CC is set to $CC"

# CC=g++

mpi_hdf5_library_path="/usr/local/$mpi_hdf5/lib64"
mpi_hdf5_include_path="/usr/local/$mpi_hdf5/include"

options="${debug_option} -mpi -hdf5 --cxx=$CC --lib_path=${mpi_hdf5_library_path} --include=${mpi_hdf5_include_path}"

myoptions=$2

current=`pwd`
cd /home/changgoo/tigris/

prob=sf_cloud
./configure.py --prob=$prob --nghost=4 -fft -fb --grav=blockfft $options $2

make clean
make all -j

cp bin/athena $current/${prob}_$CC$2$debug_option.exe

cd $currnet
set +e
