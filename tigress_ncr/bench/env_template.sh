# Machine environment for <MACHINE>      (copy to tigress_ncr/<MACHINE>/env.sh)
#   <CPU model, sockets x cores, NUMA layout, interconnect>
#
# Machine-env contract (BENCHMARK_SPEC.md). Sourced by build_tigress.sh
# (--machine=<MACHINE>), bench/submit.sh, bench/tigress_ncr_8pc_bench.slurm and the
# production slurm scripts in <MACHINE>/. Must be side-effect free apart from defining
# the variables and load_toolchain below (it is sourced in subshells to read TOOLCHAINS).
#
# Toolchains: <name> : <compiler> + <MPI>, with MPI-enabled (parallel) HDF5 and FFTW3.
# Record here anything machine-specific you learned (missing modules, bad flags, ...).

# --- machine description ------------------------------------------------------------
MACHINE_CPU="<cpu model>"
CORES_PER_NODE=<physical cores per node>
SLURM_PARTITION=<partition>
SLURM_ACCOUNT=<account or empty>
SLURM_MAX_JOBS=<max queued jobs per user>   # sacctmgr show qos / trial sbatch
SLURM_QUEUE_FILTER=""                       # squeue filter for jobs that count, e.g. "--qos=<debug qos>"
SLURM_EXTRA=""                              # extra sbatch options, e.g. "--constraint=..."
SCRATCH_BASE=<scratch root>                 # run dirs: $SCRATCH_BASE/tigress_ncr/...
MAKE_JOBS=16
MPI_LAUNCH="srun --cpu-bind=cores"

# --- toolchains (DEFAULT = benchmarked best; build_tigress.sh uses it without --cc) ----
TOOLCHAINS="<tc1> <tc2> ..."
DEFAULT_TOOLCHAIN=<tc1>

# --- benchmark checkpoints (8 pc, 384 meshblocks of 32^3) -------------------------------
BENCH_DATA=/projects/EOSTRIKE/tigris-benchmark   # Princeton clusters; elsewhere: your copy
BENCH_CACHE=$SCRATCH_BASE/tigris-benchmark      # compute-visible; bench/submit.sh stages here
BENCH_RST_mhd=mhd-ncr-8pc/TIGRESS_NCR.00006.rst
BENCH_RST_crmhd=crmhd-ncr-8pc/TIGRESS_NCR.00003.rst

# --- best COMPLETE compiler flags per compiler (start values; replace with sweep winners)
# They replace configure.py's preset flags in the Makefile (compile and link).
FLAGS_GCC="-O3 -std=c++11 -march=<arch> -ffast-math -fopenmp-simd -flto=auto -fwhole-program -fprefetch-loop-arrays"
FLAGS_CLANG="-O3 -std=c++11 -march=<arch> -ffast-math -fopenmp-simd -flto -fuse-ld=lld"

# load_toolchain <tc>: module purge + module load the stack, then set
#   CXX_PRESET  : configure.py --cxx preset used only to run configure (g++, clang++, ...)
#   TC_CXXFLAGS : the complete compiler flags (usually one of FLAGS_* above)
# Export the MPI wrapper's compiler variable if the stack mixes vendors
# (e.g. I_MPI_CXX=clang++). Return non-zero for an unknown toolchain.
load_toolchain() {
    local tc=${1:-$DEFAULT_TOOLCHAIN}
    module purge
    unset I_MPI_CXX
    case "$tc" in
        <tc1>)
            module load <compiler> <mpi> <hdf5-for-that-compiler-and-mpi> <fftw>
            CXX_PRESET=g++; TC_CXXFLAGS=$FLAGS_GCC ;;
        *)
            echo "load_toolchain: unknown toolchain '$tc' ($TOOLCHAINS)" >&2
            return 1 ;;
    esac
}
