#!/bin/bash
#SBATCH --job-name=radiative_snr    # create a short name for your job
#SBATCH --account=eost        # account (mandatory for tiger3)
##SBATCH -N 1                  # node count
##SBATCH -n 48                 # node count
#SBATCH -N 1                  # node count
#SBATCH -n 64                 # node count
#SBATCH --time=01:00:00       # total run time limit (HH:MM:SS)
#SBATCH --output=radiative_snr-debug.out
#SBATCH --error=radiative_snr-debug.err

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

prob=radiative_snr
PID=SNR
SRCDIR=$HOME/tigris
SCRIPTDIR=$HOME/tigris_scripts/$prob/tiger
EXE=${prob}_${physics}_${CC}$debug_option.exe
INPUT=athinput.$prob

RUNDIR=/scratch/gpfs/EOST/$USER/$prob/${physics}-$CC

TBLDIR="$SRCDIR/inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

# params="job/problem_id=$PID cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL output1/dt=0 output1/dcycle=1 time/tlim=10 problem/beta0=0 problem/beta_r=10 feedback/mratio_thresh=1.0"
params="job/problem_id=$PID time/tlim=5 cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL"
#output1/dt=0 output1/dcycle=1 output2/dt=0 output2/dcycle=100 time/ncycle_out=1"
periodic="mesh/ix1_bc=periodic mesh/ox1_bc=periodic"
extra_params="cr/sigma=1.e-25 cr/self_consistent_flag=1 hydro/dfloor=1.e-6 hydro/pfloor=1.e-6 $periodic"
echo $RUNDIR

# Create run directory
if [ -d $RUNDIR ] ; then
    echo "directory exists"
    rm -rd $RUNDIR/*
else
    mkdir -p $RUNDIR
fi

cd $RUNDIR
cp $0 ./$SCRIPT
cp ${SCRIPTDIR}/$EXE .
cp ${SCRIPTDIR}/../$INPUT .
cp $TBLDIR/$COOL_TBL .
cp $TBLDIR/$POPSYNTH_TBL .

echo $params $extra_params
# cat $INPUT

srun $EXE -i $INPUT -t 00:55:00 $params $extra_params 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"
