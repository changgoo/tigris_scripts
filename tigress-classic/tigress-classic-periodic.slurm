#!/bin/bash
#SBATCH --job-name=tigress    # create a short name for your job
#SBATCH -N 4                 # node count
#SBATCH -n 384               # node count
#SBATCH --time=24:00:00          # total run time limit (HH:MM:SS)
#SBATCH --mail-type=all          # send email on job start, end and fail
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=tigress-%j.err
#SBATCH --error=tigress-%j.out

module purge
module purge; module load anaconda3/2023.3 intel-oneapi/2024.2 intel-mpi/oneapi/2021.13 hdf5/oneapi-2024.2/intel-mpi/1.14.4 fftw/oneapi-2024.2/3.3.10

PID=TIGRESS
SRCDIR=`pwd`
EXE=$SRCDIR/tigress_classic_icpx-b
INPUT=${SRCDIR}/athinput.tigress_classic
RUNDIR=/scratch/gpfs/$USER/tigress-classic/R8_8pc_classic-b-periodic/

TBLDIR="$SRCDIR/../../inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

params="job/problem_id=$PID time/tlim=500 mesh/nx1=128 mesh/nx2=128 mesh/nx3=768 cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL mesh/ix1_bc=periodic mesh/ox1_bc=periodic"
echo $RUNDIR

# Create run directory
if [ -d $RUNDIR ] ; then
    echo "directory exists"
    rm -rd $RUNDIR/*
else
    mkdir -p $RUNDIR
fi

cd $RUNDIR
cp $EXE .
cp $INPUT .
cp $TBLDIR/$COOL_TBL .
cp $TBLDIR/$POPSYNTH_TBL .

echo $params
cat $INPUT

srun $EXE -i $INPUT -t 23:00:00 $params 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"

# make quick snapshots
module purge
module load anaconda3/2022.5 openmpi/gcc/4.1.0
conda activate pyathena-lem

PYTHONDIR=$HOME/pyathena_master
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$PYTHONDIR/pyathena/tigresspp/do_tasks.py
srun python -m mpi4py $pythonscript -b `pwd`
