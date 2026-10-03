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
SLURM_EXTRA=""                              # extra sbatch options, e.g. "--constraint=..."
SCRATCH_BASE=<scratch root>                 # run dirs: $SCRATCH_BASE/tigress_ncr/...
MAKE_JOBS=16
MPI_LAUNCH="srun --cpu-bind=cores"

# --- toolchains (first = preferred order for reports; DEFAULT is set after benchmarking) -
TOOLCHAINS="<tc1> <tc2> ..."
DEFAULT_TOOLCHAIN=<tc1>

# --- benchmark checkpoints (8 pc, 384 meshblocks of 32^3) -------------------------------
BENCH_RST_mhd=$SCRATCH_BASE/mhd-ncr-8pc/TIGRESS_NCR.00006.rst
BENCH_RST_crmhd=$SCRATCH_BASE/crmhd-ncr-8pc/TIGRESS_NCR.00003.rst

# load_toolchain <tc>: module purge + module load the stack, then set
#   CXX_CHOICE : configure.py --cxx preset (g++, g++-simd, clang++, icpx, ...)
#   CFLAG      : appended to compile AND link flags via --cflag (arch, LTO/IPO, fast math)
# Return non-zero for an unknown toolchain.
load_toolchain() {
    local tc=${1:-$DEFAULT_TOOLCHAIN}
    module purge
    case "$tc" in
        <tc1>)
            module load <compiler> <mpi> <hdf5-for-that-compiler-and-mpi> <fftw>
            CXX_CHOICE="g++-simd"
            CFLAG="-march=<arch> -flto=auto"
            ;;
        *)
            echo "load_toolchain: unknown toolchain '$tc' ($TOOLCHAINS)" >&2
            return 1
            ;;
    esac
}
