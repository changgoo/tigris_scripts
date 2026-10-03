#!/bin/bash
# Submit the full benchmark matrix for a machine: every toolchain in env.sh x physics x
# repeats, keeping at most SLURM_MAX_JOBS of your jobs queued (QOS submit limits).
# Blocks until everything is submitted, so run it in the background:
#
#   nohup bench/run_matrix.sh MACHINE [NCYC] [REPEATS] [PHYSICS...] > bench/logs/matrix.log 2>&1 &
#
# Defaults: NCYC=200, REPEATS=1, PHYSICS="mhd crmhd". Toolchains whose executable is
# missing are skipped with a warning. TOOLCHAINS="a b" in the environment restricts the set.
# Waits for the submitted jobs to finish, then prints the summary table.
MACHINE=${1:?usage: $0 MACHINE [NCYC] [REPEATS] [PHYSICS...]}
NCYC=${2:-200}
REPEATS=${3:-1}
shift 3 2>/dev/null || shift $#
PHYSICS_LIST=${*:-mhd crmhd}

BENCHDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NCR_DIR="$(dirname "$BENCHDIR")"
ONLY_TC=$TOOLCHAINS
source "$NCR_DIR/$MACHINE/env.sh"
TCS=${ONLY_TC:-$TOOLCHAINS}
MAXJ=${SLURM_MAX_JOBS:-5}

njobs() { squeue -h -u "$USER" | wc -l; }
JOBS=()
for rep in $(seq "$REPEATS"); do
    for phys in $PHYSICS_LIST; do
        for tc in $TCS; do
            if [ ! -x "$NCR_DIR/$MACHINE/tigris_ncr_${phys}-fft-${tc}.exe" ]; then
                echo "skip $phys $tc: executable missing"; continue
            fi
            until [ "$(njobs)" -lt "$MAXJ" ]; do sleep 30; done
            out=$("$BENCHDIR/submit.sh" "$MACHINE" "$phys" "$tc" "$NCYC")
            echo "$out"
            JOBS+=("$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+$')")
        done
    done
done

ids=$(IFS=,; echo "${JOBS[*]}")
[ -n "$ids" ] && until [ -z "$(squeue -h -j "$ids" 2>/dev/null)" ]; do sleep 30; done
python3 "$BENCHDIR/summarize.py" "$BENCHDIR/results/$MACHINE.txt"
