#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=64
#SBATCH --partition=cpu          # <- or one of: gpuA100x4 gpuA40x4 gpuA100x8 gpuMI100x8
#SBATCH --account=bdne-delta-cpu # <- match to a "Project" returned by the "accounts"
#SBATCH --job-name=crmhd
#SBATCH --time=24:00:00      # hh:mm:ss for the job
#SBATCH --constraint="scratch"
##SBATCH --mail-type=all       # send email on job start, end and fail
##SBATCH --mail-user=changgookim@gmail.com
#SBATCH --output=tigress-%j.err
#SBATCH --error=tigress-%j.out

conda deactivate
conda deactivate
module purge; module reset; module load fftw hdf5

# disable cxi
unset OMPI_MCA_mtl_ofi_provider_include
export OMPI_MCA_mtl_ofi_provider_exclude=cxi

SCRATCH=/work/hdd/bdne/$USER
STARTFLAG=$1
fgas=0.7

# Define problem and paths
physics=crmhd
prob=tigress_classic
PID=TIGRESS
SRCDIR=$HOME/tigris
SCRIPTDIR=$HOME/tigris_scripts/$prob/delta
SCRIPT=${prob}.slurm

# Define executable and input files
EXE=${prob}_${physics}.exe
INPUT=athinput.$prob
RUNDIR=$SCRATCH/$prob/crmhd

# Define table directories and files
TBLDIR="$SRCDIR/inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

lowres_bigbox="mesh/nx1=128 mesh/nx2=128 mesh/nx3=512 mesh/x1min=-1024 mesh/x1max=1024 mesh/x2min=-1024 mesh/x2max=1024"
lowres_normal="mesh/x3min=-4096 mesh/x3max=4096 mesh/nx3=512"
medres_normal="mesh/nx1=128 mesh/nx2=128 mesh/nx3=1024"

params="job/problem_id=$PID time/tlim=200 cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL $lowres_normal"
periodic="mesh/ix1_bc=periodic mesh/ox1_bc=periodic orbital_advection/Omega0=0.0"
extra_params="perturbation/rseed=1 particle1/fgas=$fgas particle1/r_return=100 gravity/solve_grav_hyperbolic_dt=true cr/sigma=1.e-25 cr/self_consistent_flag=1 hydro/dfloor=1.e-6 hydro/pfloor=1.e-6 $periodic"

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
echo $params $extra_params

# Enable pipefail option for better error handling
set -o pipefail

# Define the restart input file
RSTINPUT=$PID.final.rst
if [ ! -f $RSTINPUT ]; then
    echo "Starting fresh"
    cp ${SCRIPTDIR}/$SCRIPT .
    cp ${SCRIPTDIR}/$EXE .
    cp ${SCRIPTDIR}/../$INPUT .
    cp $TBLDIR/$COOL_TBL .
    cp $TBLDIR/$POPSYNTH_TBL .
    srun $EXE -i $INPUT -t 23:30:00 $params $extra_params 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"
else
    echo "Restarting"
    rstnum=`ls out.*.txt | wc -l`
    srun $EXE -r $RSTINPUT -t 23:30:00 1> "$RUNDIR/out.r${rstnum}.txt" 2> "$RUNDIR/err.r${rstnum}.txt"
fi

EXITCODE=$?
echo "EXITCODE = $EXITCODE"

set +o pipefail

if [[ $EXITCODE -eq 2 ]]; then
    echo "Resubmitting"
    sbatch $SCRIPT -r
fi

cd $RUNDIR
# module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena

PYTHONDIR=$HOME/pyathena
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$PYTHONDIR/pyathena/tigresspp/plot_slices.py
srun python -m mpi4py $pythonscript `pwd`
