#!/bin/bash
#SBATCH --job-name=dotask    # create a short name for your job
#SBATCH --account=eost        # account (mandatory for tiger3)
#SBATCH -N 1                  # node count
#SBATCH -n 24                # node count
#SBATCH --exclusive
##SBATCH --mem=128G
#SBATCH --time=01:00:00       # total run time limit (HH:MM:SS)

RUNDIR=/scratch/gpfs/EOST/$USER/tigress_classic/$1

cd $RUNDIR
module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena

PYTHONDIR=$HOME/pyathena
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$PYTHONDIR/pyathena/tigresspp/plot_slices.py
srun python -m mpi4py $pythonscript `pwd`
