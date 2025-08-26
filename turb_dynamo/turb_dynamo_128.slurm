#!/bin/bash
#SBATCH --job-name=dynamo    # create a short name for your job
#SBATCH --account=eost        # account (mandatory for tiger3)
#SBATCH -N 1                  # node count
#SBATCH -n 64                # node count
#SBATCH --time=05:00:00       # total run time limit (HH:MM:SS)
#SBATCH --mail-type=all       # send email on job start, end and fail
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=dynamo-%j.err
#SBATCH --error=dynamo-%j.out

CC=$1
debug_option=""
if [[ "$CC" == "icpx" || "$CC" == "icpx-b" ]]  ; then
    module purge; module load anaconda3/2023.3 intel-oneapi/2024.2 intel-mpi/oneapi/2021.13 hdf5/oneapi-2024.2/intel-mpi/1.14.4 fftw/oneapi-2024.2/3.3.10
elif [[ "$CC" == "g++" || "$CC" == "g++-b" ]] ; then
    module purge; module load anaconda3/2023.3 fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4
else
    module purge; module load anaconda3/2023.3 fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4
    CC=g++
    debug_option="-debug"
fi

STARTFLAG=$2

NX=128
beta=10
PID=DYNAMO
SRCDIR=`pwd`
EXE=turb_${CC}.exe
INPUT=${SRCDIR}/athinput.turb_dynamo
RUNDIR=/scratch/gpfs/EOST/$USER/turb_dynamo/run-$CC-br$beta-N$NX-xorder2-uct-hlld

params="job/problem_id=$PID mesh/nx1=$NX mesh/nx2=$NX mesh/nx3=$NX problem/beta_r=1.e$beta problem/dedt=4 time/tlim=20 hydro/vel_decomp=true time/integrator=rk2 time/xorder=2 hydro/fofc=false hydro/ct_method=uct_hlld"

if [[ "$COOLING" == "true" ]] ; then
    TBLDIR="$SRCDIR/../../inputs/tables"
    COOL_TBL="tigress_coolftn.txt"
    cooling_params="time/ops_task=true cooling/cooling=op_split cooling/coolftn_file=$COOL_TBL hydro/neighbor_flooring=true"
    params="{$params} ${cooling_params}"
fi

echo $RUNDIR

# Create run directory
if [ -d $RUNDIR ] ; then
    echo "directory exists"
    if [[ $STARTFLAG != "-r" ]]; then
        echo "cleaning up"
        rm -rd $RUNDIR/*
    fi
else
    mkdir -p $RUNDIR
fi

cd $RUNDIR

echo $params
# cat $INPUT

set -o pipefail

RSTINPUT=$PID.final.rst
if [ ! -f $RSTINPUT ]; then
    echo "Starting fresh"
    cp ${SRCDIR}/$EXE .
    cp ${SRCDIR}/turb_dynamo_$NX.slurm .
    cp $INPUT .
    if [[ "$COOLING" == "true" ]] ; then
        cp $TBLDIR/$COOL_TBL .
    fi
    srun $EXE -i $INPUT -t 04:50:00 $params 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"
else
    echo "Restarting"
    srun $EXE -r $RSTINPUT -t 04:50:00 1> "$RUNDIR/out.rst.txt" 2> "$RUNDIR/err.rst.txt"
fi

EXITCODE=$?
echo "EXITCODE = $EXITCODE"

set +o pipefail

if [[ $EXITCODE -eq 3 ]]; then
    echo "Resubmitting"
    sbatch turb_dynamo_$NX.slurm $CC -r
fi

# make quick snapshots
# cd $RUNDIR
# module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena

# PYTHONDIR=$HOME/pyathena
# export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
# pythonscript=$PYTHONDIR/pyathena/tigresspp/do_tasks.py
# srun python -m mpi4py $pythonscript -b `pwd`

