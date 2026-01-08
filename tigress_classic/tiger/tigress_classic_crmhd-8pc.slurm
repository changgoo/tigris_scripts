#!/bin/bash
#SBATCH --job-name=crmhd-8pc    # create a short name for your job
#SBATCH --account=eost        # account (mandatory for tiger3)
#SBATCH -N 5                  # node count
#SBATCH -n 512                # node count
#SBATCH --time=48:00:00       # total run time limit (HH:MM:SS)
#SBATCH --mail-type=all       # send email on job start, end and fail
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=tigress-%j.err
#SBATCH --error=tigress-%j.out

# default parameters (short names)
STARTFLAG=
physics=mhd
int=rk2
xo=2
ia=false
fbin=0.0
fgas=0.7
beta=1
MHDBC=diode
CRBC=lngrad_out
shear=false
CC=icpx
RSTNUM=final

# parse args: accept KEY=VALUE pairs (short or long names) and one positional STARTFLAG
for arg in "$@"; do
    if [[ "$arg" == *=* ]]; then
        key=${arg%%=*}
        val=${arg#*=}
        case "$key" in
            STARTFLAG|startflag) STARTFLAG=$val ;;
            physics)            physics=$val ;;
            integrator|int)     int=$val ;;
            xorder|xo)          xo=$val ;;
            type_ia_sn|ia)      ia=$val ;;
            fbinary|fbin)       fbin=$val ;;
            fgas)               fgas=$val ;;
            beta)               beta=$val ;;
            MHDBC|mhdbc)        MHDBC=$val ;;
            CRBC|crbc)          CRBC=$val ;;
            shear)              shear=$val ;;
            CC|cc)              CC=$val ;;
            RSTNUM|rstnum)      RSTNUM=$val ;;
            *) echo "Unknown parameter: $key" >&2; exit 1 ;;
        esac
    else
        # treat first non-key arg as STARTFLAG (e.g. "-r")
        if [[ -z "$STARTFLAG" ]]; then
            STARTFLAG=$arg
        else
            echo "Unexpected positional arg: $arg" >&2
            exit 1
        fi
    fi
done

usage="Usage: $0 <STARTFLAG> physics=<mhd> int=<rk2> xo=<2> ia=<false> fbin=<0.0> fgas=<0.7> beta=<1> MHDBC=<diode> CRBC=<lngrad_out> shear=<false> CC=<icpx> RSTNUM=<final>"

# build job options from ordered short keys and construct base name like key_value-key2_value
keys=(physics int xo ia fbin fgas beta MHDBC CRBC shear)
job_opts=()
name_parts=()
for k in "${keys[@]}"; do
    job_opts+=("$k=${!k}")        # e.g. "fgas=0.7"
    name_parts+=("${k}_${!k}")    # e.g. "fgas_0.7"
done
job_options="${job_opts[*]}"
base_name=$(IFS=-; echo "${name_parts[*]}")
echo "restart options: $0 -r $job_options RSTNUM=$RSTNUM"
echo "base name: $base_name"

# Validate required arguments
[[ -z "$STARTFLAG" ]] && echo "$usage" && exit 1

# Validate boundary condition arguments
valid_phy="crmhd crmhd_duale crmhd_lhll crmhd_duale_lhll crmhd_duals"
[[ ! " $valid_phy " =~ " $physics " ]] && echo "Invalid physics=$physics" && exit 1

# Validate boundary condition arguments
valid_bc="diode lngrad lngrad_out lingrad lingrad_out"
[[ ! " $valid_bc " =~ " $MHDBC " ]] && echo "Invalid MHDBC=$MHDBC" && exit 1
[[ ! " $valid_bc " =~ " $CRBC " ]] && echo "Invalid CRBC=$CRBC" && exit 1

# Load modules based on compiler
if [[ "$CC" == icpx* ]]; then
    module purge; module load anaconda3/2023.3 intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10
elif [[ "$CC" == g++* ]]; then
    module purge; module load anaconda3/2023.3 fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4
else
    module purge; module load anaconda3/2023.3 fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4
    debug_option="-debug"
fi

# print the job submission details
echo "Submitting a job: $0 $job_options"

# Define problem and paths
prob=tigress_classic
PID=TIGRESS
SRCDIR=$HOME/tigris
SCRIPTDIR=$HOME/tigris_scripts/$prob/tiger
SCRIPT=${prob}_crmhd-8pc.slurm

# Define executable and input files
EXE=tigris_${physics}.exe
INPUT=athinput.$prob
RUNDIR=/scratch/gpfs/EOST/$USER/$prob/${base_name}-8pc-fe05

# Define table directories and files
TBLDIR="$SRCDIR/inputs/tables"
COOL_TBL="tigress_coolftn.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

lowres_normal="meshblock/nx1=16 meshblock/nx2=16 meshblock/nx3=16 mesh/nx3=512 mesh/x3min=-4096 mesh/x3max=4096"
medres_normal="mesh/nx1=128 mesh/nx2=128 mesh/nx3=1024 mesh/x3min=-4096 mesh/x3max=4096"

params="job/problem_id=$PID time/tlim=500 $medres_normal cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL"
periodic="orbital_advection/Omega0=0.0 mesh/ix1_bc=periodic mesh/ox1_bc=periodic"
shear_periodic="mesh/ix1_bc=shear_periodic mesh/ox1_bc=shear_periodic hydro/fofc_shear=true"
extra_params="perturbation/rseed=1 particle1/fgas=$fgas particle1/r_return=100 gravity/solve_grav_hyperbolic_dt=true cr/sigma=1.e-25 cr/self_consistent_flag=1 hydro/dfloor=1.e-6 hydro/pfloor=1.e-6 mesh/mhd_outflow_bc=$MHDBC mesh/cr_outflow_bc=$CRBC problem/beta0=$beta output2/dt=1 output3/dt=1 particle1/type_ia_sn=$ia feedback/fbinary=$fbin time/integrator=$int time/xorder=$xo feedback/fe_CR=0.05"

if [[ $shear == true ]]; then
    extra_params="$extra_params $shear_periodic"
else
    extra_params="$extra_params $periodic"
fi

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
RSTINPUT=$PID.$RSTNUM.rst
if [ ! -f $RSTINPUT ]; then
    echo "Starting fresh"
    cp $0 ./$SCRIPT
    cp ${SCRIPTDIR}/$EXE .
    cp ${SCRIPTDIR}/../$INPUT .
    cp $TBLDIR/$COOL_TBL .
    cp $TBLDIR/$POPSYNTH_TBL .
    srun $EXE -i $INPUT -t 47:30:00 $params $extra_params 1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"
else
    echo "Restarting with $RSTINPUT"
    rstnum=`ls out.*.txt | wc -l`
    srun $EXE -r $RSTINPUT -t 47:30:00 1> "$RUNDIR/out.r${rstnum}.txt" 2> "$RUNDIR/err.r${rstnum}.txt"
fi

EXITCODE=$?
echo "EXITCODE = $EXITCODE"

set +o pipefail

if [[ $EXITCODE -eq 3 ]]; then
    echo "Resubmitting"
    sbatch $SCRIPT -r $job_options
fi

# make quick snapshots
# cd $RUNDIR
# module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena-lem

# PYTHONDIR=$HOME/pyathena_master
# export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
# pythonscript=$PYTHONDIR/pyathena/tigresspp/do_tasks.py
# srun python -m mpi4py $pythonscript -b `pwd`

cd $RUNDIR
module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena

PYTHONDIR=$HOME/pyathena
export PYTHONPATH="$PYTHONDIR:$PYTHONPATH"
pythonscript=$HOME/TIGRESS-CR/python/plot_slices.py
srun python -m mpi4py $pythonscript `pwd`
