# Machine environment for Tiger (tiger3, Princeton) CPU nodes
#   2x Intel Xeon Platinum 8480+ (Sapphire Rapids, 56 cores, 2.0 GHz base / 3.8 GHz turbo),
#   112 cores/node, 2 NUMA domains (one per socket), 105 MB L3 per socket, AVX-512 (2 FMA
#   units) + AMX, 1 TB per node, InfiniBand (Slurm topology: LinkSpeed=200, i.e. NDR200).
#   Login nodes are the same CPU (Xeon 8480+), so login-node builds run on compute nodes.
#
# Machine-env contract (see ../bench/BENCHMARK_SPEC.md and ../bench/env_template.sh).
# Sourced by build_tigress.sh (--machine=tiger), the benchmark scripts in ../bench, and
# the env.sh-style production slurm scripts in this directory, so builds and jobs always
# load the same modules.
#
#   source env.sh
#   load_toolchain <toolchain>   # loads modules, sets CXX_PRESET and TC_CXXFLAGS
#
# Toolchains (MPI-enabled HDF5 1.14.4 and FFTW 3.3.10 modules in every stack).
#   icpx-impi     : oneAPI 2024.2 icpx + Intel MPI 2021.13
#   icpx          : oneAPI 2024.2 icpx + Open MPI 4.1.6   (the stack of the legacy tiger build)
#   icpx2026-impi : oneAPI 2026.0 icpx + Intel MPI 2021.18 (HDF5 built with oneAPI 2024.2 +
#                   Intel MPI 2021.13; same C and MPI ABI)
#   gcc-impi      : GCC 11 (system)    + Intel MPI 2021.13 (gcc-built HDF5)
#   gcc           : GCC 11 (system)    + Open MPI 4.1.6
# icpx-impi is the default: fastest for MHD and CRMHD together (see README.md). The three
# Intel MPI stacks tie before the flag sweep; Open MPI 4.1.6 is 32% slower for MHD (ray
# tracing) and ties for CRMHD.
# There is no gcc-toolset on tiger; GCC 11.5 is the only GCC. It needs the one-line
# Accretion::rctrl fix to link with LTO (as GCC 13 on stellar; see ../stellar/README.md).
#
# Compiler flags: TC_CXXFLAGS is the COMPLETE flag set (optimization, arch, LTO/IPO, math
# mode, -std); build_tigress.sh writes it over configure.py's preset flags.
#
# Notes
# - 384 ranks on 112-core nodes: submit.sh requests 4 nodes x 96 ranks (16 idle cores/node).
# - /projects is mounted on login nodes only; bench/submit.sh stages the checkpoints from
#   BENCH_DATA to BENCH_CACHE on scratch before submitting.
# - Scratch is /scratch/gpfs/EOST/$USER (not /scratch/gpfs/$USER).

# --- machine description ------------------------------------------------------------
MACHINE_CPU="2x Intel Xeon Platinum 8480+ (Sapphire Rapids)"
CORES_PER_NODE=112
SLURM_PARTITION=cpu
SLURM_ACCOUNT=eost
SLURM_MAX_JOBS=5                       # QOS test (<=1 h jobs): 5 queued, 2 running per user
SLURM_QUEUE_FILTER="--qos=test"        # count only bench jobs against SLURM_MAX_JOBS
SLURM_EXTRA=""
SCRATCH_BASE=/scratch/gpfs/EOST/$USER
MAKE_JOBS=16
MPI_LAUNCH="srun --cpu-bind=cores"

# --- toolchains ---------------------------------------------------------------------
TOOLCHAINS="icpx-impi icpx icpx2026-impi gcc-impi gcc"
DEFAULT_TOOLCHAIN=icpx-impi

# --- benchmark checkpoints (8 pc, 384 meshblocks) ------------------------------------
BENCH_DATA=/projects/EOSTRIKE/tigris-benchmark   # shared by Princeton clusters (login nodes)
BENCH_CACHE=$SCRATCH_BASE/tigris-benchmark      # compute-node visible copy
BENCH_RST_mhd=mhd-ncr-8pc/TIGRESS_NCR.00006.rst      # t=300
BENCH_RST_crmhd=crmhd-ncr-8pc/TIGRESS_NCR.00003.rst  # t=150, CR<->NCR coupled

# --- flags per compiler: complete sets, from the flag sweep (2026-10-03), restricted to
# flags that keep NaN checks (2026-10-04; see ../README.md, "Floating-point model").
# flag_variants.txt, Intel MPI, median of 3 runs for the top variants. s/cycle as MHD, CRMHD.
#   icpx : default fp-model=fast (preset: 0.529, 0.343). The sweep winner fast2 (0.512, 0.328;
#          -fp-model=fast=2 makes NCR photochemistry 25% faster) removes NaN checks and is
#          benchmark-only; adding
#          -qopt-zmm-usage=high ties (0.519, 0.326); oneAPI 2026.0 with fast2 ties (0.523,
#          0.327); precise costs 6-14% (vs preset); -march=sapphirerapids instead of
#          -xSAPPHIRERAPIDS is within noise for MHD, but its CRMHD integrator is 7% slower.
#   GCC  : variant preset (0.533, 0.347): every fast-math + LTO variant ties within the
#          placement noise (+-3%); without -ffast-math the photochemistry is 25-40% slower
#          (safe-lto: 0.576, 0.393; plain -O3: 0.601, 0.419). -fno-finite-math-only keeps the
#          NaN checks that -ffast-math would remove (cost not benchmarked yet).
# NaN checks: fp-model=fast=2 and plain -ffast-math assume finite math, so every NaN test in
# the solver (C2P floors, CR-FOFC, CRAverage, the NCR bail-out) compiles to false;
# build_tigress.sh refuses such flags (bench/nan_check.cpp).
FLAGS_GCC="-O3 -std=c++11 -march=sapphirerapids -ffast-math -fno-finite-math-only -fopenmp-simd -flto=auto -fwhole-program -fprefetch-loop-arrays"
FLAGS_ICPX="-O3 -std=c++11 -ipo -xSAPPHIRERAPIDS -qopenmp-simd -fp-model=fast -Wno-tautological-constant-compare -Wno-array-bounds"

load_toolchain() {
    local tc=${1:-$DEFAULT_TOOLCHAIN}
    module purge
    unset I_MPI_CXX
    case "$tc" in
        icpx-impi)
            module load intel-oneapi/2024.2 intel-mpi/oneapi/2021.13 \
                hdf5/oneapi-2024.2/intel-mpi/1.14.4 fftw/oneapi-2024.2/3.3.10
            CXX_PRESET=clang++; TC_CXXFLAGS=$FLAGS_ICPX ;;
        icpx)
            module load intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 \
                hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10
            CXX_PRESET=clang++; TC_CXXFLAGS=$FLAGS_ICPX ;;
        icpx2026-impi)
            module load intel-oneapi/2026.0 intel-mpi/oneapi/2021.18 \
                hdf5/oneapi-2024.2/intel-mpi/1.14.4 fftw/oneapi-2024.2/3.3.10
            CXX_PRESET=clang++; TC_CXXFLAGS=$FLAGS_ICPX ;;
        gcc-impi)
            module load intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4 fftw/gcc/3.3.10
            CXX_PRESET=g++;     TC_CXXFLAGS=$FLAGS_GCC ;;
        gcc)
            module load openmpi/gcc/4.1.6 hdf5/gcc/openmpi-4.1.6/1.14.4 fftw/gcc/3.3.10
            CXX_PRESET=g++;     TC_CXXFLAGS=$FLAGS_GCC ;;
        *)
            echo "load_toolchain: unknown toolchain '$tc' ($TOOLCHAINS)" >&2
            return 1 ;;
    esac
}
