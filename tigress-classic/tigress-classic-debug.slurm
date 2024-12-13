#!/bin/bash
#SBATCH --job-name=tigress    # create a short name for your job
#SBATCH -N 1                 # node count
#SBATCH -n 48               # node count
#SBATCH --time=00:30:00          # total run time limit (HH:MM:SS)
#SBATCH --output=tigress


CC=g++
if [ "$CC" == "icpx" ] ; then
    module purge; module load anaconda3/2023.3 intel-oneapi/2024.2 intel-mpi/oneapi/2021.13 hdf5/oneapi-2024.2/intel-mpi/1.14.4 fftw/oneapi-2024.2/3.3.10
elif [ "$CC" == "g++" ] ; then
    module purge; module load anaconda3/2020.11 gcc-toolset/10 fftw/gcc/3.3.10 openmpi/gcc/4.1.6 hdf5/gcc/openmpi-4.1.6/1.14.4
else
    CC="none"
    exit
fi

PID=TIGRESS
SRCDIR=`pwd`
EXE=tigress_classic_$CC
INPUT=${SRCDIR}/athinput.tigress_classic
RUNDIR=/scratch/gpfs/$USER/tigress-classic/debug-$CC/

TBLDIR="$SRCDIR/../../inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

params="job/problem_id=$PID cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL output1/dt=0 output1/dcycle=1"
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

srun $EXE -i $INPUT -t 00:20:00 $params 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"

# make quick snapshots
module purge
module load anaconda3/2022.5 openmpi/gcc/4.1.0
conda activate pyathena-lem

PYTHONDIR=$HOME/pyathena_master
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$PYTHONDIR/pyathena/tigresspp/do_tasks.py
srun python $pythonscript -b `pwd`
