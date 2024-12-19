#!/bin/bash
#SBATCH --job-name=tigress    # create a short name for your job
#SBATCH -N 1                 # node count
#SBATCH -n 48                # node count
#SBATCH --time=00:30:00          # total run time limit (HH:MM:SS)
#SBATCH --mail-type=all          # send email on job start, end and fail
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=tigress-dotask.out
#SBATCH --error=tigress-dotask.err

PID=TIGRESS
RUNDIR=/scratch/gpfs/$USER/tigress_classic/$1

cd $RUNDIR

# make quick snapshots
module purge
module load anaconda3/2022.5 openmpi/gcc/4.1.0
conda activate pyathena-lem

PYTHONDIR=$HOME/pyathena_master
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$PYTHONDIR/pyathena/tigresspp/do_tasks.py
srun python -m mpi4py $pythonscript -b `pwd`
