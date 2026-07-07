#!/bin/bash
# filepath: /home/changgoo/tigris_scripts/tigress_classic/build_tigress.sh
# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

set -e

# Defaults
MACHINE="stellar"
PHYSICS="hydro"
GRAV="fft"
BUILD_OPTION="0"
SRC="tigris"
FLUX="hll"
WORKTREE=""

usage() {
    echo -e "${RED}Usage: $0 --machine=<machine> [options]${NC}"
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  --machine=<name>    Target machine (stellar|tiger|anvil) [default: stellar]"
    echo -e "  --physics=<name>    Physics option (hydro|mhd|crmhd|*_duale|*_duals) [default: hydro]"
    echo -e "  --grav=<name>       Gravity solver (fft|none) [default: fft]"
    echo -e "  --build=<0|1|2>     0=normal, 1=debug, 2=no clean [default: 0]"
    echo -e "  --src=<name>        Source repo directory name under \$HOME [default: tigris]"
    echo -e "  --flux=<name>       Flux solver (hll|lhll) [default: hll]"
    echo -e "  --worktree=<name>   Compile from \$HOME/\$src/.worktrees/<name>"
    echo -e "${YELLOW}Example: $0 --machine=tiger --physics=mhd --worktree=mesh_level_mass_return${NC}"
    exit 1
}

if [ "$#" -lt 1 ]; then
    usage
fi

for arg in "$@"; do
    case "$arg" in
        --machine=*) MACHINE="${arg#*=}" ;;
        --physics=*) PHYSICS="${arg#*=}" ;;
        --grav=*)    GRAV="${arg#*=}" ;;
        --build=*)   BUILD_OPTION="${arg#*=}" ;;
        --src=*)     SRC="${arg#*=}" ;;
        --flux=*)    FLUX="${arg#*=}" ;;
        --worktree=*) WORKTREE="${arg#*=}" ;;
        --help|-h)   usage ;;
        *) echo -e "${RED}Unknown option: $arg${NC}"; usage ;;
    esac
done

# Source and build directories
if [ -n "$WORKTREE" ]; then
    SRCDIR="$HOME/$SRC/.worktrees/$WORKTREE"
    BRANCH=""
else
    SRCDIR="$HOME/$SRC"
    BRANCH="-master"
fi
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
    if [ "$BUILD_OPTION" == "1" ]; then
        module purge; module load anaconda3/2023.3 fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4
    fi
elif [ "$MACHINE" == "anvil" ]; then
    module purge
    module load anaconda
    module load gcc
    module load openmpi
    module load fftw
    module load hdf5
    HDF5DIR="$RCAC_HDF5_ROOT"
    CFLAG="-fopenmp-simd -fwhole-program -flto=auto -ffast-math -march=znver3 -fprefetch-loop-arrays"
    CFLAG_OPTIONS="--cflag=${CFLAG}"
else
    module purge
    CC="g++"
fi

# Physics options
if [ "$PHYSICS" == "hydro" ]; then
    PHY_OPTIONS="--flux=${FLUX}c"
elif [ "$PHYSICS" == "hydro_duale" ]; then
    PHY_OPTIONS="--dual=eint --flux=${FLUX}c"
elif [ "$PHYSICS" == "hydro_duals" ]; then
    PHY_OPTIONS="--dual=entropy --flux=${FLUX}c"
elif [ "$PHYSICS" == "mhd" ]; then
    PHY_OPTIONS="-b --flux=${FLUX}d"
elif [ "$PHYSICS" == "mhd_duale" ]; then
    PHY_OPTIONS="-b --flux=${FLUX}d --dual=eint"
elif [ "$PHYSICS" == "mhd_duals" ]; then
    PHY_OPTIONS="-b --flux=${FLUX}d --dual=entropy"
elif [ "$PHYSICS" == "crmhd" ]; then
    PHY_OPTIONS="-b --cr=mg --flux=${FLUX}d"
elif [ "$PHYSICS" == "crmhd_duale" ]; then
    PHY_OPTIONS="-b --cr=mg --flux=${FLUX}d --dual=eint"
elif [ "$PHYSICS" == "crmhd_duals" ]; then
    PHY_OPTIONS="-b --cr=mg --flux=${FLUX}d --dual=entropy"
else
    echo -e "${RED} Physics option: $PHYSICS is unavailable ${NC}"
    exit 1
fi

# build option
if [ "$BUILD_OPTION" == "1" ]; then
    #DEBUG_OPTION="-debug"
    CC="g++-simd"
    CFLAG_OPTIONS="--cxx=$CC"
else
    DEBUG_OPTION=""
fi

HDF5_LIB="${HDF5DIR}/lib64"
HDF5_INC="${HDF5DIR}/include"
PATH_OPTIONS="--lib_path=${HDF5_LIB} --include=${HDF5_INC}"

if [ "$FLUX" == "lhll" ]; then
    PHYSICS="${PHYSICS}_lhll"
fi

if [ "$GRAV" == "none" ]; then
    EXE="${CURDIR}/${MACHINE}/tigris${BRANCH}_${PHYSICS}${DEBUG_OPTION}.exe"

    cd "$BUILDDIR"

    if [ "$BUILD_OPTION" != "2" ]; then
        echo -e  "${GREEN}Configuring Athena++ in $BUILDDIR.. for $PHYSICS${NC}"
        echo -e  "./configure.py --prob="$PROB" $DEBUG_OPTION --nghost=4 -fft -fb -mpi -hdf5 $PHY_OPTIONS $PATH_OPTIONS $CFLAG_OPTIONS"
        ./configure.py --prob="$PROB" $DEBUG_OPTION --nghost=4 -fft -fb -mpi -hdf5 $PHY_OPTIONS $PATH_OPTIONS $CFLAG_OPTIONS

        make clean
    fi

else
    EXE="${CURDIR}/${MACHINE}/tigris${BRANCH}_${PHYSICS}-${GRAV}${DEBUG_OPTION}.exe"

    cd "$BUILDDIR"

    if [ "$BUILD_OPTION" != "2" ]; then
        echo -e  "${GREEN}Configuring Athena++ in $BUILDDIR.. for $PHYSICS${NC}"
        echo -e  "./configure.py --prob="$PROB" $DEBUG_OPTION --nghost=4 -fft -fb --grav=$GRAV -mpi -hdf5 $PHY_OPTIONS $PATH_OPTIONS $CFLAG_OPTIONS"
        ./configure.py --prob="$PROB" $DEBUG_OPTION --nghost=4 -fft -fb --grav="$GRAV" -mpi -hdf5 $PHY_OPTIONS $PATH_OPTIONS $CFLAG_OPTIONS

        make clean
    fi
fi

echo -e  "${GREEN}Building Athena++ ${NC}"
make all -j4

cp bin/athena "$EXE"
echo -e  "${GREEN}Executable copied to $EXE${NC}"

cd "$CURDIR"
set +e
