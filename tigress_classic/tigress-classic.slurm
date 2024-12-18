#!/bin/bash
#SBATCH --job-name=tigress    # create a short name for your job
#SBATCH --account=eost        # account (mandatory for tiger3)
#SBATCH -N 4                  # node count
#SBATCH -n 384                # node count
#SBATCH --time=24:00:00       # total run time limit (HH:MM:SS)
#SBATCH --mail-type=all       # send email on job start, end and fail
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=tigress-%j.err
#SBATCH --error=tigress-%j.out

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

STARTFLAG=$2

prob=tigress_classic
PID=TIGRESS
SRCDIR=/home/$USER/tigris
SCRIPTDIR=/home/$USER/tigris_scripts/$prob
SCRIPT=$prob-tiger3.slurm
EXE=${prob}_${CC}$debug_option.exe
INPUT=${SCRIPTDIR}/athinput.$prob
RUNDIR=/scratch/gpfs/$USER/$prob/run-$CC

TBLDIR="$SRCDIR/inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

params="job/problem_id=$PID time/tlim=500 mesh/nx1=128 mesh/nx2=128 mesh/nx3=768 cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL feedback/iredist=false feedback/vmax=5000 feedback/fkin=0.28"
# feedback/iredist=false feedback/imom=true feedback/fkin=0 hydro/neighbor_flooring=true problem/beta0=0 problem/beta_r=1.e6"
periodic="mesh/ix1_bc=periodic mesh/ox1_bc=periodic"
echo $RUNDIR

# Create run directory
if [ -d $RUNDIR ] ; then
    echo "directory exists"
    if [[ $STARTFLAG != "-r" ]]; then
        echo "cleaning up"
        rm -rd $RUNDIR/*
    fi
else
    mkdir -p $RUNDIR
fi

cd $RUNDIR

echo $params
# cat $INPUT

set -o pipefail

RSTINPUT=$PID.final.rst
if [ ! -f $RSTINPUT ]; then
    echo "Starting fresh"
    cp ${SCRIPTDIR}/$SCRIPT .
    cp ${SCRIPTDIR}/$EXE .
    cp $INPUT .
    cp $TBLDIR/$COOL_TBL .
    cp $TBLDIR/$POPSYNTH_TBL .
    srun $EXE -i $INPUT -t 23:30:00 $params 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"
else
    echo "Restarting"
    srun $EXE -r $RSTINPUT -t 23:30:00 1> "$RUNDIR/out.rst.txt" 2> "$RUNDIR/err.rst.txt"
fi

EXITCODE=$?
echo "EXITCODE = $EXITCODE"

set +o pipefail

if [[ $EXITCODE -eq 2 ]]; then
    echo "Resubmitting"
    sbatch $SCRIPT $CC -r
fi

# make quick snapshots
cd $RUNDIR
module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena-lem

PYTHONDIR=$HOME/pyathena_master
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$PYTHONDIR/pyathena/tigresspp/do_tasks.py
srun python -m mpi4py $pythonscript -b `pwd`
