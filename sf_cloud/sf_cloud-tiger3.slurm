#!/bin/bash
#SBATCH --job-name=sf_cloud    # create a short name for your job
#SBATCH --account=eost        # account (mandatory for tiger3)
#SBATCH -N 5                  # node count
#SBATCH -n 512                # node count
#SBATCH --time=24:00:00       # total run time limit (HH:MM:SS)
#SBATCH --mail-type=all       # send email on job start, end and fail
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=sf_cloud-%j.err
#SBATCH --error=sf_cloud-%j.out

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

PID=TIGRESS
SRCDIR=`pwd`
EXE=sf_cloud_${CC}.exe
INPUT=${SRCDIR}/athinput.sf_cloud
RUNDIR=/scratch/gpfs/EOST/$USER/sf_cloud/run-$CC

TBLDIR="$SRCDIR/../../inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

NX=256
params="job/problem_id=$PID mesh/nx1=$NX mesh/nx2=$NX mesh/nx3=$NX cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL"
periodic="mesh/ix1_bc=periodic mesh/ox1_bc=periodic"
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
    cp $INPUT .
    cp $TBLDIR/$COOL_TBL .
    cp $TBLDIR/$POPSYNTH_TBL .
    srun $EXE -i $INPUT -t 23:30:00 $params 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"
else
    echo "Restarting"
    srun $EXE -r $RSTINPUT -t 23:30:00 1> "$RUNDIR/out.rst.txt" 2> "$RUNDIR/err.rst.txt"
fi

EXITCODE=$?
echo "EXITCODE = $EXITCODE"

set +o pipefail

if [[ $EXITCODE -eq 2 ]]; then
    echo "Resubmitting"
    cd $SRCDIR
    sbatch sf_cloud-tiger3.slurm $CC -r
fi

# make quick snapshots
cd $RUNDIR
module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena

PYTHONDIR=$HOME/pyathena
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$PYTHONDIR/pyathena/tigresspp/do_tasks.py
srun python -m mpi4py $pythonscript -b `pwd`

