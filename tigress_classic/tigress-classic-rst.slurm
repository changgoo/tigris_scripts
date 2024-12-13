#!/bin/bash
#SBATCH --job-name=tigress-rst    # create a short name for your job
#SBATCH -N 4                 # node count
#SBATCH -n 384               # node count
#SBATCH --time=00:30:00          # total run time limit (HH:MM:SS)
#SBATCH --mail-type=all          # send email on job start, end and fail
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=tigress-%j.err
#SBATCH --error=tigress-%j.out

module purge
module load anaconda3/2023.3 intel/2024.2 intel-mpi/oneapi/2021.13 hdf5/intel-2021.1/intel-mpi/1.10.6 fftw/intel-2021.1/3.3.9

PID=TIGRESS
SRCDIR=$HOME/tigris/
EXE=$SRCDIR/scripts/tigress-classic/tigress_classic_icpx.exe
RSTDIR=/scratch/gpfs/$USER/tigress-classic/R8_8pc_classic
RSTFILE=TIGRESS.00002.rst
RUNDIR=/scratch/gpfs/$USER/tigress-classic/R8_8pc_rst2

TBLDIR="$SRCDIR/inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

params="job/problem_id=$PID output1/file_number=0 cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL time/tlim=22 output1/dcycle=1 output1/dt=0 output2/dcycle=100 output2/dt=0 output3/dcycle=100 output3/dt=0 output4/dcycle=100 output4/dt=0 output5/dcycle=100 output5/dt=0 time/ncycle_out=1 time/dt_diagnostics=1"
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

srun $EXE -r $RSTDIR/$RSTFILE -t 00:25:00 $params 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"

# make quick snapshots
module purge
module load anaconda3/2022.5 openmpi/gcc/4.1.0
conda activate pyathena-lem

PYTHONDIR=$HOME/pyathena_master
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$PYTHONDIR/pyathena/tigresspp/do_tasks.py
srun python -m mpi4py $pythonscript -b `pwd`
