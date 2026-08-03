#!/bin/bash
# filepath: /home/changgoo/tigris_scripts/tigress_ncr/build_tigress.sh
#
# Build script for the TIGRESS-NCR problem generator (src/pgen/tigress_ncr.cpp):
# ray-tracing radiation + NCR photochemistry on top of tigress_classic.
#
# Modeled on tigris_scripts/tigress_classic/build_tigress.sh. The only structural
# difference is the "-ncr" configure flag, which enables NCR photochemistry and
# automatically sets --nspecies=3 and --nfreq_rayt=3 (LyC, LW, PE). Do NOT also
# pass --nspecies; configure.py will error.
#
# Milestone 1 (default): MHD-only NCR  --physics=mhd
# Milestone 2:           CRMHD NCR     --physics=crmhd  (adds --cr=mg)

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

set -e

# Defaults
MACHINE="stellar"
PHYSICS="mhd"
GRAV="fft"
BUILD_OPTION="0"
SRC="tigris"
FLUX="hll"
WORKTREE=""

usage() {
    echo -e "${RED}Usage: $0 --machine=<machine> [options]${NC}"
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  --machine=<name>    Target machine (stellar|tiger|anvil) [default: stellar]"
    echo -e "  --physics=<name>    Physics option (mhd|crmhd|*_duale|*_duals) [default: mhd]"
    echo -e "  --grav=<name>       Gravity solver (fft|none) [default: fft]"
    echo -e "  --build=<0|1|2>     0=normal, 1=debug, 2=no clean [default: 0]"
    echo -e "  --src=<name>        Source repo directory name under \$HOME [default: tigris]"
    echo -e "  --flux=<name>       Flux solver (hll|lhll) [default: hll]"
    echo -e "  --worktree=<name>   Compile from \$HOME/\$src/.worktrees/<name>"
    echo -e "${YELLOW}Example: $0 --machine=stellar --physics=mhd --worktree=tigress-ncr${NC}"
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
PROB="tigress_ncr"

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

# HDF5DIR is set by the hdf5 module on stellar/tiger; fall back to HDF5_ROOT
: "${HDF5DIR:=$HDF5_ROOT}"

# Physics options (all TIGRESS-NCR builds add -ncr => NFREQ_RAYT=3, NSCALARS_PHOTCHEM=3)
if [ "$PHYSICS" == "mhd" ]; then
    PHY_OPTIONS="-b --flux=${FLUX}d -ncr"
elif [ "$PHYSICS" == "mhd_duale" ]; then
    PHY_OPTIONS="-b --flux=${FLUX}d --dual=eint -ncr"
elif [ "$PHYSICS" == "mhd_duals" ]; then
    PHY_OPTIONS="-b --flux=${FLUX}d --dual=entropy -ncr"
elif [ "$PHYSICS" == "crmhd" ]; then
    PHY_OPTIONS="-b --cr=mg --flux=${FLUX}d -ncr"
elif [ "$PHYSICS" == "crmhd_duale" ]; then
    PHY_OPTIONS="-b --cr=mg --flux=${FLUX}d --dual=eint -ncr"
elif [ "$PHYSICS" == "crmhd_duals" ]; then
    PHY_OPTIONS="-b --cr=mg --flux=${FLUX}d --dual=entropy -ncr"
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
    EXE="${CURDIR}/${MACHINE}/tigris${BRANCH}_ncr_${PHYSICS}${DEBUG_OPTION}.exe"

    cd "$BUILDDIR"

    if [ "$BUILD_OPTION" != "2" ]; then
        echo -e  "${GREEN}Configuring Athena++ in $BUILDDIR.. for $PHYSICS${NC}"
        echo -e  "./configure.py --prob="$PROB" $DEBUG_OPTION --nghost=4 -fft -fb -mpi -hdf5 $PHY_OPTIONS $PATH_OPTIONS $CFLAG_OPTIONS"
        ./configure.py --prob="$PROB" $DEBUG_OPTION --nghost=4 -fft -fb -mpi -hdf5 $PHY_OPTIONS $PATH_OPTIONS $CFLAG_OPTIONS

        make clean
    fi

else
    EXE="${CURDIR}/${MACHINE}/tigris${BRANCH}_ncr_${PHYSICS}-${GRAV}${DEBUG_OPTION}.exe"

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

mkdir -p "$(dirname "$EXE")"
cp bin/athena "$EXE"
echo -e  "${GREEN}Executable copied to $EXE${NC}"

cd "$CURDIR"
set +e
