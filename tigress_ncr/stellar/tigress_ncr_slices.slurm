#!/bin/bash
#SBATCH --job-name=slices  # short name for the job
#SBATCH --account=eost         # account (mandatory for tiger3; harmless on stellar)
#SBATCH -N 1                   # node count
#SBATCH -n 32                  # task count (= number of meshblocks, 1 block/rank)
#SBATCH --time=00:30:00        # total run time limit (HH:MM:SS)
#SBATCH --output=slices-%j.out
#SBATCH --error=slices-%j.err

RUNBASE=/scratch/gpfs/$USER/tigress_ncr
RUNNAME=${1:-mhd-ncr-8pc}

# make quick snapshots
cd "$RUNBASE/$RUNNAME" || exit 1
module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena

PYTHONDIR=$HOME/pyathena_master
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$HOME/TIGRESS-CR/python/plot_slices_ncr.py
srun python -m mpi4py "$pythonscript" "$(pwd)"
