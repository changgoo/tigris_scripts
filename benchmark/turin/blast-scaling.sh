#!/bin/bash
#SBATCH --job-name=blast_mhd    # create a short name for your job
#SBATCH -N 1
#SBATCH -n 512
#SBATCH --exclusive
#SBATCH --time=01:00:00       # total run time limit (HH:MM:SS)
#SBATCH --mail-type=all       # send email on job start, end and fail
#SBATCH --mail-user=changgookim@gmail.com
#SBATCH --output=blast-%j.err
#SBATCH --error=blast-%j.out

usage="Usage: NTASKS=N ./$0 <meshblock_resolution> <CC> <physics>"

# module purge; module load gcc; module load openmpi; module load fftw hdf5
mbres=${1:-mb32}
CC=${2:-aocc}
physics=${3:-hydro}
res=${4:-${NTASKS}}

if [ "$CC" == "icpx" ] ; then
    module purge; module load anaconda3/2023.3 intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6
    debug_option=""
elif [ "$CC" == "g++" ] ; then
    module purge; module load anaconda3/2025.6 gcc-toolset/14 openmpi/gcc/4.1.6
elif [ "$CC" == "g++-simd" ] ; then
    module purge; module load anaconda3/2025.6 gcc-toolset/14 openmpi/gcc/4.1.6
elif [ "$CC" == "aocc" ] ; then
    module purge; module load anaconda3/2025.6 gcc-toolset/14 aocc/5.0.0 openmpi/aocc-5.0.0/4.1.6
    debug_option=""
elif [ "$CC" == "aocc-simd" ] ; then
    module purge; module load anaconda3/2025.6 gcc-toolset/14 aocc/5.0.0 openmpi/aocc-5.0.0/4.1.6
    debug_option=""
fi

echo "submitting a job with NTASK=$NTASKS: $mbres $CC $physics $res"

# Define problem and paths
prob=blast
machine=turin
SRCDIR=$HOME/athena
SCRIPTDIR=$HOME/tigris_scripts/benchmark/$machine
SCRIPT=${prob}-scaling.slurm
SCRATCH=/scratch/gpfs/$USER

# Define executable and input files
EXE=${prob}_${physics}_${CC}.exe
INPUT=athinput.$prob
RUNDIR=$SCRATCH/${machine}_new/${prob}-scaling-$CC/${physics}-${mbres}_n$NTASKS

if [[ $mbres == "mb32" ]] ; then
    mb_nx=32
elif [[ $mbres == "mb64" ]] ; then
    mb_nx=64
elif [[ $mbres == "mb16" ]] ; then
    mb_nx=16
elif [[ $mbres == "mb128" ]] ; then
    mb_nx=128
elif [[ $mbres == "mb256" ]] ; then
    mb_nx=256
else
    echo "Invalid meshblock resolution: $mbres"
    exit 1
fi

mesh_L=1
if [[ $res == "1" ]] ; then
    mesh_nx1=$mb_nx
    mesh_nx2=$mb_nx
    mesh_nx3=$mb_nx
    mesh_x1min=$(( -mesh_L ))
    mesh_x1max=$(( mesh_L ))
    mesh_x2min=$(( -mesh_L ))
    mesh_x2max=$(( mesh_L ))
    mesh_x3min=$(( -mesh_L ))
    mesh_x3max=$(( mesh_L ))
elif [[ $res == "2" ]] ; then
    mesh_nx1=$mb_nx
    mesh_nx2=$mb_nx
    mesh_nx3=$((mb_nx*2))
    mesh_x1min=$(( -mesh_L ))
    mesh_x1max=$(( mesh_L ))
    mesh_x2min=$(( -mesh_L ))
    mesh_x2max=$(( mesh_L ))
    mesh_x3min=$(( -mesh_L*2 ))
    mesh_x3max=$(( mesh_L*2 ))
elif [[ $res == "4" ]] ; then
    mesh_nx1=$mb_nx
    mesh_nx2=$((mb_nx*2))
    mesh_nx3=$((mb_nx*2))
    mesh_x1min=$(( -mesh_L ))
    mesh_x1max=$(( mesh_L ))
    mesh_x2min=$(( -mesh_L*2 ))
    mesh_x2max=$(( mesh_L*2 ))
    mesh_x3min=$(( -mesh_L*2 ))
    mesh_x3max=$(( mesh_L*2 ))
elif [[ $res == "8" ]] ; then
    mesh_nx1=$((mb_nx*2))
    mesh_nx2=$((mb_nx*2))
    mesh_nx3=$((mb_nx*2))
    mesh_x1min=$(( -mesh_L*2 ))
    mesh_x1max=$(( mesh_L*2 ))
    mesh_x2min=$(( -mesh_L*2 ))
    mesh_x2max=$(( mesh_L*2 ))
    mesh_x3min=$(( -mesh_L*2 ))
    mesh_x3max=$(( mesh_L*2 ))
elif [[ $res == "16" ]] ; then
    mesh_nx1=$((mb_nx*2))
    mesh_nx2=$((mb_nx*2))
    mesh_nx3=$((mb_nx*4))
    mesh_x1min=$(( -mesh_L*2 ))
    mesh_x1max=$(( mesh_L*2 ))
    mesh_x2min=$(( -mesh_L*2 ))
    mesh_x2max=$(( mesh_L*2 ))
    mesh_x3min=$(( -mesh_L*4 ))
    mesh_x3max=$(( mesh_L*4 ))
elif [[ $res == "32" ]] ; then
    mesh_nx1=$((mb_nx*2))
    mesh_nx2=$((mb_nx*4))
    mesh_nx3=$((mb_nx*4))
    mesh_x1min=$(( -mesh_L*2 ))
    mesh_x1max=$(( mesh_L*2 ))
    mesh_x2min=$(( -mesh_L*4 ))
    mesh_x2max=$(( mesh_L*4 ))
    mesh_x3min=$(( -mesh_L*4 ))
    mesh_x3max=$(( mesh_L*4 ))
elif [[ $res == "64" ]] ; then
    mesh_nx1=$((mb_nx*4))
    mesh_nx2=$((mb_nx*4))
    mesh_nx3=$((mb_nx*4))
    mesh_x1min=$(( -mesh_L*4 ))
    mesh_x1max=$(( mesh_L*4 ))
    mesh_x2min=$(( -mesh_L*4 ))
    mesh_x2max=$(( mesh_L*4 ))
    mesh_x3min=$(( -mesh_L*4 ))
    mesh_x3max=$(( mesh_L*4 ))
elif [[ $res == "96" ]] ; then
    mesh_nx1=$((mb_nx*4))
    mesh_nx2=$((mb_nx*4))
    mesh_nx3=$((mb_nx*6))
    mesh_x1min=$(( -mesh_L*4 ))
    mesh_x1max=$(( mesh_L*4 ))
    mesh_x2min=$(( -mesh_L*4 ))
    mesh_x2max=$(( mesh_L*4 ))
    mesh_x3min=$(( -mesh_L*6 ))
    mesh_x3max=$(( mesh_L*6 ))
else
    mesh_nx1=$res
    mesh_nx2=$res
    mesh_nx3=$res
    mesh_x1min=$(( -mesh_L ))
    mesh_x1max=$(( mesh_L ))
    mesh_x2min=$(( -mesh_L ))
    mesh_x2max=$(( mesh_L ))
    mesh_x3min=$(( -mesh_L ))
    mesh_x3max=$(( mesh_L ))
    RUNDIR=$SCRATCH/${machine}_new/${prob}-strong-scaling-$CC-${mbres}/${physics}_${res}_n$NTASKS
    echo "Invalid resolution: $res"
fi
meshblock="meshblock/nx1=$mb_nx meshblock/nx2=$mb_nx meshblock/nx3=$mb_nx"
mesh="mesh/nx1=$mesh_nx1 mesh/nx2=$mesh_nx2 mesh/nx3=$mesh_nx3 mesh/x1min=$mesh_x1min mesh/x1max=$mesh_x1max mesh/x2min=$mesh_x2min mesh/x2max=$mesh_x2max mesh/x3min=$mesh_x3min mesh/x3max=$mesh_x3max"

params="$mesh $meshblock time/nlim=10 time/ncycle_out=1 output2/dt=-1"

# Print the run directory
echo $params
echo $RUNDIR

# Create run directory if it doesn't exist, or clean it if it does
if [ -d $RUNDIR ] ; then
    # echo "directory exists"
    echo "cleaning up"
    rm -rf $RUNDIR/*
else
    mkdir -p $RUNDIR
fi

# Change to the run directory
cd $RUNDIR

# echo "Starting fresh"
cp ${SCRIPTDIR}/$EXE .
cp ${SCRIPTDIR}/../$INPUT .
mpirun -n $NTASKS $EXE -i $INPUT -t 00:30:00 $params 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"

cd $SCRIPTDIR
