#!/bin/bash
# Compiler-flag sweep: build every variant of <machine>/flag_variants.txt for each physics,
# benchmark them, and print the summary. Blocks; run it in the background:
#
#   nohup bench/flag_sweep.sh MACHINE [NCYC] [REPEATS] > bench/logs/sweep.log 2>&1 &
#
# flag_variants.txt lines: <toolchain> <variant> <complete compiler flags>
# Executables: <machine>/tigris_ncr_<physics>-fft-<toolchain>-<variant>.exe (build_tigress.sh
# --cxxflags=... --exe_suffix=<variant>); results carry variant=<variant>.
#
# env PHYSICS_LIST : physics to sweep [default: "mhd crmhd"]
# env LANES        : parallel build lanes [default: 3]. Lane i builds in a detached git
#                    worktree $HOME/tigris/.worktrees/build-lane-<i> at the commit of
#                    $SRCDIR (created if missing), so builds do not share a source tree.
# env ONLY         : regex on "<toolchain> <variant>" to restrict the sweep
# env SKIP_BUILD=1 : only submit (executables already built)
# env SRCDIR       : reference worktree [default: $HOME/tigris/.worktrees/ncr-cr-coupling]
MACHINE=${1:?usage: $0 MACHINE [NCYC] [REPEATS]}
NCYC=${2:-200}
REPEATS=${3:-1}
PHYSICS_LIST=${PHYSICS_LIST:-mhd crmhd}
LANES=${LANES:-3}
SRCDIR=${SRCDIR:-$HOME/tigris/.worktrees/ncr-cr-coupling}

BENCHDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NCR_DIR="$(dirname "$BENCHDIR")"
VFILE=$NCR_DIR/$MACHINE/flag_variants.txt
[ -f "$VFILE" ] || { echo "missing $VFILE"; exit 1; }
source "$NCR_DIR/$MACHINE/env.sh"

# variant list: "tc|variant|flags"
mapfile -t VARS < <(grep -vE '^\s*(#|$)' "$VFILE" | awk '{tc=$1; v=$2; $1=""; $2=""; sub(/^ +/,""); print tc "|" v "|" $0}' \
    | { if [ -n "$ONLY" ]; then grep -E "$ONLY"; else cat; fi; })
echo "$(date) sweep: ${#VARS[@]} variants x ($PHYSICS_LIST), $REPEATS repeat(s), $NCYC cycles"

if [ "${SKIP_BUILD:-0}" != "1" ]; then
    COMMIT=$(git -C "$SRCDIR" rev-parse HEAD)
    REPO=$(git -C "$SRCDIR" rev-parse --path-format=absolute --git-common-dir)
    REPO=${REPO%/.git}
    for i in $(seq "$LANES"); do
        lane=$REPO/.worktrees/build-lane-$i
        if [ ! -d "$lane" ]; then
            git -C "$REPO" worktree add --detach "$lane" "$COMMIT" >/dev/null
        else
            git -C "$lane" checkout -q --detach "$COMMIT"
        fi
    done
    # round-robin the (variant, physics) builds over the lanes
    JOBS=()
    for v in "${VARS[@]}"; do for p in $PHYSICS_LIST; do JOBS+=("$v|$p"); done; done
    for i in $(seq "$LANES"); do
        (
            lane=$REPO/.worktrees/build-lane-$i
            for ((k = i - 1; k < ${#JOBS[@]}; k += LANES)); do
                IFS='|' read -r tc var flags phys <<< "${JOBS[$k]}"
                log=$BENCHDIR/logs/build-$phys-$tc-$var.log
                if bash "$NCR_DIR/build_tigress.sh" --machine="$MACHINE" --cc="$tc" --physics="$phys" \
                        --srcdir="$lane" --exe_suffix="$var" --cxxflags="$flags" > "$log" 2>&1; then
                    echo "built $phys $tc-$var (lane $i)"
                else
                    echo "BUILD FAILED $phys $tc-$var (lane $i): $log"
                fi
            done
        ) &
    done
    wait
fi

MAXJ=${SLURM_MAX_JOBS:-5}
IDS=()
for rep in $(seq "$REPEATS"); do
    for v in "${VARS[@]}"; do
        IFS='|' read -r tc var _ <<< "$v"
        for p in $PHYSICS_LIST; do
            [ -x "$NCR_DIR/$MACHINE/tigris_ncr_${p}-fft-${tc}-${var}.exe" ] || { echo "skip $p $tc-$var: no exe"; continue; }
            until [ "$(squeue -h -u "$USER" $SLURM_QUEUE_FILTER | wc -l)" -lt "$MAXJ" ]; do sleep 30; done
            out=$(VARIANT=$var "$BENCHDIR/submit.sh" "$MACHINE" "$p" "$tc" "$NCYC")
            echo "$out" | tail -1
            IDS+=("$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+$')")
        done
    done
done
ids=$(IFS=,; echo "${IDS[*]}")
[ -n "$ids" ] && until [ -z "$(squeue -h -j "$ids" 2>/dev/null)" ]; do sleep 30; done
echo "$(date) sweep done"
python3 "$BENCHDIR/summarize.py" "$BENCHDIR/results/$MACHINE.txt"
