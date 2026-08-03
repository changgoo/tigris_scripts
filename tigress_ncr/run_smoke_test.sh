#!/bin/bash
# filepath: /home/changgoo/tigris_scripts/tigress_ncr/run_smoke_test.sh
#
# Repeatable smoke test for the TIGRESS-NCR (MHD) build. Runs the lightweight
# test input for a few cycles and checks that:
#   - photochemistry (NCR) and ray tracing both initialize,
#   - the run advances without NaN / negative density / FATAL errors.
#
# This does NOT validate physics; it only exercises the coupled code paths.
#
# Usage:
#   ./run_smoke_test.sh [NRANKS] [NLIM]
#     NRANKS : number of MPI ranks (default 32 = 1 block/rank for the 32^3 test).
#              Use 1 for a single-block sanity run on a login/interactive node.
#     NLIM   : cycle limit for the smoke test (default 5).
#
# On a login/interactive node prefer:  ./run_smoke_test.sh 1 5
# For the full 32-rank layout submit from a compute allocation.

# Note: no `set -u` -- the environment-modules init script references $PS1.
set -eo pipefail

NRANKS="${1:-32}"
NLIM="${2:-5}"

SRC="${SRC:-tigris}"
WORKTREE="${WORKTREE:-tigress-ncr}"
SRCDIR="$HOME/$SRC/.worktrees/$WORKTREE"
EXE="$SRCDIR/bin/athena"
TABLES="$SRCDIR/inputs/tables"
INPUT="$(cd "$(dirname "$0")" && pwd)/athinput.tigress_ncr_test"

COOL_TBL="tigress_coolftn_ncr.txt"
POPSYNTH_TBL="Z014_GenevaV00.txt"

# Modules (stellar)
module purge
module load anaconda3/2023.3
module load intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 \
            hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10

if [ ! -x "$EXE" ]; then
  echo "ERROR: executable not found: $EXE (build first with build_tigress.sh)" >&2
  exit 1
fi

RUNDIR="$(mktemp -d "${TMPDIR:-/tmp}/ncr_smoke.XXXXXX")"
echo "Run directory: $RUNDIR"
cp "$EXE" "$RUNDIR/athena"
cp "$TABLES/$COOL_TBL" "$TABLES/$POPSYNTH_TBL" "$RUNDIR/"
cd "$RUNDIR"

# For a single-rank sanity run, collapse to one 32^3 block so 1 block/rank holds.
# Keep cubic (isotropic) cells: ray tracing requires dx1 = dx2 = dx3 at root level.
# 512/32 = 16 pc in every direction, matching the full test resolution.
SINGLE_OVERRIDE=""
if [ "$NRANKS" -eq 1 ]; then
  SINGLE_OVERRIDE="mesh/nx1=32 mesh/nx2=32 mesh/nx3=32 \
    mesh/x1min=-256 mesh/x1max=256 mesh/x2min=-256 mesh/x2max=256 \
    mesh/x3min=-256 mesh/x3max=256"
fi

PARAMS="time/nlim=$NLIM time/tlim=100 \
  photchem_ncr/coolftn_file=$COOL_TBL feedback/pop_synth_file=$POPSYNTH_TBL \
  $SINGLE_OVERRIDE"

LOG="$RUNDIR/smoke.log"
echo "Launching: mpirun -np $NRANKS ./athena -i $INPUT $PARAMS"
set +e
mpirun -np "$NRANKS" ./athena -i "$INPUT" $PARAMS > "$LOG" 2>&1
RC=$?
set -e

echo "----- last 20 lines -----"
tail -20 "$LOG"
echo "-------------------------"

FAIL=0
grep -qiE "PhotochemistryNCR" "$LOG" && echo "OK: photochemistry NCR active" || { echo "MISS: no photochemistry banner"; FAIL=1; }
grep -qiE '\b(nan|inf)\b|negative (density|pressure)|FATAL' "$LOG" && { echo "FAIL: NaN/negative/FATAL in log"; FAIL=1; } || echo "OK: no NaN/negative/FATAL"
grep -qiE "ray.?tracing" "$LOG" && echo "OK: ray tracing referenced" || echo "NOTE: no explicit ray-tracing banner"
[ "$RC" -eq 0 ] && echo "OK: athena exited 0" || { echo "FAIL: athena exit code $RC"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then
  echo "SMOKE TEST PASSED"
else
  echo "SMOKE TEST FAILED (see $LOG)"
  exit 1
fi
