# Machine environment for Stellar (Princeton) Intel CPU nodes
#   2x Intel Xeon Platinum 9242 (Cascade Lake-AP), 96 cores/node, 4 NUMA domains,
#   AVX-512 (2 FMA units), 760 GB, HDR InfiniBand. Login nodes are Cascade Lake too.
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
MACHINE_CPU="2x Intel Xeon Platinum 9242 (Cascade Lake)"
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

# --- best flags per compiler: complete sets, winners of the flag sweep (2026-10-03) ----
# flag_variants.txt, Intel MPI, 3 runs for the top variants. s/cycle as MHD, CRMHD.
#   icpx : variant fast2  (0.740, 0.416): -fp-model=fast=2 makes NCR photochemistry 16%
#          faster than the default fp-model=fast (0.749, 0.431); precise costs 2-11%;
#          -qopt-zmm-usage=high is 4-7% slower; -march=cascadelake instead of
#          -xCASCADELAKE ties; without -ipo the link fails (omp declare simd variants).
#   GCC  : variant preset (0.822, 0.512): the fast-math + LTO variants tie within noise;
#          -mprefer-vector-width=512 is 3-6% slower (unlike Zen 5); without -ffast-math the
#          photochemistry is 60% slower (plain -O3: 1.02, 0.67).
FLAGS_GCC="-O3 -std=c++11 -march=cascadelake -ffast-math -fopenmp-simd -flto=auto -fwhole-program -fprefetch-loop-arrays"
FLAGS_ICPX="-O3 -std=c++11 -ipo -xCASCADELAKE -qopenmp-simd -fp-model=fast=2 -Wno-tautological-constant-compare -Wno-array-bounds"

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
