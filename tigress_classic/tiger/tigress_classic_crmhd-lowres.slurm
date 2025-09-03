#!/bin/bash
#SBATCH --job-name=lowres-crmhd    # create a short name for your job
#SBATCH --account=eost        # account (mandatory for tiger3)
#SBATCH -N 5                  # node count
#SBATCH -n 512                # node count
#SBATCH --time=24:00:00       # total run time limit (HH:MM:SS)
#SBATCH --mail-type=all       # send email on job start, end and fail
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=tigress-%j.err
#SBATCH --error=tigress-%j.out

# check if the second argument is provided
usage="Usage: $0 <start_flag> <physics> <MHDBC=diode> <CRBC=lngrad_out> <beta>"

STARTFLAG=${1:-}
physics=${2:-crmhd_duale}
MHDBC=${3:-diode}
CRBC=${4:-lngrad_out}
beta=${5:-1}
CC=icpx

# Validate required arguments
[[ -z "$STARTFLAG" ]] && echo "$usage" && exit 1

# Validate boundary condition arguments
valid_bc="diode lngrad lngrad_out lingrad lingrad_out"
[[ ! " $valid_bc " =~ " $MHDBC " ]] && echo "Invalid MHDBC=$MHDBC" && exit 1
[[ ! " $valid_bc " =~ " $CRBC " ]] && echo "Invalid CRBC=$CRBC" && exit 1

# Load modules based on compiler
if [[ "$CC" == icpx* ]]; then
    module purge; module load anaconda3/2023.3 intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10
elif [[ "$CC" == g++* ]]; then
    module purge; module load anaconda3/2023.3 fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4
else
    module purge; module load anaconda3/2023.3 fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4
    debug_option="-debug"
fi

# Set gravity solve flag based on CR subcycle
selfg_dt=$([[ "$crsubcycle" == "true" ]] && echo false || echo true)

echo "submitting a job: $0 $STARTFLAG $physics $MHDBC $CRBC $beta"

fgas=0.7

# Define problem and paths
prob=tigress_classic
PID=TIGRESS
SRCDIR=$HOME/tigris
SCRIPTDIR=$HOME/tigris_scripts/$prob/tiger
SCRIPT=tigress_classic_crmhd-lowres.slurm

# Define executable and input files
EXE=tigris_${physics}.exe
INPUT=athinput.$prob
RUNDIR=/scratch/gpfs/EOST/$USER/$prob/${physics}-16pc-b$beta-mhdbc_$MHDBC-crbc_$CRBC

# Define table directories and files
TBLDIR="$SRCDIR/inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

lowres_normal="meshblock/nx1=16 meshblock/nx2=16 meshblock/nx3=16 mesh/nx3=512 mesh/x3min=-4096 mesh/x3max=4096"

params="job/problem_id=$PID time/tlim=500 $lowres_normal cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL orbital_advection/Omega0=0.0"
periodic="mesh/ix1_bc=periodic mesh/ox1_bc=periodic"
extra_params="perturbation/rseed=1 particle1/fgas=$fgas particle1/r_return=100 gravity/solve_grav_hyperbolic_dt=true cr/sigma=1.e-25 cr/self_consistent_flag=1 hydro/dfloor=1.e-6 hydro/pfloor=1.e-6 mesh/mhd_outflow_bc=$MHDBC mesh/cr_outflow_bc=$CRBC $periodic  problem/beta0=$beta"

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

# Define the restart input file
RSTINPUT=$PID.final.rst
if [ ! -f $RSTINPUT ]; then
    echo "Starting fresh"
    cp $0 ./$SCRIPT
    cp ${SCRIPTDIR}/$EXE .
    cp ${SCRIPTDIR}/../$INPUT .
    cp $TBLDIR/$COOL_TBL .
    cp $TBLDIR/$POPSYNTH_TBL .
    srun $EXE -i $INPUT -t 23:30:00 $params $extra_params 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"
else
    echo "Restarting"
    rstnum=`ls out.*.txt | wc -l`
    srun $EXE -r $RSTINPUT -t 23:30:00 1> "$RUNDIR/out.r${rstnum}.txt" 2> "$RUNDIR/err.r${rstnum}.txt"
fi

EXITCODE=$?
echo "EXITCODE = $EXITCODE"

set +o pipefail

if [[ $EXITCODE -eq 3 ]]; then
    echo "Resubmitting"
    sbatch $SCRIPT -r $physics $MHDBC $CRBC $beta
fi

# make quick snapshots
# cd $RUNDIR
# module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena-lem

# PYTHONDIR=$HOME/pyathena_master
# export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
# pythonscript=$PYTHONDIR/pyathena/tigresspp/do_tasks.py
# srun python -m mpi4py $pythonscript -b `pwd`

cd $RUNDIR
module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena

PYTHONDIR=$HOME/pyathena
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$PYTHONDIR/pyathena/tigresspp/plot_slices.py
srun python -m mpi4py $pythonscript `pwd`
