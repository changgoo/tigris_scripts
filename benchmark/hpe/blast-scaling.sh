#!/bin/bash
#PBS -N mhd
#PBS -v comment=freq=max
#PBS -l place=scatter:excl
#PBS -j oe
#PBS -l walltime=2:00:00

cd $PBS_O_WORKDIR

# Load Intel OneAPI environment
module load intel-oneapi/2025.2.0/tbb/2022.2
module load intel-oneapi/2025.2.0/umf/0.11.0
module load intel-oneapi/2025.2.0/dpl/2022.9
module load intel-oneapi/2025.2.0/compiler-rt/2025.2.1
module load intel-oneapi/2025.2.0/compiler/2025.2.1
module load intel-oneapi/2025.2.0/mkl/2025.2
module load intel-oneapi/2025.2.0/mpi/2021.16


res=${NTASKS}
echo "submitting a job with NTASK=$NTASKS: $MBRES $CC $PHYSICS $res"

# Define problem and paths
prob=blast
SRCDIR=$HOME/athena
SCRIPTDIR=$HOME/tigris_scripts/benchmark/hpe

# Define executable and input files
EXE=${prob}_${PHYSICS}_${CC}.exe
INPUT=athinput.$prob
RUNDIR=$HOME/$MACHINE/${prob}-scaling-$CC/${PHYSICS}-${MBRES}_n$NTASKS

if [[ $MBRES == "mb32" ]] ; then
    mb_nx=32
elif [[ $MBRES == "mb64" ]] ; then
    mb_nx=64
elif [[ $MBRES == "mb16" ]] ; then
    mb_nx=16
elif [[ $MBRES == "mb128" ]] ; then
    mb_nx=128
elif [[ $MBRES == "mb256" ]] ; then
    mb_nx=256
else
    echo "Invalid meshblock resolution: $MBRES"
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
elif [[ $res == "128" ]] ; then
    mesh_nx1=$((mb_nx*4))
    mesh_nx2=$((mb_nx*4))
    mesh_nx3=$((mb_nx*8))
    mesh_x1min=$(( -mesh_L*4 ))
    mesh_x1max=$(( mesh_L*4 ))
    mesh_x2min=$(( -mesh_L*4 ))
    mesh_x2max=$(( mesh_L*4 ))
    mesh_x3min=$(( -mesh_L*8 ))
    mesh_x3max=$(( mesh_L*8 ))
elif [[ $res == "144" ]] ; then
    mesh_nx1=$((mb_nx*4))
    mesh_nx2=$((mb_nx*6))
    mesh_nx3=$((mb_nx*6))
    mesh_x1min=$(( -mesh_L*4 ))
    mesh_x1max=$(( mesh_L*4 ))
    mesh_x2min=$(( -mesh_L*6 ))
    mesh_x2max=$(( mesh_L*6 ))
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
    echo "Invalid resolution: $res"
fi
meshblock="meshblock/nx1=$mb_nx meshblock/nx2=$mb_nx meshblock/nx3=$mb_nx"
mesh="mesh/nx1=$mesh_nx1 mesh/nx2=$mesh_nx2 mesh/nx3=$mesh_nx3 mesh/x1min=$mesh_x1min mesh/x1max=$mesh_x1max mesh/x2min=$mesh_x2min mesh/x2max=$mesh_x2max mesh/x3min=$mesh_x3min mesh/x3max=$mesh_x3max"

params="$mesh $meshblock time/nlim=100 time/ncycle_out=1 output2/dt=-1"

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
mpirun -n $NTASKS ./$EXE -i $INPUT -t 00:30:00 $params 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"

cd $SCRIPTDIR
