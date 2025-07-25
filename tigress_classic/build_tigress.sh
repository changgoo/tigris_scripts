#!/bin/bash
# filepath: /home/changgoo/tigris_scripts/tigress_classic/build_tigress.sh
# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

set -e

# User-configurable options
MACHINE=${1:-stellar}
PHYSICS=${2:-hydro}
BUILD_OPTION=${3:-0}

# Source and build directories
SRCDIR="$HOME/tigris"
BUILDDIR="$SRCDIR"
CURDIR="$(pwd)"
PROB="tigress_classic"

# Machine-specific module loading
if [ "$MACHINE" == "stellar" ]; then
    module purge
    module load anaconda3/2023.3
    module load intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10
    CC="icpx"
    CFLAG_OPTIONS="--cxx=$CC"
elif [ "$MACHINE" == "tiger" ]; then
    module purge
    module load anaconda3/2023.3
    module load intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10
    CC="icpx"
    CFLAG_OPTIONS="--cxx=$CC"
elif [ "$MACHINE" == "anvil" ]; then
    module purge
    module load anaconda
    module load gcc
    module load openmpi
    module load fftw
    module load hdf5
    HDF5DIR="$RCAC_HDF5_ROOT"
    CFLAG="-fopenmp-simd -fwhole-program -flto=auto -ffast-math -march=znver3 -fprefetch-loop-arrays"
    CFLAG_OPTINOS="--cflag=${CFLAG}"
else
    module purge
    CC="g++"
fi

# Physics options
if [ "$PHYSICS" == "hydro" ]; then
    PHY_OPTIONS=""
elif [ "$PHYSICS" == "mhd" ]; then
    PHY_OPTIONS="-b"
elif [ "$PHYSICS" == "crmhd" ]; then
    PHY_OPTIONS="-b --cr=mg"
else
    PHY_OPTIONS=""
fi

# build option
if [ "$BUILD_OPTION" == "1" ]; then
    DEBUG_OPTION="-debug"
    CC="g++"
else
    DEBUG_OPTION=""
fi

HDF5_LIB="${HDF5DIR}/lib64"
HDF5_INC="${HDF5DIR}/include"
PATH_OPTIONS="--lib_path=${HDF5_LIB} --include=${HDF5_INC}"

EXE="${CURDIR}/${MACHINE}/${PROB}_${PHYSICS}${DEBUG_OPTION}.exe"


cd "$BUILDDIR"

if [ "$BUILD_OPTION" != "2" ]; then
    echo -e  "${GREEN}Configuring Athena++ in $BUILDDIR.. for $PHYSICS${NC}"
    ./configure.py --prob="$PROB" $DEBUG_OPTION --nghost=4 -fft -fb --grav=blockfft -mpi -hdf5 $PHY_OPTIONS $PATH_OPTIONS

    make clean
fi

echo -e  "${GREEN}Building Athena++ ${NC}"
make all -j4

cp bin/athena "$EXE"
echo -e  "${GREEN}Executable copied to $EXE${NC}"

cd "$CURDIR"
set +e