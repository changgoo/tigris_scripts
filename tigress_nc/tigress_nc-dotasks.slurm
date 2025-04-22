#!/bin/bash
#SBATCH --job-name=ncr-dotask    # create a short name for your job
#SBATCH --account=eost        # account (mandatory for tiger3)
#SBATCH -N 1                  # node count
#SBATCH -n 48                # node count
#SBATCH --time=00:30:00       # total run time limit (HH:MM:SS)
#SBATCH --output=dotask-%j.err
#SBATCH --error=dotask-%j.out

BASEDIR=/scratch/gpfs/$USER/tigress_nc/
RUNDIR=$BASEDIR$1

# make quick snapshots
cd $RUNDIR
module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena

PYTHONDIR=$HOME/pyathena
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$PYTHONDIR/pyathena/tigresspp/plot_slices.py
srun python -m mpi4py $pythonscript `pwd`