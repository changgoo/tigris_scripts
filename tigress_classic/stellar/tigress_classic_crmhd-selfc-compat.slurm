#!/bin/bash
#SBATCH --job-name=crmhd-compat
#SBATCH --account=eost
#SBATCH -N 6
#SBATCH -n 512
#SBATCH --time=48:00:00
#SBATCH --mail-type=all
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=tigress-compat-%j.out
#SBATCH --error=tigress-compat-%j.err

# Backward-compatibility run for the ncr-cr-coupling executable.  This uses
# the archived inputs and physical parameters from the original Vmax2 run,
# but writes to a separate directory so that the reference run is untouched.

usage="Usage: $0 <-i|-r> [RSTNUM=final]"
STARTFLAG=${1:-}
RSTNUM=${2:-final}

if [[ "$STARTFLAG" != "-i" && "$STARTFLAG" != "-r" ]]; then
    echo "$usage"
    exit 1
fi

module purge
module load anaconda3/2023.3 intel-oneapi/2024.2 \
    openmpi/oneapi-2024.2/4.1.6 \
    hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 \
    fftw/oneapi-2024.2/3.3.10

prob=tigress_classic
PID=TIGRESS
SCRIPT=${prob}_crmhd-selfc-compat.slurm
SCRIPTDIR=$HOME/tigris_scripts/$prob/stellar
EXE=tigris_crmhd-fft.exe

REFDIR=/scratch/gpfs/$USER/$prob/crmhd-8pc-b1-mhdbc_diode-crbc_lngrad_out-sigma_selfc-Vmax2
RUNDIR=/scratch/gpfs/$USER/$prob/crmhd-8pc-b1-mhdbc_diode-crbc_lngrad_out-sigma_selfc-Vmax2-ncr-cr-coupling-compat

INPUT=athinput.$prob
COOL_TBL=tigress_coolftn.txt
POPSYNTH_TBL=Z014_GenevaV00.txt

# These are the command-line overrides recorded in the reference job script.
medres_normal="mesh/nx1=128 mesh/nx2=128 mesh/nx3=1024 mesh/x3min=-4096 mesh/x3max=4096"
params="job/problem_id=$PID time/tlim=500 $medres_normal cooling/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL orbital_advection/Omega0=0.0"
periodic="mesh/ix1_bc=periodic mesh/ox1_bc=periodic"
extra_params="perturbation/rseed=1 particle1/fgas=0.7 particle1/r_return=100 gravity/solve_grav_hyperbolic_dt=true hydro/dfloor=1.e-6 hydro/pfloor=1.e-6 mesh/mhd_outflow_bc=diode mesh/cr_outflow_bc=lngrad_out output2/dt=1 output3/dt=1 $periodic"
extra_params2="cr/vmax=2e9 problem/beta0=1"

for source_file in \
    "$SCRIPTDIR/$EXE" \
    "$REFDIR/$INPUT" \
    "$REFDIR/$COOL_TBL" \
    "$REFDIR/$POPSYNTH_TBL"; do
    if [[ ! -f "$source_file" ]]; then
        echo "Required file not found: $source_file" >&2
        exit 1
    fi
done

if [[ "$STARTFLAG" == "-i" ]]; then
    if [[ -e "$RUNDIR" ]]; then
        echo "Refusing to overwrite existing compatibility run: $RUNDIR" >&2
        exit 1
    fi
    mkdir -p "$RUNDIR"
elif [[ ! -d "$RUNDIR" ]]; then
    echo "Cannot restart; run directory not found: $RUNDIR" >&2
    exit 1
fi

cd "$RUNDIR" || exit 1
echo "Run directory: $RUNDIR"
echo "Executable: $SCRIPTDIR/$EXE"
echo "Parameters: $params $extra_params $extra_params2"

if [[ "$STARTFLAG" == "-i" ]]; then
    cp -p "$SCRIPTDIR/$SCRIPT" .
    cp -p "$SCRIPTDIR/$EXE" .
    cp -p "$REFDIR/$INPUT" .
    cp -p "$REFDIR/$COOL_TBL" .
    cp -p "$REFDIR/$POPSYNTH_TBL" .

    set -o pipefail
    srun "./$EXE" -i "$INPUT" -t 47:30:00 \
        $params $extra_params $extra_params2 \
        >out.txt 2>err.txt
    EXITCODE=$?
    set +o pipefail
else
    RSTINPUT=$PID.$RSTNUM.rst
    if [[ ! -f "$RSTINPUT" ]]; then
        echo "Restart file not found: $RUNDIR/$RSTINPUT" >&2
        exit 1
    fi
    rstnum=$(find . -maxdepth 1 -name 'out.r*.txt' -printf '.' | wc -c)

    set -o pipefail
    srun "./$EXE" -r "$RSTINPUT" -t 47:30:00 \
        >"out.r${rstnum}.txt" 2>"err.r${rstnum}.txt"
    EXITCODE=$?
    set +o pipefail
fi

echo "EXITCODE = $EXITCODE"

if [[ $EXITCODE -eq 3 ]]; then
    echo "Resubmitting"
    sbatch "$SCRIPT" -r final
    exit $?
fi

exit "$EXITCODE"
