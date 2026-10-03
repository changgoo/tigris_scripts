#!/bin/bash
# filepath: /home/changgoo/tigris_scripts/tigress_classic/build_tigress.sh
#
# Build script for the TIGRESS-classic problem generator (src/pgen/tigress_classic.cpp).
#
# Machines with a <machine>/env.sh next to this script (stellar, tiger, stellarai-amd) use
# the machine-env contract of ../tigress_ncr/bench/BENCHMARK_SPEC.md; their env.sh reuses
# the toolchains and flags benchmarked for TIGRESS-NCR:
#   --cc=<toolchain> selects a module stack from env.sh (--cc=all builds each in turn;
#     no --cc means the benchmarked DEFAULT_TOOLCHAIN);
#   the compiler flags are the toolchain's complete, benchmarked TC_CXXFLAGS from env.sh
#     (or --cxxflags=...). They REPLACE configure.py's --cxx preset flags in the generated
#     Makefile; the preset is only used to run configure;
#   the executable is <machine>/tigris_<physics>-<grav>-<toolchain>[-<suffix>].exe,
#     with a .buildinfo file recording modules, flags and the source commit.
# Other machines (anvil, ...) keep their hard-coded module sets and configure presets below.

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
EXE_SUFFIX=""
TOOLCHAIN=""
MAKE_JOBS=4
CXXFLAGS_OVERRIDE=""
SRCDIR_OVERRIDE=""

usage() {
    echo -e "${RED}Usage: $0 --machine=<machine> [options]${NC}"
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  --machine=<name>    Target machine (stellar|stellarai-amd|tiger|anvil) [default: stellar]"
    echo -e "  --physics=<name>    Physics option (hydro|mhd|crmhd|*_duale|*_duals) [default: hydro]"
    echo -e "  --grav=<name>       Gravity solver (fft|blockfft|none) [default: fft]"
    echo -e "  --build=<0|1|2>     0=normal, 1=debug, 2=no clean [default: 0]"
    echo -e "  --src=<name>        Source repo directory name under \$HOME [default: tigris]"
    echo -e "  --flux=<name>       Flux solver (hll|lhll) [default: hll]"
    echo -e "  --worktree=<name>   Compile from \$HOME/\$src/.worktrees/<name>"
    echo -e "  --exe_suffix=<tag>  Append -<tag> to the executable name (keeps the production exe intact)"
    echo -e "  --cc=<toolchain>    machines with <machine>/env.sh: a toolchain from its TOOLCHAINS,"
    echo -e "                      or 'all' [default: DEFAULT_TOOLCHAIN]; the exe name gets -<toolchain>"
    echo -e "  --cxxflags=<flags>  env.sh machines: complete compiler flags instead of the toolchain's"
    echo -e "                      TC_CXXFLAGS (flag sweeps; combine with --exe_suffix)"
    echo -e "  --srcdir=<path>     Compile from this source tree (overrides --src/--worktree)"
    echo -e "${YELLOW}Example: $0 --machine=tiger --physics=mhd --worktree=mesh_level_mass_return${NC}"
    echo -e "${YELLOW}         $0 --machine=stellarai-amd --cc=gcc-impi --physics=crmhd${NC}"
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
        --exe_suffix=*) EXE_SUFFIX="-${arg#*=}" ;;
        --cc=*)      TOOLCHAIN="${arg#*=}" ;;
        --cxxflags=*) CXXFLAGS_OVERRIDE="${arg#*=}" ;;
        --srcdir=*)  SRCDIR_OVERRIDE="${arg#*=}" ;;
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
if [ -n "$SRCDIR_OVERRIDE" ]; then
    SRCDIR="$SRCDIR_OVERRIDE"
    BRANCH=""
fi
BUILDDIR="$SRCDIR"
CURDIR="$(pwd)"
PROB="tigress_classic"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACHINE_ENV="$SCRIPT_DIR/$MACHINE/env.sh"

# --cc=all: build every toolchain of the machine, one at a time (they share $SRCDIR).
if [ "$TOOLCHAIN" == "all" ]; then
    [ -f "$MACHINE_ENV" ] || { echo -e "${RED}--cc=all needs $MACHINE_ENV${NC}"; exit 1; }
    TOOLCHAINS=$(source "$MACHINE_ENV" && echo "$TOOLCHAINS")
    for tc in $TOOLCHAINS; do
        args=()
        for arg in "$@"; do [[ $arg == --cc=* ]] || args+=("$arg"); done
        echo -e "${CYAN}=== toolchain $tc ===${NC}"
        bash "${BASH_SOURCE[0]}" "${args[@]}" --cc="$tc"
    done
    exit 0
fi

# Machine-specific module loading
if [ -f "$MACHINE_ENV" ]; then
    # Module stacks and flags live in <machine>/env.sh, which the slurm scripts can source
    # too. The toolchain is part of the exe name so a job can never load a module set
    # that does not match its executable.
    source "$MACHINE_ENV"
    : "${TOOLCHAIN:=$DEFAULT_TOOLCHAIN}"
    load_toolchain "$TOOLCHAIN"
    CFLAG_OPTIONS=(--cxx="$CXX_PRESET")
    FULL_CXXFLAGS="${CXXFLAGS_OVERRIDE:-$TC_CXXFLAGS}"
    [ -n "$FULL_CXXFLAGS" ] || { echo -e "${RED}TC_CXXFLAGS not set for $TOOLCHAIN in $MACHINE_ENV${NC}"; exit 1; }
    EXE_SUFFIX="-${TOOLCHAIN}${EXE_SUFFIX}"
    CURDIR="$SCRIPT_DIR"   # exe goes to $SCRIPT_DIR/$MACHINE regardless of the cwd
elif [ -n "$TOOLCHAIN" ]; then
    echo -e "${RED}--cc needs $MACHINE_ENV${NC}"; exit 1
elif [ "$MACHINE" == "anvil" ]; then
    module purge
    module load anaconda
    module load gcc
    module load openmpi
    module load fftw
    module load hdf5
    HDF5DIR="$RCAC_HDF5_ROOT"
    CFLAG="-fopenmp-simd -fwhole-program -flto=auto -ffast-math -march=znver3 -fprefetch-loop-arrays"
    CFLAG_OPTIONS=(--cflag="$CFLAG")
else
    module purge
    CC="g++"
fi

# HDF5DIR is set by the hdf5 module on stellar/tiger; fall back to HDF5_ROOT
: "${HDF5DIR:=$HDF5_ROOT}"

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

# build option (debug uses g++-simd; not applicable to <machine>/env.sh machines)
if [ "$BUILD_OPTION" == "1" ] && [ ! -f "$MACHINE_ENV" ]; then
    #DEBUG_OPTION="-debug"
    CC="g++-simd"
    CFLAG_OPTIONS=(--cxx=$CC)
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
    EXE="${CURDIR}/${MACHINE}/tigris${BRANCH}_${PHYSICS}${DEBUG_OPTION}${EXE_SUFFIX}.exe"

    cd "$BUILDDIR"

    if [ "$BUILD_OPTION" != "2" ]; then
        echo -e  "${GREEN}Configuring Athena++ in $BUILDDIR.. for $PHYSICS${NC}"
        echo -e  "./configure.py --prob="$PROB" $DEBUG_OPTION --nghost=4 -fft -fb -mpi -hdf5 $PHY_OPTIONS $PATH_OPTIONS ${CFLAG_OPTIONS[*]}"
        python3 ./configure.py --prob="$PROB" $DEBUG_OPTION --nghost=4 -fft -fb -mpi -hdf5 $PHY_OPTIONS $PATH_OPTIONS "${CFLAG_OPTIONS[@]}"

        make clean
    fi

else
    EXE="${CURDIR}/${MACHINE}/tigris${BRANCH}_${PHYSICS}-${GRAV}${DEBUG_OPTION}${EXE_SUFFIX}.exe"

    cd "$BUILDDIR"

    if [ "$BUILD_OPTION" != "2" ]; then
        echo -e  "${GREEN}Configuring Athena++ in $BUILDDIR.. for $PHYSICS${NC}"
        echo -e  "./configure.py --prob="$PROB" $DEBUG_OPTION --nghost=4 -fft -fb --grav=$GRAV -mpi -hdf5 $PHY_OPTIONS $PATH_OPTIONS ${CFLAG_OPTIONS[*]}"
        python3 ./configure.py --prob="$PROB" $DEBUG_OPTION --nghost=4 -fft -fb --grav="$GRAV" -mpi -hdf5 $PHY_OPTIONS $PATH_OPTIONS "${CFLAG_OPTIONS[@]}"

        make clean
    fi
fi

# env.sh machines: replace the preset's compiler flags with the toolchain's complete flags.
# CXXFLAGS is used for compiling and linking (LTO/IPO); the HDF5 include path is re-added.
if [ -n "$FULL_CXXFLAGS" ]; then
    sed -i "s|^CXXFLAGS := .*|CXXFLAGS := ${FULL_CXXFLAGS} -I${HDF5_INC}|" Makefile
    echo -e "${GREEN}CXXFLAGS := ${FULL_CXXFLAGS} -I${HDF5_INC}${NC}"
fi

echo -e  "${GREEN}Building Athena++ ${NC}"
make all -j"$MAKE_JOBS"

mkdir -p "$(dirname "$EXE")"
cp bin/athena "$EXE"
echo -e  "${GREEN}Executable copied to $EXE${NC}"

# Provenance: what was built, from which commit, with which modules and flags.
{
    echo "exe:       $(basename "$EXE")"
    echo "date:      $(date -Iseconds)"
    echo "host:      $(hostname)"
    echo "machine:   $MACHINE  toolchain: ${TOOLCHAIN:-n/a}"
    echo "source:    $SRCDIR"
    echo "commit:    $(git -C "$SRCDIR" log -1 --format='%H %s')"
    echo "dirty:     $(git -C "$SRCDIR" status --porcelain --untracked-files=no | wc -l) modified files"
    echo "configure: $PHY_OPTIONS ${CFLAG_OPTIONS[*]}"
    echo "flags:     ${FULL_CXXFLAGS:+$([ -n "$CXXFLAGS_OVERRIDE" ] && echo "--cxxflags override" || echo "TC_CXXFLAGS from env.sh")}"
    echo "CXX:       $(sed -n 's/^CXX := //p' "$SRCDIR/Makefile") -> $( (mpicxx --showme 2>/dev/null || mpicxx -show 2>/dev/null) | awk '{print $1}')"
    sed -n 's/^CXXFLAGS := /CXXFLAGS:  /p; s/^LDFLAGS := /LDFLAGS:   /p' "$SRCDIR/Makefile"
    echo "modules:   $(module -t list 2>&1 | grep -v ':$' | tr '\n' ' ')"
} > "${EXE%.exe}.buildinfo"

cd "$CURDIR"
set +e
