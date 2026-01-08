#!/bin/bash
#SBATCH --job-name=tigress-dotask    # create a short name for your job
#SBATCH -N 1                 # node count
#SBATCH -n 24                # node count
#SBATCH --time=06:00:00
##SBATCH --mem=2000G
##SBATCH --partition=bigmem
#SBATCH --mail-type=all          # send email on job start, end and fail
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=tigress-dotask-%j.err
#SBATCH --error=tigress-dotask-%j.out

PID=TIGRESS
RUNDIR=/scratch/gpfs/$USER/tigress_classic/$1

cd $RUNDIR

# make quick snapshots
module purge
module load anaconda3/2022.5 openmpi/gcc/4.1.0
conda activate pyathena-lem

# PYTHONDIR=$HOME/pyathena_master
# export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
# pythonscript=$PYTHONDIR/pyathena/tigresspp/do_tasks.py
# srun python -m mpi4py $pythonscript -b `pwd`


cd $RUNDIR
module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena

PYTHONDIR=$HOME/pyathena_master
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$HOME/TIGRESS-CR/python/plot_slices.py
srun python -m mpi4py $pythonscript `pwd`