#!/bin/bash
#SBATCH --job-name=sf_cloud-dotask  # create a short name for your job
#SBATCH --account=eost             # account (mandatory for tiger3)
#SBATCH -N 1                       # node count
#SBATCH -n 25                     # node count
#SBATCH --time=01:00:00            # total run time limit (HH:MM:SS)
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=sf_cloud-dotask.out
#SBATCH --error=sf_cloud-dotask.err

RUNDIR=/scratch/gpfs/EOST/$USER/sf_cloud/$1

cd $RUNDIR

# make quick snapshots
module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena

PYTHONDIR=$HOME/pyathena
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$PYTHONDIR/pyathena/tigris_sfcloud/do_tasks.py
srun python -m mpi4py $pythonscript -b `pwd`
