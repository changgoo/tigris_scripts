#!/bin/bash
#SBATCH --job-name=ncr8-diag   # short name for the job
#SBATCH --account=eost         # account (mandatory for tiger3; harmless on stellar)
#SBATCH -N 4                   # node count
#SBATCH -n 384                 # task count (= number of meshblocks, 1 block/rank)
#SBATCH --time=00:30:00        # total run time limit (HH:MM:SS)
#SBATCH --output=ncr8diag-%j.out
#SBATCH --error=ncr8diag-%j.err
#
# Short diagnostic segments of the 8 pc MHD TIGRESS-NCR run (floor/fallback
# diagnostics, branch floor-fallback-diagnostics). Restarts a production restart
# file in a separate run directory so the production run is never touched.
# No auto-resubmit, no snapshot plotting.
#
# Usage:
#   sbatch [--time=HH:MM:SS] tigress_ncr_mhd_8pc_diag.slurm TAG RSTFILE TLIM [EXE] [extra overrides...]
#     TAG     : run-directory tag -> /scratch/gpfs/$USER/tigress_ncr/diag/TAG
#     RSTFILE : restart file to start from (symlinked into the run dir)
#     TLIM    : time/tlim override (code time)
#     EXE     : executable name under $SLURMDIR [default: tigris_ncr_mhd-fft-floordiag.exe]
#     extra   : further block/par=value overrides (e.g. problem/floor_diag=true)
#   env ATHENA_WALL : athena -t soft limit, must be < --time [default: 00:25:00]
#   env ADD_INPUT   : input file loaded on top of the restart parameters (-r ... -i FILE);
#                     needed for blocks/parameters absent from the restart, e.g.
#                     <floor_diag>, since command-line overrides cannot add them
#
# Athena writes TIGRESS_NCR.final.rst (~3.7 GB) at the end; it is kept for
# bitwise comparisons between runs and can be deleted afterwards.
#
# Example (phase 0 smoke test, ~200 cycles from t=150):
#   sbatch tigress_ncr_mhd_8pc_diag.slurm p0-restart \
#     /scratch/gpfs/changgoo/tigress_ncr/mhd-ncr-8pc/TIGRESS_NCR.00003.rst 150.1

module purge; module load anaconda3/2023.3 intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10

TAG=$1; RSTFILE=$2; TLIM=$3
EXE=${4:-tigris_ncr_mhd-fft-floordiag.exe}
shift 4 2>/dev/null || shift $#
EXTRA="$*"

if [[ -z "$TAG" || -z "$RSTFILE" || -z "$TLIM" ]]; then
    echo "ERROR: usage: sbatch $0 TAG RSTFILE TLIM [EXE] [overrides...]"; exit 1
fi

prob=tigress_ncr
SRCDIR=$HOME/tigris/.worktrees/floor-fallback-diagnostics  # tables staged from here
SLURMDIR=$HOME/tigris_scripts/$prob/stellar
EXEPATH=$SLURMDIR/$EXE
TBLDIR=$SRCDIR/inputs/tables
RUNDIR=/scratch/gpfs/$USER/tigress_ncr/diag/$TAG

[ -x "$EXEPATH" ] || { echo "ERROR: executable not found: $EXEPATH"; exit 1; }
[ -f "$RSTFILE" ] || { echo "ERROR: restart file not found: $RSTFILE"; exit 1; }
if [ -d "$RUNDIR" ] && [ -n "$(ls -A "$RUNDIR")" ]; then
    echo "ERROR: $RUNDIR exists and is not empty (pick a new TAG)"; exit 1
fi
mkdir -p "$RUNDIR"; cd "$RUNDIR"

cp "$EXEPATH" .
cp "$SLURMDIR/tigress_ncr_mhd_8pc_diag.slurm" .
cp "$TBLDIR/tigress_coolftn_ncr.txt" "$TBLDIR/Z014_GenevaV00.txt" .
ln -s "$RSTFILE" start.rst
INARG=""
if [ -n "$ADD_INPUT" ]; then
    cp "$ADD_INPUT" ./athinput.add
    INARG="-i athinput.add"
fi
git -C "$SRCDIR" log -1 --format='%H %s' > build_commit.txt
git -C "$SRCDIR" status -s >> build_commit.txt

echo "RUNDIR  = $RUNDIR"
echo "EXE     = $EXEPATH"
echo "RSTFILE = $RSTFILE"
echo "params  = time/tlim=$TLIM $EXTRA"
echo "ADD_INPUT = ${ADD_INPUT:-none}"

srun "./$EXE" -r start.rst $INARG -t ${ATHENA_WALL:-00:25:00} time/tlim=$TLIM $EXTRA \
    1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"
echo "EXITCODE = $?"
