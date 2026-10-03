#!/bin/bash
#SBATCH --job-name=ncr8-bench
#SBATCH --exclusive
#SBATCH --time=00:30:00
#SBATCH --output=logs/ncr8bench-%j.out
#SBATCH --error=logs/ncr8bench-%j.err
#
# TIGRESS-NCR toolchain benchmark job (see BENCHMARK_SPEC.md). Submit it with submit.sh,
# which adds the machine's partition, account and node/task counts from <machine>/env.sh;
# the #SBATCH lines above are only the machine-independent part.
#
# Restarts a production checkpoint in a throw-away run directory, advances a fixed number
# of cycles, and reports seconds per cycle from TIGRESS_NCR.loop_time.txt. Every
# toolchain integrates exactly the same cycles from the same state.
#
# Arguments: MACHINE PHYSICS TOOLCHAIN [NCYC] [extra overrides...]
#   MACHINE   : directory with env.sh and the executables (e.g. stellarai-amd)
#   PHYSICS   : mhd|crmhd
#   TOOLCHAIN : one of TOOLCHAINS in env.sh; runs tigris_ncr_PHYSICS-fft-TOOLCHAIN.exe
#   NCYC      : cycles to advance [default: 200]
#   extra     : further block/par=value overrides
# env RSTFILE    : restart file [default: $BENCH_CACHE/$BENCH_RST_<physics>; submit.sh stages it]
# env VARIANT    : flag variant; runs tigris_ncr_PHYSICS-fft-TOOLCHAIN-VARIANT.exe
# env SRUN_OPTS  : extra launcher options, e.g. "--distribution=block:block"
# env OMPI_MCA_*, I_MPI_*, UCX_* : MPI tuning; recorded in the result line
# env KEEP_RST   : 1 keeps the ~3-4 GB TIGRESS_NCR.final.rst written at exit
# env NCR_DIR    : tigress_ncr scripts directory [default: $HOME/tigris_scripts/tigress_ncr]
# env SRCDIR     : source worktree for the data tables [default: $HOME/tigris/.worktrees/ncr-cr-coupling]
#
# Result: one line appended to $NCR_DIR/bench/results/<MACHINE>.txt and bench-summary.txt
# in the run directory ($SCRATCH_BASE/tigress_ncr/bench/<physics>-<tc>-<jobid>).

MACHINE=${1:?usage: MACHINE PHYSICS TOOLCHAIN [NCYC] [overrides...]}
PHYSICS=${2:?usage: MACHINE PHYSICS TOOLCHAIN [NCYC] [overrides...]}
TC=${3:?usage: MACHINE PHYSICS TOOLCHAIN [NCYC] [overrides...]}
NCYC=${4:-200}
shift 4 2>/dev/null || shift $#
EXTRA="$*"

NCR_DIR=${NCR_DIR:-$HOME/tigris_scripts/tigress_ncr}
BENCHDIR=$NCR_DIR/bench
MACHDIR=$NCR_DIR/$MACHINE
source "$MACHDIR/env.sh" || exit 1
load_toolchain "$TC" || exit 1
module list 2>&1

SRCDIR=${SRCDIR:-$HOME/tigris/.worktrees/ncr-cr-coupling}
TBLDIR=$SRCDIR/inputs/tables
RSTVAR=BENCH_RST_$PHYSICS
RSTFILE=${RSTFILE:-$BENCH_CACHE/${!RSTVAR}}
EXE=tigris_ncr_${PHYSICS}-fft-${TC}${VARIANT:+-$VARIANT}.exe
RUNDIR=$SCRATCH_BASE/tigress_ncr/bench/${PHYSICS}-${TC}${VARIANT:+-$VARIANT}-${SLURM_JOB_ID}

[ -x "$MACHDIR/$EXE" ] || { echo "ERROR: executable not found: $MACHDIR/$EXE"; exit 1; }
[ -f "$RSTFILE" ] || { echo "ERROR: restart file not found: '$RSTFILE'"; exit 1; }

# time/nlim is absolute, so add NCYC to the restart cycle. One meshblock per rank.
read -r NBTOTAL _T0 _DT NCYC0 < <(python3 "$BENCHDIR/rst_info.py" "$RSTFILE")
if [ "$SLURM_NTASKS" != "$NBTOTAL" ]; then
    echo "ERROR: $SLURM_NTASKS tasks but the checkpoint has $NBTOTAL meshblocks (use submit.sh)"
    exit 1
fi
NLIM=$((NCYC0 + NCYC))

mkdir -p "$RUNDIR"; cd "$RUNDIR"
cp "$MACHDIR/$EXE" .
[ -f "$MACHDIR/${EXE%.exe}.buildinfo" ] && cp "$MACHDIR/${EXE%.exe}.buildinfo" .
cp "$TBLDIR/tigress_coolftn_ncr.txt" "$TBLDIR/Z014_GenevaV00.txt" .
ln -sf "$RSTFILE" start.rst

params="time/nlim=$NLIM time/ncycle_out=10 time/ncycle_out_timing=10 job/output_timing=true $EXTRA"
echo "RUNDIR  = $RUNDIR"
echo "EXE     = $EXE"
echo "RSTFILE = $RSTFILE (cycle $NCYC0, $NBTOTAL meshblocks)"
echo "params  = $params"
echo "launch  = $MPI_LAUNCH ${SRUN_OPTS:-}"

T0=$(date +%s)
$MPI_LAUNCH $SRUN_OPTS "./$EXE" -r start.rst -t 00:25:00 $params 1> out.txt 2> err.txt
EXITCODE=$?
T1=$(date +%s)
echo "EXITCODE = $EXITCODE"

python3 "$BENCHDIR/parse_loop_time.py" TIGRESS_NCR.loop_time.txt \
    machine="$MACHINE" physics="$PHYSICS" tc="$TC" variant="${VARIANT:-default}" job="$SLURM_JOB_ID" \
    nranks="$SLURM_NTASKS" nodes="$SLURM_JOB_NUM_NODES" rc="$EXITCODE" \
    job_wall="$((T1 - T0))" opts="${SRUN_OPTS:-default} ${BENCH_MPIENV:-}" | tee bench-summary.txt
mkdir -p "$BENCHDIR/results"
cat bench-summary.txt >> "$BENCHDIR/results/$MACHINE.txt"

[ "${KEEP_RST:-0}" == "1" ] || rm -f TIGRESS_NCR.final.rst
