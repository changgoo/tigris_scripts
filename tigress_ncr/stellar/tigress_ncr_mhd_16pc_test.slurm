#!/bin/bash
#SBATCH --job-name=mhd-ncr    # short name for the job
#SBATCH --account=eost        # account (mandatory for tiger3; harmless on stellar)
#SBATCH -N 1                  # node count
#SBATCH -n 32                 # task count (= number of meshblocks, 1 block/rank)
#SBATCH --time=24:00:00       # total run time limit (HH:MM:SS)
##SBATCH --mail-type=all
##SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=ncr-%j.out
#SBATCH --error=ncr-%j.err
#
# Run the TIGRESS-NCR (MHD) executable built by build_tigress.sh.
#
# Task/rank count MUST equal the number of meshblocks (1 block/rank, no AMR):
#   athinput.tigress_ncr_test  : 64x64x256, 32^3 blocks -> 2*2*8  = 32 blocks -> -n 32 (-N 1)
#   athinput.tigress_ncr       : 64x64x384, 32^3 blocks -> 2*2*12 = 48 blocks -> -n 48 (-N 1)
# If you switch INPUT below, update -n (and -N) above to match.
#
# Usage:
#   sbatch tigress_ncr_mhd.slurm [CC] [-r]
#     CC : icpx (default) or g++   -- selects the module set (must match the build)
#     -r : restart from PID.final.rst instead of a fresh start

CC=${1:-icpx}
debug_option=""
if [[ "$CC" == "icpx" || "$CC" == "icpx-b" ]] ; then
    module purge; module load anaconda3/2023.3 intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10
elif [[ "$CC" == "g++" || "$CC" == "g++-b" ]] ; then
    module purge; module load anaconda3/2023.3 fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4
else
    module purge; module load anaconda3/2023.3 intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10
    CC=icpx
fi

STARTFLAG=$2

# Problem definition and paths
physics=mhd
grav=fft
prob=tigress_ncr
PID=TIGRESS_NCR
SRCDIR=$HOME/tigris/.worktrees/tigress-ncr   # worktree the exe was built from
SCRIPTDIR=$HOME/tigris_scripts/$prob
SCRIPT=${prob}_${physics}.slurm

# Executable (produced by build_tigris.sh under $SCRIPTDIR/stellar/) and input file
EXE=tigris_ncr_${physics}-${grav}.exe        # e.g. tigris_ncr_mhd-fft.exe
EXEPATH=${SCRIPTDIR}/stellar/$EXE
INPUT=${SCRIPTDIR}/athinput.${prob}

# --- Test box: shorten the vertical extent so the run fits on 32 ranks -------
# The input is the full production box: 64x64x384 (6144 pc tall) -> 2*2*12 = 48
# blocks. TESTBOX overrides it to 64x64x256 (4096 pc tall) -> 2*2*8 = 32 blocks
# -> 32 ranks, matching the -N 1 -n 32 SBATCH header above.
# For the FULL production box: set TESTBOX="" and TAG="", and use -N 1 -n 48.
TESTBOX="mesh/nx3=256 mesh/x3min=-2048 mesh/x3max=2048"
TAG="-test"
# ----------------------------------------------------------------------------

# Data tables
TBLDIR="$SRCDIR/inputs/tables"
COOL_TBL="tigress_coolftn_ncr.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

# Build an informative run-directory name: <physics>-ncr-<res>pc[<TAG>]
# (resolution is read from the input's <mesh> block so the name matches the run.)
mesh_val () {  # first match wins: the <mesh> block precedes <meshblock>
    grep -E "^[[:space:]]*$1[[:space:]]*=" "$INPUT" | head -1 | sed -E 's/#.*//; s/[^=]*=[[:space:]]*//; s/[[:space:]]*$//'
}
nx1=$(mesh_val nx1)
x1min=$(mesh_val x1min); x1max=$(mesh_val x1max)
res=$(( (x1max - x1min) / nx1 ))
RUNNAME=${physics}-ncr-${res}pc${TAG}

# Target run directory (informative subfolder under the requested base)
RUNDIR=/scratch/gpfs/$USER/tigress_ncr/$RUNNAME

# Runtime parameter overrides (data-table filenames must be relative to RUNDIR).
# output_timing=true turns on per-task timing output (every <time>/ncycle_out_timing cycles).
params="job/problem_id=$PID job/output_timing=true $TESTBOX \
        photchem_ncr/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL"

echo "RUNDIR = $RUNDIR"
echo "EXE    = $EXEPATH"
echo "INPUT  = $INPUT"

if [ ! -x "$EXEPATH" ]; then
    echo "ERROR: executable not found: $EXEPATH (build it first with build_tigress.sh)"
    exit 1
fi

# Create/clean the run directory
if [ -d "$RUNDIR" ] ; then
    echo "directory exists"
    if [[ $STARTFLAG != "-r" ]]; then
        echo "cleaning up"
        rm -rf "$RUNDIR"/*
    fi
else
    mkdir -p "$RUNDIR"
fi

cd "$RUNDIR"
echo "params = $params"
set -o pipefail

RSTINPUT=$PID.final.rst
if [ ! -f "$RSTINPUT" ]; then
    echo "Starting fresh"
    cp "${SCRIPTDIR}/$SCRIPT" .
    cp "$EXEPATH" .
    cp "$INPUT" .
    cp "$TBLDIR/$COOL_TBL" .
    cp "$TBLDIR/$POPSYNTH_TBL" .
    srun "./$EXE" -i "$(basename "$INPUT")" -t 23:30:00 $params \
        1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"
else
    echo "Restarting"
    rstnum=$(ls out.*.txt 2>/dev/null | wc -l)
    srun "./$EXE" -r "$RSTINPUT" -t 23:30:00 \
        1> "$RUNDIR/out.r${rstnum}.txt" 2> "$RUNDIR/err.r${rstnum}.txt"
fi

EXITCODE=$?
echo "EXITCODE = $EXITCODE"
set +o pipefail

# Athena exits with code 3 when it stops on the walltime soft limit (-t): resubmit to continue.
#if [[ $EXITCODE -eq 3 ]]; then
#    echo "Resubmitting"
#    cd "$SCRIPTDIR"
#    sbatch "$SCRIPT" "$CC" -r
#fi

# Optional post-processing (pyathena) -- enable if your environment is set up:
# cd "$RUNDIR"
# module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena
# srun python -m mpi4py $HOME/pyathena/pyathena/tigresspp/plot_slices.py "$(pwd)"
