#!/bin/bash
#SBATCH --job-name=tigress-debug    # create a short name for your job
#SBATCH --account=eost        # account (mandatory for tiger3)
##SBATCH -N 1                  # node count
##SBATCH -n 48                 # node count
#SBATCH -N 4                  # node count
#SBATCH -n 384                # node count
#SBATCH --time=01:00:00       # total run time limit (HH:MM:SS)
#SBATCH --output=tigress-debug.out
#SBATCH --error=tigress-debug.err

CC=$1
debug_option=""
if [[ "$CC" == "icpx" || "$CC" == "icpx-b" ]]  ; then
    module purge; module load anaconda3/2023.3 intel-oneapi/2024.2 intel-mpi/oneapi/2021.13 hdf5/oneapi-2024.2/intel-mpi/1.14.4 fftw/oneapi-2024.2/3.3.10
elif [[ "$CC" == "g++" || "$CC" == "g++-b" ]] ; then
    module purge; module load anaconda3/2023.3 fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4
else
    module purge; module load anaconda3/2023.3 fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4
    CC=g++
    debug_option="-debug"
fi

prob=tigress_classic
PID=TIGRESS
SRCDIR=/home/$USER/tigris
SCRIPTDIR=/home/$USER/tigris_scripts/$prob
EXE=${prob}_${CC}$debug_option.exe
INPUT=${SCRIPTDIR}/athinput.$prob
RUNDIR=/scratch/gpfs/EOST/$USER/$prob/debug-$CC

TBLDIR="$SRCDIR/inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

# params="job/problem_id=$PID cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL output1/dt=0 output1/dcycle=1 time/tlim=10 problem/beta0=0 problem/beta_r=10 feedback/mratio_thresh=1.0"
params="job/problem_id=$PID mesh/nx1=128 mesh/nx2=128 mesh/nx3=768 cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL output1/dt=0 output1/dcycle=1 time/nlim=10 time/ncycle_out=1 feedback/write_rprof=true"
echo $RUNDIR

# Create run directory
if [ -d $RUNDIR ] ; then
    echo "directory exists"
    rm -rd $RUNDIR/*
else
    mkdir -p $RUNDIR
fi

cd $RUNDIR
cp ${SCRIPTDIR}/$EXE .
cp $INPUT .
cp $TBLDIR/$COOL_TBL .
cp $TBLDIR/$POPSYNTH_TBL .

echo $params
# cat $INPUT

srun $EXE -i $INPUT -t 00:55:00 $params 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"

# make quick snapshots
# module purge
# module load anaconda3/2022.5 openmpi/gcc/4.1.0
# conda activate pyathena-lem

# PYTHONDIR=$HOME/pyathena_master
# export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
# pythonscript=$PYTHONDIR/pyathena/tigresspp/do_tasks.py
# srun python $pythonscript -b `pwd`
