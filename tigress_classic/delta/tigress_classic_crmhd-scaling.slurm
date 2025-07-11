#!/bin/bash
#SBATCH --job-name=crmhd-scaling    # create a short name for your job
#SBATCH --exclusive
#SBATCH --mem=0
#SBATCH --partition=cpu     #
#SBATCH --account=bdne-delta-cpu    #
#SBATCH --job-name=crmhd
#SBATCH --time=01:00:00             # hh:mm:ss for the job
#SBATCH --constraint="scratch"
#SBATCH --output=tigress-scaling-%j.err
#SBATCH --error=tigress-scaling-%j.out

usage="Usage: sbatch -N num_nodes -n num_tasks $0 <resolution> <meshblock_resolution>"

module purge; module reset; module load fftw hdf5

# disable cxi
#unset OMPI_MCA_mtl_ofi_provider_include
#export OMPI_MCA_mtl_ofi_provider_exclude=cxi
export FI_CXI_RX_MATCH_MODE=software
SCRATCH=/work/hdd/bdne/$USER

STARTFLAG=-i
MHDBC=diode
CRBC=lngrad_out
beta=1

if [ -z "$1" ]; then
    echo $usage
    res=8pc
else
    res=$1
fi

if [ -z "$2" ]; then
    echo $usage
    mbres=mb64
else
    mbres=$2
fi

echo "submitting a job: $0 $1 $2"

fgas=0.7

# Define problem and paths
physics=crmhd
prob=tigress_classic
PID=TIGRESS
SRCDIR=$HOME/tigris
SCRIPTDIR=$HOME/tigris_scripts/$prob/delta
SCRIPT=${prob}_${physics}-scaling.slurm

# Define executable and input files
EXE=${prob}_${physics}.exe
INPUT=athinput.$prob
RUNDIR=$SCRATCH/${prob}-scaling/${physics}-${res}_${mbres}-b$beta-mhdbc_$MHDBC-crbc_$CRBC-NNODES$SLURM_JOB_NUM_NODES

# Define table directories and files
TBLDIR="$SRCDIR/inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

mb_32="meshblock/nx1=32 meshblock/nx2=32 meshblock/nx3=32"
mb_64="meshblock/nx1=64 meshblock/nx2=64 meshblock/nx3=64"
mb_16="meshblock/nx1=16 meshblock/nx2=16 meshblock/nx3=16"
mb_128="meshblock/nx1=128 meshblock/nx2=128 meshblock/nx3=128"
res_16pc="mesh/nx1=64 mesh/nx2=64 mesh/nx3=512 mesh/x3min=-4096 mesh/x3max=4096"
res_8pc="mesh/nx1=128 mesh/nx2=128 mesh/nx3=1024 mesh/x3min=-4096 mesh/x3max=4096"
res_4pc="mesh/nx1=256 mesh/nx2=256 mesh/nx3=2048 mesh/x3min=-4096 mesh/x3max=4096"
res_2pc="mesh/nx1=512 mesh/nx2=512 mesh/nx3=4096 mesh/x3min=-4096 mesh/x3max=4096"

res_16pc_short="mesh/nx1=64 mesh/nx2=64 mesh/nx3=256 mesh/x3min=-2048 mesh/x3max=2048"
res_8pc_short="mesh/nx1=128 mesh/nx2=128 mesh/nx3=512 mesh/x3min=-2048 mesh/x3max=2048"
res_4pc_short="mesh/nx1=256 mesh/nx2=256 mesh/nx3=1024 mesh/x3min=-2048 mesh/x3max=2048"
res_2pc_short="mesh/nx1=512 mesh/nx2=512 mesh/nx3=2048 mesh/x3min=-2048 mesh/x3max=2048"

res_16pc_tall="mesh/nx1=64 mesh/nx2=64 mesh/nx3=1024 mesh/x3min=-8192 mesh/x3max=8192"
res_8pc_tall="mesh/nx1=128 mesh/nx2=128 mesh/nx3=2048 mesh/x3min=-8192 mesh/x3max=8192"
res_4pc_tall="mesh/nx1=256 mesh/nx2=256 mesh/nx3=4096 mesh/x3min=-8192 mesh/x3max=8192"
res_2pc_tall="mesh/nx1=512 mesh/nx2=512 mesh/nx3=8192 mesh/x3min=-8192 mesh/x3max=8192"

if [[ $res == "8pc" ]] ; then
    mesh=$res_8pc
elif [[ $res == "4pc" ]] ; then
    mesh=$res_4pc
elif [[ $res == "2pc" ]] ; then
    mesh=$res_2pc
elif [[ $res == "16pc" ]] ; then
    mesh=$res_16pc
elif [[ $res == "8pc_short" ]] ; then
    mesh=$res_8pc_short
elif [[ $res == "4pc_short" ]] ; then
    mesh=$res_4pc_short
elif [[ $res == "2pc_short" ]] ; then
    mesh=$res_2pc_short
elif [[ $res == "16pc_short" ]] ; then
    mesh=$res_16pc_short
elif [[ $res == "8pc_tall" ]] ; then
    mesh=$res_8pc_tall
elif [[ $res == "4pc_tall" ]] ; then
    mesh=$res_4pc_tall
elif [[ $res == "2pc_tall" ]] ; then
    mesh=$res_2pc_tall
elif [[ $res == "16pc_tall" ]] ; then
    mesh=$res_16pc_tall
else
    echo "Invalid resolution: $res"
    exit 1
fi

if [[ $mbres == "mb32" ]] ; then
    meshblock=$mb_32
elif [[ $mbres == "mb64" ]] ; then
    meshblock=$mb_64
elif [[ $mbres == "mb16" ]] ; then
    meshblock=$mb_16
elif [[ $mbres == "mb128" ]] ; then
    meshblock=$mb_128
else
    echo "Invalid meshblock resolution: $mbres"
    exit 1
fi

params="job/problem_id=$PID time/tlim=500 $mesh $meshblock cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL orbital_advection/Omega0=0.0"
periodic="mesh/ix1_bc=periodic mesh/ox1_bc=periodic"
extra_params="perturbation/rseed=1 particle1/fgas=$fgas particle1/r_return=100 gravity/solve_grav_hyperbolic_dt=true cr/sigma=1.e-25 cr/self_consistent_flag=1 hydro/dfloor=1.e-6 hydro/pfloor=1.e-6 mesh/mhd_outflow_bc=$MHDBC mesh/cr_outflow_bc=$CRBC output2/dt=5 output3/dt=5 $periodic"
extra_params2="problem/beta0=$beta time/ncycle_out_timing=1 time/ncycle_out=1"

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
    srun --distribution=cyclic $EXE -i $INPUT -t 00:30:00 $params $extra_params $extra_params2 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"
else
    echo "Restarting"
    rstnum=`ls out.*.txt | wc -l`
    srun $EXE -r $RSTINPUT -t 47:30:00 1> "$RUNDIR/out.r${rstnum}.txt" 2> "$RUNDIR/err.r${rstnum}.txt"
fi

EXITCODE=$?
echo "EXITCODE = $EXITCODE"

set +o pipefail

# if [[ $EXITCODE -eq 2 ]]; then
#     echo "Resubmitting"
#     sbatch $SCRIPT $CC -r $MHDBC $CRBC $beta
# fi

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
