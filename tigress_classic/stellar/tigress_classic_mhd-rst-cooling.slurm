#!/bin/bash
#SBATCH --job-name=rst-cooling    # create a short name for your job
#SBATCH -N 6                  # node count
#SBATCH -n 512                # node count
#SBATCH --time=00:30:00       # total run time limit (HH:MM:SS)
##SBATCH --mail-type=all       # send email on job start, end and fail
##SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=tigress-%j.err
#SBATCH --error=tigress-%j.out

solver=${1:-rk2}

# Validate boundary condition arguments
valid_solver="rk2 rk4 forward_euler backward_euler crank_nicolson implicit"
[[ ! " $valid_solver " =~ " $solver " ]] && echo "Invalid solver=$solver" && exit 1

CC=icpx
debug_option=""
if [[ "$CC" == "icpx" || "$CC" == "icpx-b" ]]  ; then
    module purge; module load anaconda3/2023.3 intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10
elif [[ "$CC" == "g++" || "$CC" == "g++-b" ]] ; then
    module purge; module load anaconda3/2023.3 fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4
else
    module purge; module load anaconda3/2023.3 fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4
    CC=g++
    debug_option="-debug"
fi

# Define problem and paths
physics=mhd
prob=tigress_classic
PID=TIGRESS
SRCDIR=$HOME/tigris
SCRIPTDIR=$HOME/tigris_scripts/$prob/stellar

# Define executable and input files
EXE=tigris_${physics}.exe
INPUT=athinput.$prob
RUNDIR=/scratch/gpfs/$USER/$prob/${physics}-8pc-cooling-${solver}

# Define table directories and files
TBLDIR="$SRCDIR/inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

# Print the run directory
echo $RUNDIR

# Create run directory if it doesn't exist, or clean it if it does
if [ -d $RUNDIR ] ; then
    echo "directory exists"
    echo "cleaning up"
    rm -rf $RUNDIR/*
else
    mkdir -p $RUNDIR
fi

# Change to the run directory
cd $RUNDIR

# Enable pipefail option for better error handling
set -o pipefail

if [ ! -f "$COOL_TBL" ]; then
    cp -p "$TBLDIR/$COOL_TBL" .
fi
if [ ! -f "$POPSYNTH_TBL" ]; then
    cp -p "$TBLDIR/$POPSYNTH_TBL" .
fi

cp -p ${SCRIPTDIR}/$EXE .

# Define the restart input file
RSTINPUT=../mhd-8pc-b1-mhdbc_diode/TIGRESS.00006.rst

echo "Restart from $RSTINPUT"
srun $EXE -r $RSTINPUT -t 00:30:00 cooling/solver=$solver time/tlim=301 output2/dt=0.1 output3/dt=0.1 output6/dt=0.1 output7/dt=0.1 output1/file_number=0 output5/file_number=0 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"

# make quick snapshots
cd $RUNDIR
module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena

PYTHONDIR=$HOME/pyathena_master
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$HOME/TIGRESS-CR/python/plot_slices.py
srun python -m mpi4py $pythonscript `pwd`
