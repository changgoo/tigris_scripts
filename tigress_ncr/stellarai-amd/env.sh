# Machine environment for stellarai-amd CPU nodes
#   2x AMD EPYC 9475F (Turin, Zen 5), 96 cores/node, 2 NUMA domains, 16 CCDs x 6 cores
#
# Machine-env contract (see ../bench/BENCHMARK_SPEC.md and ../bench/env_template.sh).
# Sourced by build_tigress.sh (--machine=stellarai-amd), the benchmark scripts in ../bench,
# and the production slurm scripts in this directory, so builds and jobs always load the
# same modules.
#
#   source env.sh
#   load_toolchain <toolchain>   # loads modules, sets CXX_CHOICE and CFLAG
#
# Toolchains (MPI-enabled HDF5 and AOCL-FFTW in every stack; there is no fftw module).
# gcc-impi is the default: fastest for both MHD and CRMHD 8 pc runs (see README.md).
#   gcc-impi  : GCC 14                + Intel MPI 2021.18
#   icpx-impi : oneAPI 2026.0 icpx    + Intel MPI 2021.18
#   aocc      : AOCC 5.2 clang++      + Open MPI 5.0.10
#   gcc       : GCC 14                + Open MPI 5.0.10
#   icpx      : oneAPI 2026.0 icpx    + Open MPI 5.0.10
#
# Notes
# - configure.py's "icpx" preset hard-codes -xhost, which on AMD produces a binary that
#   refuses to run ("can only be run on Intel(R) processors"). The icpx toolchains
#   therefore use the generic "clang++" preset (mpicxx wraps icpx) with -march=znver5.
#   The resulting build reports "Compiler = clang++" in its configure summary.
# - All toolchains use fast floating-point math, matching icpx's default fp-model=fast
#   used for the Stellar production builds.

# --- machine description ------------------------------------------------------------
MACHINE_CPU="2x AMD EPYC 9475F (Zen 5)"
CORES_PER_NODE=96
SLURM_PARTITION=cpu
SLURM_ACCOUNT=eost
SLURM_MAX_JOBS=5                       # QOSMaxSubmitJobPerUserLimit
SCRATCH_BASE=/scratch/gpfs/EOST/$USER  # /scratch/gpfs/$USER does not exist here
MAKE_JOBS=16
MPI_LAUNCH="srun --cpu-bind=cores"

# --- toolchains ---------------------------------------------------------------------
TOOLCHAINS="gcc-impi icpx-impi aocc gcc icpx"
DEFAULT_TOOLCHAIN=gcc-impi

# --- benchmark checkpoints (8 pc, 384 meshblocks) ------------------------------------
BENCH_RST_mhd=$SCRATCH_BASE/mhd-ncr-8pc/TIGRESS_NCR.00006.rst      # t=300
BENCH_RST_crmhd=$SCRATCH_BASE/crmhd-ncr-8pc/TIGRESS_NCR.00003.rst  # t=150, CR<->NCR coupled

load_toolchain() {
    local tc=${1:-$DEFAULT_TOOLCHAIN}
    local fftw_gcc=aocl/gcc/ST/5.3.0
    local fftw_aocc=aocl/aocc/ST/5.3.0
    local icpx_flags="-march=znver5 -ipo -qopenmp-simd -Wno-tautological-constant-compare -Wno-array-bounds"
    module purge
    case "$tc" in
        gcc-impi)
            module load gcc/14 intel-mpi/gcc/2021.18 \
                hdf5/gcc/intel-mpi/1.14.6 $fftw_gcc
            CXX_CHOICE="g++-simd"   # -O3 -fopenmp-simd -fwhole-program -flto -ffast-math
            CFLAG="-march=znver5 -flto=auto"
            ;;
        icpx-impi)
            module load intel-oneapi/2026.0 intel-mpi/oneapi/2021.18 \
                hdf5/oneapi-2026.0/intel-mpi/1.14.6 $fftw_gcc
            CXX_CHOICE="clang++"
            CFLAG="$icpx_flags"
            ;;
        aocc)
            module load aocc/5.2.0 openmpi/aocc-5.2.0/5.0.10 \
                hdf5/aocc-5.2.0/openmpi-5.0.10/1.14.6 $fftw_aocc
            CXX_CHOICE="clang++"
            CFLAG="-march=znver5 -ffast-math -fopenmp-simd -flto -fuse-ld=lld"
            ;;
        gcc)
            module load gcc/14 openmpi/gcc/5.0.10 \
                hdf5/gcc/openmpi-5.0.10/1.14.6 $fftw_gcc
            CXX_CHOICE="g++-simd"
            CFLAG="-march=znver5 -flto=auto"
            ;;
        icpx)
            module load intel-oneapi/2026.0 openmpi/oneapi-2026.0/5.0.10 \
                hdf5/oneapi-2026.0/openmpi-5.0.10/1.14.6 $fftw_gcc
            CXX_CHOICE="clang++"
            CFLAG="$icpx_flags"
            ;;
        *)
            echo "load_toolchain: unknown toolchain '$tc' ($TOOLCHAINS)" >&2
            return 1
            ;;
    esac
}
