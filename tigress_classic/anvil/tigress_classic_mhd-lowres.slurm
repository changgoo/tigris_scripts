#!/bin/bash
#SBATCH --job-name=mhd-16pc    # create a short name for your job
#SBATCH -A phy240043
#SBATCH -p debug
#SBATCH -N 2
#SBATCH -n 256
#SBATCH --time=02:00:00       # total run time limit (HH:MM:SS)
#SBATCH --mail-type=all       # send email on job start, end and fail
#SBATCH --mail-user=changgookim@gmail.com
#SBATCH --output=tigress-%j.err
#SBATCH --error=tigress-%j.out

module purge; module load gcc; module load openmpi; module load fftw hdf5

# check if the second argument is provided
usage="Usage: $0 <start_flag=-r or -i> <b0=1> <RSTNUM=final> <MHDBC=diode>"

STARTFLAG=${1:-}
b0=${2:-1}
RSTNUM=${3:-final}
MHDBC=${4:-diode}

# Validate required arguments
valid_flag="-i -r"
[[ -z "$STARTFLAG" || ! $valid_flag =~ $STARTFLAG ]] && echo "$usage" && exit 1

# Validate boundary condition arguments
valid_bc="diode lngrad lngrad_out lingrad lingrad_out"
[[ ! " $valid_bc " =~ " $MHDBC " ]] && echo "Invalid MHDBC=$MHDBC" && exit 1

echo "submitting a job: $0 $STARTFLAG $b0 $MHDBC"

fgas=0.9
CRIR=3.e-17

# Define problem and paths
physics=mhd
prob=tigress_classic
PID=TIGRESS
SRCDIR=$HOME/tigris
SCRIPTDIR=$HOME/tigris_scripts/$prob/anvil
SCRIPT=${prob}_${physics}-lowres.slurm

# Define executable and input files
EXE=tigris_${physics}.exe
INPUT=athinput.$prob
RUNDIR=$SCRATCH/$prob/${physics}-16pc-b$b0-mhdbc_$MHDBC-shear
#-CRIR$CRIR

# Define table directories and files
TBLDIR="$SRCDIR/inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

lres_normal="mesh/nx1=64 mesh/nx2=64 mesh/nx3=512 mesh/x3min=-4096 mesh/x3max=4096 meshblock/nx1=16 meshblock/nx2=16 meshblock/nx3=32"

params="job/problem_id=$PID time/tlim=500 $lres_normal cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL"
periodic="orbital_advection/Omega0=0.0 mesh/ix1_bc=periodic mesh/ox1_bc=periodic"
extra_params="perturbation/rseed=1 particle1/fgas=$fgas mesh/mhd_outflow_bc=$MHDBC problem/beta0=$b0"
rst_params="output1/file_number=0 output5/file_number=0"

# Print the run directory
echo $RUNDIR

# Create run directory if it doesn't exist, or clean it if it does
if [ -d $RUNDIR ] ; then
    echo "directory exists"
    if [[ $STARTFLAG != "-r" ]]; then
        echo "cleaning up"
        rm -rf $RUNDIR/*
    fi
else
    mkdir -p $RUNDIR
fi

# Change to the run directory
cd $RUNDIR

# Print the parameters
echo $params $extra_params

# Enable pipefail option for better error handling
set -o pipefail

if [ ! -f "$EXE" ]; then
    cp -p ${SCRIPTDIR}/$EXE .
fi
if [ ! -f "$COOL_TBL" ]; then
    cp -p "$TBLDIR/$COOL_TBL" .
fi
if [ ! -f "$POPSYNTH_TBL" ]; then
    cp -p "$TBLDIR/$POPSYNTH_TBL" .
fi

# Define the restart input file
RSTINPUT=$PID.$RSTNUM.rst
if [[ ! -f "$RSTINPUT" && "$STARTFLAG" == "-i" ]]; then
    echo "Starting fresh"
    cp -p $0 ./$SCRIPT
    cp -p ${SCRIPTDIR}/../$INPUT .
    srun $EXE -i $INPUT -t 1:30:00 $params $extra_params 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"
else
    echo "Restarting from $RSTINPUT"
    rstnum=`ls out.*.txt | wc -l`
    if [[ $RSTNUM == "final" ]]; then
        srun $EXE -r $RSTINPUT -t 1:30:00 1> "$RUNDIR/out.r${rstnum}.txt" 2> "$RUNDIR/err.r${rstnum}.txt"
    else
        srun $EXE -r $RSTINPUT -t 1:30:00 $rst_params 1> "$RUNDIR/out.r${rstnum}.txt" 2> "$RUNDIR/err.r${rstnum}.txt"
    fi
fi

EXITCODE=$?
echo "EXITCODE = $EXITCODE"

set +o pipefail

if [[ $EXITCODE -eq 3 ]]; then
    echo "Resubmitting"
    sbatch $SCRIPT -r $b0 final $MHDBC
fi

# make quick snapshots
cd $RUNDIR
module purge; module load anaconda openmpi; conda activate pyathena

PYTHONDIR=$HOME/pyathena
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$HOME/TIGRESS-CR/python/plot_slices.py
srun python -m mpi4py $pythonscript `pwd`
