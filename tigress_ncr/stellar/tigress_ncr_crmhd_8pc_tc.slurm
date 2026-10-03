#!/bin/bash
#SBATCH --job-name=crncr-8pc   # short name for the job
#SBATCH --account=eost
#SBATCH -N 4                   # node count
#SBATCH --ntasks-per-node=96   # 384 ranks = 384 meshblocks (1 block/rank)
#SBATCH --exclusive
#SBATCH --time=24:00:00        # total run time limit (HH:MM:SS)
#SBATCH --mail-type=all
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=crncr8pc-%j.out
#SBATCH --error=crncr8pc-%j.err
#
# 8 pc CRMHD + NCR *coupling* run of the TIGRESS-NCR executable on Stellar
# (4x Intel Xeon Platinum 8268 Cascade Lake, 96 cores/node), built with --physics=crmhd
# (-b --cr=mg --flux=hlld -ncr).
#
# The coupling (both directions) is turned on at runtime by cr/photchem_flag=1:
#   - CR energy density  -> per-cell NCR cosmic-ray ionization rate (xi_cr)
#   - NCR ion/neutral abundances -> CR scattering coefficient (CROpacity)
# It requires <cr>/self_consistent_flag=1 and <photchem>/mode=ncr (both set in
# athinput.tigress_ncr) and the 10-column cooling table of the ncr-cr-coupling branch.
#
# Runs the production input (athinput.tigress_ncr) but overrides the mesh to 8 pc:
#   128x128x768 over the full 1024x1024x6144 pc box, 32^3 blocks
#   -> 4*4*24 = 384 blocks -> 384 ranks (1 block/rank) = 4 full nodes.
#
# Toolchain: built by build_tigress.sh --machine=stellar --cc=<toolchain>; the
# matching modules come from env.sh. The default is DEFAULT_TOOLCHAIN of env.sh, the
# benchmarked best for MHD and CRMHD together (see README.md).
#
# This is the env.sh version of tigress_ncr_crmhd_8pc.slurm (which keeps its fixed icpx +
# Open MPI modules and tigris_ncr_crmhd-fft.exe). Both use the run directory
# $RUNBASE/crmhd-ncr-8pc[TAG], so -r continues a run started by the other script.
#
# Long production run: chains itself via restart when it stops on the walltime
# soft limit (athena exit code 3).
#
# Usage:
#   sbatch tigress_ncr_crmhd_8pc_tc.slurm [-r] [TAG]
#     -r  : restart from $PID.final.rst in the run directory, or, if there is none,
#           from the newest $PID.NNNNN.rst there (e.g. a checkpoint copied from another cluster)
#     TAG : suffix of the run-directory name
#   env CC      : toolchain [default: DEFAULT_TOOLCHAIN of env.sh]
#   env RUNBASE : parent of the run directory [default: /scratch/gpfs/$USER/tigress_ncr]

STARTFLAG=$1
TAG=$2

# Problem definition and paths
physics=crmhd
grav=fft
prob=tigress_ncr
PID=TIGRESS_NCR
SRCDIR=$HOME/tigris/.worktrees/ncr-cr-coupling  # worktree the exe was built from (10-column cooling table)
SCRIPTDIR=$HOME/tigris_scripts/$prob         # holds athinput.$prob
SLURMDIR=$SCRIPTDIR/stellar            # holds the exe, env.sh and this script
SCRIPT=${prob}_${physics}_8pc_tc.slurm

source "$SLURMDIR/env.sh"
CC=${CC:-$DEFAULT_TOOLCHAIN}  # a resubmitted segment keeps the CC of the first one
load_toolchain "$CC" || exit 1

# Executable (under $SLURMDIR) and input file
EXE=tigris_ncr_${physics}-${grav}-${CC}.exe  # e.g. tigris_ncr_crmhd-fft-icpx-impi.exe
EXEPATH=${SLURMDIR}/$EXE
INPUT=${SCRIPTDIR}/athinput.${prob}

# --- 8 pc override: refine the 16 pc input to 8 pc over the SAME box -----------
HIRES="mesh/nx1=128 mesh/nx2=128 mesh/nx3=768"
# ------------------------------------------------------------------------------

# Data tables
TBLDIR="$SRCDIR/inputs/tables"
COOL_TBL="tigress_coolftn_ncr.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

# Informative run-directory name: <physics>-ncr-<res>pc (res from box / override nx1)
mesh_val () {
    grep -E "^[[:space:]]*$1[[:space:]]*=" "$INPUT" | head -1 | sed -E 's/#.*//; s/[^=]*=[[:space:]]*//; s/[[:space:]]*$//'
}
x1min=$(mesh_val x1min); x1max=$(mesh_val x1max)
nx1=$(echo "$HIRES" | grep -oE 'nx1=[0-9]+' | head -1 | cut -d= -f2)
res=$(( (x1max - x1min) / nx1 ))
RUNNAME=${physics}-ncr-${res}pc${TAG}
RUNBASE=${RUNBASE:-/scratch/gpfs/$USER/tigress_ncr}
RUNDIR=$RUNBASE/$RUNNAME

# Runtime parameter overrides (data-table filenames must be relative to RUNDIR).
# cr/photchem_flag=1 turns on the CR<->NCR coupling.
params="job/problem_id=$PID job/output_timing=true $HIRES cr/photchem_flag=1 \
        ray_tracing/rayt_sparse=true ray_tracing/dist_xy_max=2048 ray_tracing/eps_extinct=1.e-8 \
        photchem_ncr/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL"

echo "RUNDIR = $RUNDIR"
echo "EXE    = $EXEPATH"
echo "INPUT  = $INPUT"

if [ ! -x "$EXEPATH" ]; then
    echo "ERROR: executable not found: $EXEPATH"
    echo "       build it with: build_tigress.sh --machine=stellar --cc=$CC --physics=$physics --worktree=ncr-cr-coupling"
    exit 1
fi

# Create/clean the run directory. A fresh start never deletes restart files.
if [ -d "$RUNDIR" ] ; then
    echo "directory exists"
    if [[ $STARTFLAG != "-r" ]]; then
        if compgen -G "$RUNDIR/*.rst" > /dev/null; then
            echo "ERROR: $RUNDIR holds restart files; use -r, or move them away for a fresh start"
            exit 1
        fi
        echo "cleaning up"
        rm -rf "$RUNDIR"/*
    fi
else
    mkdir -p "$RUNDIR"
fi

cd "$RUNDIR"
echo "params = $params"
set -o pipefail

# Stage the executable and tables on every segment so a toolchain change takes effect.
cp "${SLURMDIR}/$SCRIPT" .
cp "$EXEPATH" .
cp "$TBLDIR/$COOL_TBL" .
cp "$TBLDIR/$POPSYNTH_TBL" .

RSTINPUT=$PID.final.rst
if [[ $STARTFLAG == "-r" && ! -f "$RSTINPUT" ]]; then
    RSTINPUT=$(ls -1 $PID.[0-9]*.rst 2>/dev/null | sort | tail -1)
fi

if [[ $STARTFLAG != "-r" ]]; then
    echo "Starting fresh"
    cp "$INPUT" .
    srun --cpu-bind=cores "./$EXE" -i "$(basename "$INPUT")" -t 23:30:00 $params \
        1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"
elif [ -n "$RSTINPUT" ] && [ -f "$RSTINPUT" ]; then
    echo "Restarting from $RSTINPUT"
    rstnum=$(ls out*.txt 2>/dev/null | wc -l)
    # Parameters absent from the restart file (e.g. a new <hydro> switch) cannot be
    # set on the command line; put them in $RESTART_ADD in the run directory.
    RESTART_ADD=athinput.restart_add
    ADDARG=""
    if [ -f "$RESTART_ADD" ]; then
        ADDARG="-i $RESTART_ADD"
        echo "Restart add-on input: $RESTART_ADD"
    fi
    srun --cpu-bind=cores "./$EXE" -r "$RSTINPUT" $ADDARG -t 23:30:00 \
        1> "$RUNDIR/out.r${rstnum}.txt" 2> "$RUNDIR/err.r${rstnum}.txt"
else
    echo "ERROR: -r given but no restart file in $RUNDIR"
    exit 1
fi

EXITCODE=$?
echo "EXITCODE = $EXITCODE"
set +o pipefail

# Athena exits with code 3 when it stops on the walltime soft limit (-t): resubmit.
if [[ $EXITCODE -eq 3 ]]; then
    echo "Resubmitting"
    cd "$SLURMDIR"
    CC=$CC RUNBASE=$RUNBASE sbatch "$SCRIPT" -r "$TAG"
fi

# make quick snapshots (needs the pyathena conda env, which is not set up on this cluster yet)
cd "$RUNDIR"
pythonscript=$HOME/TIGRESS-CR/python/plot_slices_ncr.py
if [ -d "$HOME/.conda/envs/pyathena" ] && [ -f "$pythonscript" ]; then
    module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena
    export PYTHONPATH="$HOME/pyathena_master:$PYTHONPATH"
    srun python -m mpi4py "$pythonscript" "$(pwd)"
else
    echo "Skipping snapshots: pyathena env or $pythonscript not found"
fi
