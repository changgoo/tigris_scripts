#!/bin/bash
#SBATCH --job-name=crncr-8pc  # short name for the job
#SBATCH --account=eost         # account (mandatory for tiger3; harmless on stellar)
#SBATCH -N 4                   # node count
#SBATCH -n 384                 # task count (= number of meshblocks, 1 block/rank)
#SBATCH --time=24:00:00        # total run time limit (HH:MM:SS)
##SBATCH --mail-type=all
##SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=crncr8pc-%j.out
#SBATCH --error=crncr8pc-%j.err
#
# 8 pc CRMHD + NCR *coupling* run of the TIGRESS-NCR executable built by
# build_tigress.sh --physics=crmhd (i.e. -b --cr=mg --flux=hlld -ncr).
#
# The coupling (both directions) is turned on at runtime by cr/photchem_flag=1:
#   - CR energy density  -> per-cell NCR cosmic-ray ionization rate (xi_cr)
#   - NCR ion/neutral abundances -> CR scattering coefficient (CROpacity)
# It requires <cr>/self_consistent_flag=1 and <photchem>/mode=ncr (both set in
# athinput.tigress_ncr) and the 10-column cooling table shipped on the
# ncr-cr-coupling branch (staged from SRCDIR below; the old 6-column table
# makes NCRCoolFtnTable abort).
#
# Runs the production input (athinput.tigress_ncr) but overrides the mesh to 8 pc:
#   128x128x768 over the full 1024x1024x6144 pc box, 32^3 blocks
#   -> 4*4*24 = 384 blocks -> 384 ranks (1 block/rank), matching -N 4 -n 384.
#
# Long production run: chains itself via restart when it stops on the walltime
# soft limit (athena exit code 3).
#
# Usage:
#   sbatch tigress_ncr_crmhd_8pc.slurm [CC] [-r]
#     CC : icpx (default) or g++   -- module set (must match the build)
#     -r : restart from PID.final.rst instead of a fresh start

CC=${1:-icpx}
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
physics=crmhd
grav=fft
prob=tigress_ncr
PID=TIGRESS_NCR
SRCDIR=$HOME/tigris/.worktrees/ncr-cr-coupling  # worktree the exe was built from
SCRIPTDIR=$HOME/tigris_scripts/$prob            # holds athinput.$prob
SLURMDIR=$SCRIPTDIR/stellar                     # holds the exe and this script
SCRIPT=${prob}_${physics}_8pc.slurm

# Executable (under $SLURMDIR) and input file
EXE=tigris_ncr_${physics}-${grav}.exe           # e.g. tigris_ncr_crmhd-fft.exe
EXEPATH=${SLURMDIR}/$EXE
INPUT=${SCRIPTDIR}/athinput.${prob}

# --- 8 pc override: refine the 16 pc input to 8 pc over the SAME box -----------
# Box is unchanged (1024 x 1024 x 6144 pc from the input); only the cell count.
# 128x128x768 with 32^3 blocks -> 4*4*24 = 384 blocks -> -N 4 -n 384.
HIRES="mesh/nx1=128 mesh/nx2=128 mesh/nx3=768"
TAG=""                                        # production; no extra label
# ------------------------------------------------------------------------------

# Data tables (staged from the coupling worktree: 10-column cooling table).
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
RUNDIR=/scratch/gpfs/$USER/tigress_ncr/$RUNNAME

# Runtime parameter overrides (data-table filenames must be relative to RUNDIR).
# cr/photchem_flag=1 turns on the CR<->NCR coupling; ray_tracing/rayt_sparse=true
# solves ray tracing on the warm/cold hyperbolic cadence (dt_hyperbolic_wc).
# Production ray-tracing reach: dist_xy_max=2048, eps_extinct=1e-8.
params="job/problem_id=$PID job/output_timing=true $HIRES cr/photchem_flag=1 \
        ray_tracing/rayt_sparse=true ray_tracing/dist_xy_max=2048 ray_tracing/eps_extinct=1.e-8 \
        photchem_ncr/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL"

echo "RUNDIR = $RUNDIR"
echo "EXE    = $EXEPATH"
echo "INPUT  = $INPUT"

if [ ! -x "$EXEPATH" ]; then
    echo "ERROR: executable not found: $EXEPATH (build it first with build_tigress.sh --physics=crmhd)"
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
    cp "${SLURMDIR}/$SCRIPT" .
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

# Athena exits with code 3 when it stops on the walltime soft limit (-t): resubmit.
if [[ $EXITCODE -eq 3 ]]; then
    echo "Resubmitting"
    cd "$SLURMDIR"
    sbatch "$SCRIPT" "$CC" -r
fi

# make quick snapshots
cd $RUNDIR
module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena

PYTHONDIR=$HOME/pyathena_master
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$HOME/TIGRESS-CR/python/plot_slices_ncr.py
srun python -m mpi4py $pythonscript `pwd`
