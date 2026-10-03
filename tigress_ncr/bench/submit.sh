#!/bin/bash
# Submit one TIGRESS-NCR benchmark job with the machine's slurm settings.
#
#   bench/submit.sh MACHINE PHYSICS TOOLCHAIN [NCYC] [extra overrides...]
#
# Reads partition/account/cores-per-node from <machine>/env.sh, the meshblock count from
# the checkpoint header, and requests one rank per meshblock on whole nodes.
# MPI tuning variables (OMPI_MCA_*, I_MPI_*, UCX_*) set in the calling shell are passed to
# the job and recorded as the run's opts; so is SRUN_OPTS. Other env knobs: RSTFILE,
# KEEP_RST, BENCH_TIME (slurm --time, default 00:30:00). See BENCHMARK_SPEC.md.
set -e
MACHINE=${1:?usage: $0 MACHINE PHYSICS TOOLCHAIN [NCYC] [overrides...]}
PHYSICS=${2:?usage: $0 MACHINE PHYSICS TOOLCHAIN [NCYC] [overrides...]}
TC=${3:?usage: $0 MACHINE PHYSICS TOOLCHAIN [NCYC] [overrides...]}

BENCHDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NCR_DIR="$(dirname "$BENCHDIR")"

# Tuning variables from the user's shell, captured before env.sh loads any modules.
MPIENV=$(env | grep -E '^(OMPI_MCA_|I_MPI_|UCX_)' | sort | tr '\n' ' ' || true)

source "$NCR_DIR/$MACHINE/env.sh"
[[ " $TOOLCHAINS " == *" $TC "* ]] || { echo "unknown toolchain $TC (one of: $TOOLCHAINS)"; exit 1; }
[ -x "$NCR_DIR/$MACHINE/tigris_ncr_${PHYSICS}-fft-${TC}.exe" ] || {
    echo "missing $MACHINE/tigris_ncr_${PHYSICS}-fft-${TC}.exe; build it with:"
    echo "  bash $NCR_DIR/build_tigress.sh --machine=$MACHINE --cc=$TC --physics=$PHYSICS --worktree=ncr-cr-coupling"
    exit 1; }

RSTVAR=BENCH_RST_$PHYSICS
RSTFILE=${RSTFILE:-${!RSTVAR}}
[ -f "$RSTFILE" ] || { echo "restart file not found: '$RSTFILE' (set $RSTVAR in env.sh)"; exit 1; }
read -r NR _ _ _ < <(python3 "$BENCHDIR/rst_info.py" "$RSTFILE")
NODES=$(( (NR + CORES_PER_NODE - 1) / CORES_PER_NODE ))

SB=(--partition="$SLURM_PARTITION" -N "$NODES" -n "$NR" --time="${BENCH_TIME:-00:30:00}")
[ -n "$SLURM_ACCOUNT" ] && SB+=(--account="$SLURM_ACCOUNT")
(( NR % NODES == 0 )) && SB+=(--ntasks-per-node=$(( NR / NODES )))
[ -n "$SLURM_EXTRA" ] && SB+=($SLURM_EXTRA)

mkdir -p "$BENCHDIR/logs"
cd "$BENCHDIR"
echo "sbatch ${SB[*]} tigress_ncr_8pc_bench.slurm $*   [${MPIENV:-no MPI env}${SRUN_OPTS:+ SRUN_OPTS=$SRUN_OPTS}]"
NCR_DIR="$NCR_DIR" RSTFILE="$RSTFILE" BENCH_MPIENV="$MPIENV" \
    sbatch "${SB[@]}" tigress_ncr_8pc_bench.slurm "$@"
