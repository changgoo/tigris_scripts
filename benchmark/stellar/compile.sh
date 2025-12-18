#!/bin/sh
# tigress-classic compilation script works for stellar and tiger3
#   alias for module_icpx an module_gcc should be in .bashrc,
#   otherwise uncomment the following
source ~/.bashrc
set -e

CC=$1
if [ "$CC" == "icpx" ] ; then
    module purge; module load anaconda3/2023.3 intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6
    debug_option=""
elif [ "$CC" == "g++" ] ; then
    module purge; module load anaconda3/2025.6 gcc-toolset/14 openmpi/gcc/4.1.6
    debug_option=""
elif [ "$CC" == "g++-simd" ] ; then
    module purge; module load anaconda3/2025.6 gcc-toolset/14 openmpi/gcc/4.1.6
    debug_option=""
else
    module_gcc
    CC=g++
    debug_option="-debug"
fi
echo "CC is set to $CC"

options="${debug_option} -mpi --cxx=$CC"

physics=$2
if [ "$physics" == "hydro" ] ; then
    phy_options=""
elif [ "$physics" == "mhd" ] ; then
    phy_options="-b"
else
    echo "physics is set to hydro"
    physics=hydro
fi

current=`pwd`
SRCDIR=$HOME/athena/
cd $SRCDIR

prob=blast
./configure.py --prob=$prob $options $phy_options

make clean
make all -j4

cp bin/athena $current/${prob}_${physics}_$CC$debug_option.exe

cd $current
set +e
