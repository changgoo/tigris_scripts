#!/bin/bash
#SBATCH --job-name=tigress-zprof    # create a short name for your job
#SBATCH -N 1                 # node count
#SBATCH -n 24                # node count
#SBATCH --time=06:00:00
##SBATCH --mem=2000G
##SBATCH --partition=bigmem
#SBATCH --exclusive
#SBATCH --mail-type=all          # send email on job start, end and fail
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=tigress-dotask-%j.err
#SBATCH --error=tigress-dotask-%j.out

module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena
PYTHONDIR=$HOME/pyathena_master
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$HOME/TIGRESS-CR/python/process_zprof.py
pythonscript=$HOME/TIGRESS-CR/python/plot_slices.py

BASEDIR="/scratch/gpfs/changgoo/tigress_classic"
BASEDIR="/tigress/changgoo/anvil"
dir_pattern=${1:-*}

for path in $BASEDIR/$dir_pattern; do
    [ -d "$path" ] || continue
    DIR=$(basename "$path")
    echo "Processing directory: $DIR"

    cd $path
    srun python -m mpi4py $pythonscript `pwd`
done

