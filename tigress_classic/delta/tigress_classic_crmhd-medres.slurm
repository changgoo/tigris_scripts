#!/bin/bash
#SBATCH --nodes=8
#SBATCH --ntasks-per-node=64
#SBATCH --exclusive
#SBATCH --partition=cpu          # <- or one of: gpuA100x4 gpuA40x4 gpuA100x8 gpuMI100x8
#SBATCH --account=bdne-delta-cpu # <- match to a "Project" returned by the "accounts"
#SBATCH --job-name=crmhd
#SBATCH --time=24:00:00      # hh:mm:ss for the job
#SBATCH --constraint="scratch"
#SBATCH --mail-type=all       # send email on job start, end and fail
#SBATCH --mail-user=changgookim@gmail.com
#SBATCH --output=tigress-%j.err
#SBATCH --error=tigress-%j.out

module purge; module reset; module load fftw hdf5

# disable cxi
#unset OMPI_MCA_mtl_ofi_provider_include
#export OMPI_MCA_mtl_ofi_provider_exclude=cxi
export FI_CXI_RX_MATCH_MODE=software
SCRATCH=/work/hdd/bdne/$USER

usage="Usage: $0 <start_flag> <MHDBC=diode> <CRBC=lngrad_out> <beta=1>"
# check if the second argument is provided
if [ -z "$1" ]; then
    echo $usage
    exit 1
fi
STARTFLAG=$1


# check if the third argument is provided
if [ -z "$2" ]; then
    echo $usage
    MHDBC=diode
else
    MHDBC=$2
fi

# check if the third argument is a valid value
if [[ "$MHDBC" != "diode" && "$MHDBC" != "lngrad" && "$MHDBC" != "lngrad_out" && "$MHDBC" != "lingrad" && "$MHDBC" != "lingrad_out" ]]; then
    echo "Invalid value for MHDBC=$MHDBC"
    exit 1
fi

# check if the fourth argument is provided
if [ -z "$3" ]; then
    echo $usage
    CRBC=lngrad_out
else
    CRBC=$3
fi

# check if the third argument is a valid value
if [[ "$CRBC" != "diode" && "$CRBC" != "lngrad" && "$CRBC" != "lngrad_out" && "$CRBC" != "lingrad" && "$CRBC" != "lingrad_out" ]]; then
    echo "Invalid value for crbc=$CRBC"
    exit 1
fi


# check if the fifth argument is provided
if [ -z "$4" ]; then
    echo $usage
    beta=1
else
    beta=$4
fi

echo "submitting a job: $0 $1 $2 $MHDBC $CRBC $beta"

fgas=0.7

# Define problem and paths
physics=crmhd
prob=tigress_classic
PID=TIGRESS
SRCDIR=$HOME/tigris
SCRIPTDIR=$HOME/tigris_scripts/$prob/delta
SCRIPT=${prob}_${physics}-lowres.slurm

# Define executable and input files
EXE=${prob}_${physics}.exe
INPUT=athinput.$prob
RUNDIR=$SCRATCH/$prob/${physics}-8pc-b$beta-mhdbc_$MHDBC-crbc_${CRBC}

# Define table directories and files
TBLDIR="$SRCDIR/inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

lowres_bigbox="mesh/nx1=128 mesh/nx2=128 mesh/nx3=768 mesh/x1min=-1024 mesh/x1max=1024 mesh/x2min=-1024 mesh/x2max=1024 mesh/x3min=-6144 mesh/x3max=6144"
lowres_tallbox="mesh/nx3=1024 mesh/x3min=-8192 mesh/x3max=8192 meshblock/nx1=16 meshblock/nx2=16"
lowres_normal="meshblock/nx1=16 meshblock/nx2=16 meshblock/nx3=16 mesh/nx3=512 mesh/x3min=-4096 mesh/x3max=4096"
# lowres_normal="meshblock/nx1=16 meshblock/nx2=16 meshblock/nx3=16"

medres_normal="mesh/nx1=128 mesh/nx2=128 mesh/nx3=1024 mesh/x3min=-4096 mesh/x3max=4096"

params="job/problem_id=$PID time/tlim=500 $medres_normal cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL orbital_advection/Omega0=0.0"
periodic="mesh/ix1_bc=periodic mesh/ox1_bc=periodic"
extra_params="perturbation/rseed=1 particle1/fgas=$fgas particle1/r_return=100 gravity/solve_grav_hyperbolic_dt=true cr/sigma=1.e-25 cr/self_consistent_flag=1 hydro/dfloor=1.e-6 hydro/pfloor=1.e-6 mesh/mhd_outflow_bc=$MHDBC mesh/cr_outflow_bc=$CRBC output2/dt=5 output3/dt=5 $periodic"
extra_params2="problem/beta0=$beta"

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
echo $params $extra_params $extra_params2

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
    srun $EXE -i $INPUT -t 23:30:00 $params $extra_params $extra_params2 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"
else
    echo "Restarting"
    rstnum=`ls out.*.txt | wc -l`
    srun $EXE -r $RSTINPUT -t 23:30:00 1> "$RUNDIR/out.r${rstnum}.txt" 2> "$RUNDIR/err.r${rstnum}.txt"
fi

EXITCODE=$?
echo "EXITCODE = $EXITCODE"

set +o pipefail

if [[ $EXITCODE -eq 2 ]]; then
    echo "Resubmitting"
    sbatch $SCRIPT -r $MHDBC $CRBC $beta
fi

# make quick snapshots
# cd $RUNDIR
# module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena-lem

# PYTHONDIR=$HOME/pyathena_master
# export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
# pythonscript=$PYTHONDIR/pyathena/tigresspp/do_tasks.py
# srun python -m mpi4py $pythonscript -b `pwd`

# cd $RUNDIR
# module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena

# PYTHONDIR=$HOME/pyathena
# export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
# pythonscript=$PYTHONDIR/pyathena/tigresspp/plot_slices.py
# srun python -m mpi4py $pythonscript `pwd`
