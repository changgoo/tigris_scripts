#!/bin/bash
#SBATCH --job-name=crmhd      # create a short name for your job
#SBATCH --account=eost        # account (mandatory for tiger3)
#SBATCH -N 6                  # node count
#SBATCH -n 512                # node count
#SBATCH --time=00:30:00       # total run time limit (HH:MM:SS)
#SBATCH --mail-type=all       # send email on job start, end and fail
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=tigress-%j.err
#SBATCH --error=tigress-%j.out

module purge; module load anaconda3/2023.3 intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10

SRCDIR=$HOME/tigris
SCRIPTDIR=$HOME/tigris_scripts/$prob/stellar

# Define executable and input files
EXE=tigris_crmhd.exe
RSTINPUT=$1
RUNDIR=./

# Define table directories and files
TBLDIR="$SRCDIR/inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

if [ ! -f "$COOL_TBL" ]; then
    cp -p "$TBLDIR/$COOL_TBL" .
fi
if [ ! -f "$POPSYNTH_TBL" ]; then
    cp -p "$TBLDIR/$POPSYNTH_TBL" .
fi

cp -p ${SCRIPTDIR}/$EXE .
srun $EXE -r $RSTINPUT -i athinput.restart 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"
