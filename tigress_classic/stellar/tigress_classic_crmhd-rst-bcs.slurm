#!/bin/bash
#SBATCH --job-name=crmhd_bc    # create a short name for your job
#SBATCH --account=eost        # account (mandatory for tiger3)
#SBATCH -N 4                  # node count
#SBATCH -n 384                # node count
#SBATCH --time=01:30:00       # total run time limit (HH:MM:SS)
##SBATCH --mail-type=all       # send email on job start, end and fail
##SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=tigress-%j.err
#SBATCH --error=tigress-%j.out

CC=$1
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

STARTFLAG=$2


# check if the third argument is provided
if [ -z "$3" ]; then
    echo "Usage: $0 <compiler> <start_flag> <crbc>"
    CRBC=lngrad
else
    CRBC=$3
fi

# check if the third argument is a valid value
if [[ "$CRBC" != "diode" && "$CRBC" != "lngrad" && "$CRBC" != "lngrad_out" && "$CRBC" != "lingrad" && "$CRBC" != "lingrad_out" ]]; then
    echo "Invalid value for crbc=$CRBC. Use 'diode' or 'lngrad'."
    exit 1
fi

# check if the third argument is provided
if [ -z "$4" ]; then
    echo "Usage: $0 <compiler> <start_flag> <crbc>"
    MHDBC=lngrad
else
    MHDBC=$4
fi

# check if the third argument is a valid value
if [[ "$MHDBC" != "diode" && "$MHDBC" != "lngrad" && "$MHDBC" != "lngrad_out" && "$MHDBC" != "lingrad" && "$MHDBC" != "lingrad_out" ]]; then
    echo "Invalid value for MHDBC=$MHDBC. Use 'diode' or 'lngrad'."
    exit 1
fi

# Define problem and paths
physics=crmhd
prob=tigress_classic
SRCDIR=$HOME/tigris
SCRIPTDIR=$HOME/tigris_scripts/$prob/stellar

# Define executable and input files
EXE=${prob}_${physics}_${CC}$debug_option.exe
RUNDIR=/scratch/gpfs/$USER/$prob/${physics}-rst-mhdbc_$MHDBC-crbc_$CRBC-$CC

# Define table directories and files
TBLDIR="$SRCDIR/inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

extra_params="time/tlim=201 mesh/mhd_outflow_bc=$MHDBC mesh/cr_outflow_bc=$CRBC output2/ghost_zones=true output2/dt=0 output2/dcycle=100 time/nlim=834000"

# Print the run directory
echo $RUNDIR

# Create run directory if it doesn't exist, or clean it if it does
if [ -d $RUNDIR ] ; then
    echo "directory exists"
    if [[ $STARTFLAG != "-r" ]]; then
        echo "cleaning up"
        rm -rf $RUNDIR/*
    fi
else
    mkdir -p $RUNDIR
fi

# Change to the run directory
cd $RUNDIR

# Print the parameters
echo $extra_arams

# Enable pipefail option for better error handling
set -o pipefail

# Define the restart input file
RSTINPUT=../crmhd-16pc-r_ret100-fgas0.7-df6-gravdt-icpx/TIGRESS.00004.rst

echo "Restart from $RSTINPIT"
cp ${SCRIPTDIR}/$SCRIPT .
cp ${SCRIPTDIR}/$EXE .
cp $TBLDIR/$COOL_TBL .
cp $TBLDIR/$POPSYNTH_TBL .
srun $EXE -r $RSTINPUT -t 47:30:00 $extra_params 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"
