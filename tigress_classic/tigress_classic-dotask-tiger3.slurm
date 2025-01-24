#!/bin/bash
#SBATCH --job-name=tigress-dotask  # create a short name for your job
#SBATCH --account=eost             # account (mandatory for tiger3)
#SBATCH -N 1                       # node count
#SBATCH -n 112                     # node count
#SBATCH --time=01:00:00            # total run time limit (HH:MM:SS)
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=tigress-dotask.out
#SBATCH --error=tigress-dotask.err

RUNDIR=/scratch/gpfs/EOST/$USER/tigress_classic/$1

cd $RUNDIR

# make quick snapshots
module purge; module load anaconda3/2024.6; conda activate pyathena
module load openmpi/gcc/4.1.6

PYTHONDIR=$HOME/pyathena
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$PYTHONDIR/pyathena/tigresspp/do_tasks.py
srun python -m mpi4py $pythonscript -b `pwd`
