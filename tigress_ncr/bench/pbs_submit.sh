#!/bin/bash
# Bundle TIGRESS-NCR benchmark runs into ONE PBS job (PBS machines, e.g. athena).
#
#   bench/pbs_submit.sh MACHINE [--submit] [--workload=rst|fresh] [--lanes=N] [--ncyc=N] [--repeats=N] [--per-run=MIN]
#                       [--nodes-per-run=N] TASK...
#
# TASK = [<workload>/]<physics>:<toolchain>[:<variant>][:<overrides with commas>],
#        e.g. mhd:gcc, crmhd:aocc:preset-v512, rst/crmhd:gcc::gravity/solve_grav_hyperbolic_dt=true
# Shorthands: "matrix" = every toolchain in env.sh x {mhd, crmhd};
#             "sweep"  = every line of <machine>/flag_variants.txt x {mhd, crmhd}.
#
# --workload: rst (default) restarts the 8 pc checkpoints (384 ranks); fresh starts
# athinput.tigress_ncr in the 512-block 8 pc box (see tigress_ncr_8pc_bench.pbs).
# Without --submit it only prints the plan (task list, nodes, walltime, SBU estimate) and
# the qsub command: the user confirms before anything is submitted.
# The job (tigress_ncr_8pc_bench.pbs) splits its nodes into LANES lanes of
# 2 nodes (--nodes-per-run: more, for scaling probes; ranks per node = ranks / nodes) and runs LANES tasks at a time. Walltime = ceil(tasks/lanes) x
# per-run minutes + 5. PBS charges the wall time actually used.
# MPI tuning variables (MPICH_*, FI_*) set in the calling shell are passed to every run and
# recorded in opts; so is LAUNCH_OPTS (extra mpiexec options). ONLY=<regex> filters tasks.
set -e
MACHINE=${1:?usage: $0 MACHINE [--submit] [--lanes=N] [--ncyc=N] [--repeats=N] TASK...}
shift
SUBMIT=0; WORKLOAD=rst; LANES=""; NCYC=200; REPEATS=1; PER_RUN=4
SPECS=()
for a in "$@"; do
    case "$a" in
        --submit) SUBMIT=1 ;;
        --workload=*) WORKLOAD=${a#*=} ;;
        --lanes=*) LANES=${a#*=} ;;
        --ncyc=*) NCYC=${a#*=} ;;
        --repeats=*) REPEATS=${a#*=} ;;
        --per-run=*) PER_RUN=${a#*=} ;;
        --nodes-per-run=*) NPR_OPT=${a#*=} ;;
        *) SPECS+=("$a") ;;
    esac
done

BENCHDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NCR_DIR="$(dirname "$BENCHDIR")"
MPIENV=$(env | grep -E '^(MPICH_|FI_)' | grep -v '^MPICH_DIR=' | sort | tr '\n' ' ' || true)
source "$NCR_DIR/$MACHINE/env.sh"
case "$WORKLOAD" in rst) NR=384 ;; fresh) NR=512 ;; *) echo "unknown workload $WORKLOAD"; exit 1 ;; esac
NPR=${NPR_OPT:-$(( (512 + CORES_PER_NODE - 1) / CORES_PER_NODE ))}   # default: lanes fit the larger workload (fresh, 512 ranks)

TASKS=()
for rep in $(seq "$REPEATS"); do
    for s in "${SPECS[@]}"; do
        case "$s" in
            matrix)
                for p in mhd crmhd; do for tc in $TOOLCHAINS; do TASKS+=("$WORKLOAD $p $tc default $NCYC"); done; done ;;
            sweep)
                while read -r tc var _; do
                    for p in mhd crmhd; do TASKS+=("$WORKLOAD $p $tc $var $NCYC"); done
                done < <(grep -vE '^\s*(#|$)' "$NCR_DIR/$MACHINE/flag_variants.txt") ;;
            */*)   # <workload>/<physics>:<toolchain>[:...] overrides --workload for one task
                IFS=: read -r p tc var ovr <<< "${s#*/}"
                TASKS+=("${s%%/*} $p $tc ${var:-default} $NCYC ${ovr//,/ }") ;;
            *)
                IFS=: read -r p tc var ovr <<< "$s"
                TASKS+=("$WORKLOAD $p $tc ${var:-default} $NCYC ${ovr//,/ }") ;;
        esac
    done
done
[ -n "$ONLY" ] && mapfile -t TASKS < <(printf '%s\n' "${TASKS[@]}" | grep -E "$ONLY")
[ ${#TASKS[@]} -gt 0 ] || { echo "no tasks"; exit 1; }

missing=0
for t in "${TASKS[@]}"; do
    read -r _ p tc var _ <<< "$t"
    sfx=""; [ "$var" != default ] && sfx=-$var
    exe=tigris_ncr_${p}-fft-${tc}${sfx}.exe
    [ -x "$NCR_DIR/$MACHINE/$exe" ] || { echo "missing $MACHINE/$exe"; missing=1; }
done
for p in mhd crmhd; do
    v=BENCH_RST_$p
    printf '%s\n' "${TASKS[@]}" | grep -q "^rst $p " && { [ -f "$BENCH_CACHE/${!v}" ] || { echo "missing checkpoint $BENCH_CACHE/${!v}"; missing=1; }; }
done

NT=${#TASKS[@]}
: "${LANES:=$NT}"
(( LANES > NT )) && LANES=$NT
NODES=$(( LANES * NPR ))
ROUNDS=$(( (NT + LANES - 1) / LANES ))
WMIN=$(( ROUNDS * PER_RUN + 5 ))
WALL=$(printf '%02d:%02d:00' $((WMIN / 60)) $((WMIN % 60)))
SBU_MAX=$(python3 -c "print(f'{$NODES * $WMIN / 60 * $SBU_RATE:.1f}')")
SBU_EST=$(python3 -c "print(f'{$NODES * ($ROUNDS * $PER_RUN * 0.75 + 2) / 60 * $SBU_RATE:.1f}')")

echo "tasks ($NT):"; printf '  %s\n' "${TASKS[@]}"
echo "workload=$WORKLOAD ($NR ranks/run), lanes=$LANES x $NPR nodes = $NODES nodes, rounds=$ROUNDS, walltime=$WALL, queue=$PBS_QUEUE"
echo "SBU: <= $SBU_MAX if it uses the full walltime; expected ~$SBU_EST"
echo "MPI env: ${MPIENV:-none}  LAUNCH_OPTS: ${LAUNCH_OPTS:-none}"
[ $missing == 0 ] || { echo "not submitting: missing files"; exit 1; }

QSUB=(qsub -q "$PBS_QUEUE" -W group_list="$PBS_GROUP"
      -l "select=$NODES:ncpus=$CORES_PER_NODE:mpiprocs=$(( (NR + NPR - 1) / NPR )):model=$PBS_MODEL"
      -l place=scatter:excl -l walltime="$WALL" -o "$BENCHDIR/logs/")
if [ $SUBMIT != 1 ]; then
    echo "dry run; to submit: $0 $MACHINE --submit ${*/--submit/}"
    echo "  ${QSUB[*]} tigress_ncr_8pc_bench.pbs"
    exit 0
fi

TASKDIR=$SCRATCH_BASE/tigress_ncr/bench/tasks-$(date +%Y%m%d-%H%M%S)
mkdir -p "$TASKDIR" "$BENCHDIR/logs"
printf '%s\n' "${TASKS[@]}" > "$TASKDIR/tasks.txt"
cd "$BENCHDIR"
BENCH_MPIENV=$MPIENV NODES_PER_RUN=$NPR KEEP_RST=${KEEP_RST:-0}
declare -p MACHINE NCR_DIR NODES_PER_RUN BENCH_MPIENV KEEP_RST > "$TASKDIR/job.env"
[ -n "$LAUNCH_OPTS" ] && declare -p LAUNCH_OPTS >> "$TASKDIR/job.env"
"${QSUB[@]}" -v "TASKDIR=$TASKDIR" tigress_ncr_8pc_bench.pbs
echo "task list: $TASKDIR/tasks.txt"
