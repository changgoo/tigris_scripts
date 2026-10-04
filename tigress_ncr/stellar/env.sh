# Machine environment for Stellar (Princeton) Intel CPU nodes
#   4x Intel Xeon Platinum 8268 (Cascade Lake, 24 cores, 2.9 GHz), 96 cores/node, 4 NUMA
#   domains, AVX-512 (2 FMA units), 760 GB, ConnectX-6 InfiniBand at 100 Gb/s.
#   Login nodes are Cascade Lake too (Xeon Gold 6242R).
#
# Machine-env contract (see ../bench/BENCHMARK_SPEC.md and ../bench/env_template.sh).
# Sourced by build_tigress.sh (--machine=stellar), the benchmark scripts in ../bench,
# and the env.sh-style production slurm scripts in this directory, so builds and jobs
# always load the same modules.
#
#   source env.sh
#   load_toolchain <toolchain>   # loads modules, sets CXX_PRESET and TC_CXXFLAGS
#
# Toolchains (MPI-enabled HDF5 1.14.4 and FFTW 3.3.10 modules in every stack).
# icpx-impi is the default: fastest for both MHD and CRMHD 8 pc runs (see README.md).
#   icpx-impi  : oneAPI 2024.2 icpx  + Intel MPI 2021.13
#   icpx       : oneAPI 2024.2 icpx  + Open MPI 4.1.6   (the stack of the legacy stellar build)
#   gcc-impi   : GCC 13 (gcc-toolset)+ Intel MPI 2021.13 (gcc-built HDF5)
#   gcc        : GCC 13 (gcc-toolset)+ Open MPI 4.1.6
# GCC 13 needs a one-line source fix to link this code with LTO (Accretion::rctrl; README.md).
#
# Compiler flags: TC_CXXFLAGS is the COMPLETE flag set (optimization, arch, LTO/IPO, math
# mode, -std); build_tigress.sh writes it over configure.py's preset flags.
#
# Notes
# - Slurm routes jobs by walltime: <=30 min -> QOS stellar-debug (partition "all" with the
#   "intel" feature forced, <=2 running and <=10 queued per user); the partition and
#   account given here are overwritten by the site's job_submit filter.
# - NVHPC 25.5 exists, but nvc++ is not a contender for CPU-only code on x86 and has no
#   matching parallel HDF5; it was left out.
# - /projects is mounted on login nodes only; bench/submit.sh stages the checkpoints from
#   BENCH_DATA to BENCH_CACHE on scratch before submitting.

# --- machine description ------------------------------------------------------------
MACHINE_CPU="4x Intel Xeon Platinum 8268 (Cascade Lake)"
CORES_PER_NODE=96
SLURM_PARTITION=pu
SLURM_ACCOUNT=eost
SLURM_MAX_JOBS=10                      # stellar-debug: 10 queued, 2 running per user
SLURM_QUEUE_FILTER="--qos=stellar-debug"  # count only bench jobs against SLURM_MAX_JOBS
SLURM_EXTRA=""
SCRATCH_BASE=/scratch/gpfs/$USER
MAKE_JOBS=16
MPI_LAUNCH="srun --cpu-bind=cores"

# --- toolchains ---------------------------------------------------------------------
TOOLCHAINS="icpx-impi icpx gcc-impi gcc"
DEFAULT_TOOLCHAIN=icpx-impi

# --- benchmark checkpoints (8 pc, 384 meshblocks) ------------------------------------
BENCH_DATA=/projects/EOSTRIKE/tigris-benchmark   # shared by Princeton clusters (login nodes)
BENCH_CACHE=$SCRATCH_BASE/tigris-benchmark      # compute-node visible copy
BENCH_RST_mhd=mhd-ncr-8pc/TIGRESS_NCR.00006.rst      # t=300
BENCH_RST_crmhd=crmhd-ncr-8pc/TIGRESS_NCR.00003.rst  # t=150, CR<->NCR coupled

# --- flags per compiler: complete sets, from the flag sweep (2026-10-03), restricted to
# flags that keep NaN checks (2026-10-04; see the note above FLAGS_ICPX and README.md).
# flag_variants.txt, Intel MPI, 3 runs for the top variants. s/cycle as MHD, CRMHD.
#   icpx : default fp-model=fast (0.749, 0.431). The sweep winner fast2 (0.740, 0.416;
#          -fp-model=fast=2 makes NCR photochemistry 16% faster) removes NaN checks and is
#          benchmark-only; precise costs 2-11%;
#          -qopt-zmm-usage=high is 4-7% slower; -march=cascadelake instead of
#          -xCASCADELAKE ties; without -ipo the link fails (omp declare simd variants).
#   GCC  : variant preset (0.822, 0.512): the fast-math + LTO variants tie within noise;
#          -mprefer-vector-width=512 is 3-6% slower (unlike Zen 5); without -ffast-math the
#          photochemistry is 60% slower (plain -O3: 1.02, 0.67). -fno-finite-math-only
#          keeps the NaN checks that -ffast-math would remove (cost not benchmarked yet).
FLAGS_GCC="-O3 -std=c++11 -march=cascadelake -ffast-math -fno-finite-math-only -fopenmp-simd -flto=auto -fwhole-program -fprefetch-loop-arrays"
# fp-model=fast, not the sweep winner fast=2: fast=2 assumes no NaNs, so every NaN check in
# the solver (std::isnan, x != x, !(x >= 0); e.g. the C2P floors, CR-FOFC, CRAverage, the
# NCR bail-out) compiles to false, and x/x folds to 1. The cost is ~3.5% on CRMHD
# (0.431 vs 0.416 s/cycle). Checked 2026-10-04 with a small isnan test under icpx 2024.2.
FLAGS_ICPX="-O3 -std=c++11 -ipo -xCASCADELAKE -qopenmp-simd -fp-model=fast -Wno-tautological-constant-compare -Wno-array-bounds"

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
        gcc-impi)
            module load gcc-toolset/13 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4 fftw/gcc/3.3.10
            CXX_PRESET=g++;     TC_CXXFLAGS=$FLAGS_GCC ;;
        gcc)
            module load gcc-toolset/13 openmpi/gcc/4.1.6 hdf5/gcc/openmpi-4.1.6/1.14.4 fftw/gcc/3.3.10
            CXX_PRESET=g++;     TC_CXXFLAGS=$FLAGS_GCC ;;
        *)
            echo "load_toolchain: unknown toolchain '$tc' ($TOOLCHAINS)" >&2
            return 1 ;;
    esac
}
