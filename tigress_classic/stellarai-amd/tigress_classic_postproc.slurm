#!/bin/bash
#SBATCH --job-name=tc-postproc
#SBATCH --account=eost
#SBATCH --partition=cpu
#SBATCH -N 1
#SBATCH --ntasks-per-node=24
#SBATCH --exclusive
#SBATCH --time=04:00:00
#SBATCH --output=tc-postproc-%j.out
#
# Quick-look figures, PDFs and movies of a TIGRESS-classic run with ~/TIGRESS-CR/python/plot_slices.py
# (cr_snapshot, cr_slices, cr_snapshot_prj, cr_acoustic_plot, snapshot, movies/).
#   sbatch tigress_classic_postproc.slurm <rundir>
#   sbatch --ntasks-per-node=8 tigress_classic_postproc.slurm <rundir>   # 4 pc run (memory)
# Needs the pyathena conda env (pyathena from ~/pyathena, plus pip package colormaps).
# pyathena's mpi4py uses the Intel MPI bundled with the conda env, so srun --mpi=pmi2.

RUNDIR=$1
[ -d "$RUNDIR" ] || { echo "ERROR: no run directory $RUNDIR"; exit 1; }
PYSCRIPT=$HOME/TIGRESS-CR/python/plot_slices.py

module purge; module load anaconda3/2024.6
source "$(conda info --base)/etc/profile.d/conda.sh"; conda activate pyathena
export OMP_NUM_THREADS=1 MPLBACKEND=Agg
git -C $HOME/TIGRESS-CR log -1 --format='TIGRESS-CR %h %s'
git -C $HOME/pyathena log -1 --format='pyathena %h %s'
cd "$RUNDIR" || exit 1
date
srun --mpi=pmi2 python -m mpi4py "$PYSCRIPT" "$RUNDIR"
echo "EXITCODE = $?"
date
