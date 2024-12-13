#!/bin/bash
#SBATCH --job-name=sf_cloud    # create a short name for your job
#SBATCH --account=eost        # account (mandatory for tiger3)
#SBATCH -N 1                  # node count
#SBATCH -n 64                 # node count
##SBATCH -N 4                  # node count
##SBATCH -n 384                # node count
#SBATCH --time=01:00:00       # total run time limit (HH:MM:SS)
#SBATCH --output=sf_cloud-debug

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

PID=SFCLOUD
SRCDIR=`pwd`
EXE=sf_cloud_${CC}$debug_option
INPUT=${SRCDIR}/athinput.sf_cloud
RUNDIR=/scratch/gpfs/EOST/$USER/sf_cloud/debug-$CC

TBLDIR="$SRCDIR/../../inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

params="job/problem_id=$PID mesh/nx1=128 mesh/nx2=128 mesh/nx3=128 cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL output1/dt=0 output1/dcycle=1"
echo $RUNDIR

# Create run directory
if [ -d $RUNDIR ] ; then
    echo "directory exists"
    rm -rd $RUNDIR/*
else
    mkdir -p $RUNDIR
fi

cd $RUNDIR
cp $SRCDIR/$EXE .
cp $INPUT .
cp $TBLDIR/$COOL_TBL .
cp $TBLDIR/$POPSYNTH_TBL .

echo $params
# cat $INPUT

srun $EXE -i $INPUT -t 00:55:00 $params 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"

# make quick snapshots
cd $RUNDIR
module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena

PYTHONDIR=$HOME/pyathena
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$PYTHONDIR/pyathena/tigresspp/do_tasks.py
srun python -m mpi4py $pythonscript -b `pwd`
