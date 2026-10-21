#!/bin/bash
#SBATCH --job-name=osu-net
#SBATCH -N 2
#SBATCH --exclusive
#SBATCH --time=00:20:00
#SBATCH --output=logs/osu-net-%j.out
#
# Slurm twin of osu_net.pbs (see there): OSU micro-benchmarks between 2 nodes with a
# machine's toolchain, for comparison with Athena's FFT-gravity remap performance.
#
#   cd bench && sbatch --partition=<p> --account=<a> --ntasks-per-node=<cores per node> \
#       --export=ALL,MACHINE=<machine>,TC=<toolchain>,OSU_DIR=<osu install prefix> osu_net.slurm
#
# Many pairs (osu_mbw_mr) run with one rank per core; a second run with half the cores
# shows whether the message rate scales with the number of pairs. The intra-node pair sits
# on two CCDs of socket 0, as on Athena. Output: bench/logs/osu-<job>/ (summarize with
# osu_summary.py).

NCR_DIR=${NCR_DIR:-$HOME/tigris_scripts/tigress_ncr}
source "$NCR_DIR/${MACHINE:?set MACHINE}/env.sh" || exit 1
load_toolchain "${TC:-$DEFAULT_TOOLCHAIN}" > /dev/null 2>&1 || exit 1
export OMP_NUM_THREADS=1
P2P=${OSU_DIR:?set OSU_DIR}/libexec/osu-micro-benchmarks/mpi/pt2pt
COLL=$OSU_DIR/libexec/osu-micro-benchmarks/mpi/collective
OUT=$NCR_DIR/bench/logs/osu-$SLURM_JOB_ID
mkdir -p "$OUT"
PPN=$CORES_PER_NODE
CCD=$(( CORES_PER_NODE / 16 ))   # cores per CCD (16 CCDs per node on both Turin machines)

{
    date; echo "nodes: $SLURM_JOB_NODELIST  toolchain: ${TC:-$DEFAULT_TOOLCHAIN}"
    module -t list 2>&1 | tr '\n' ' '; echo
    echo "THP: $(cat /sys/kernel/mm/transparent_hugepage/enabled)"
    command -v ibv_devinfo > /dev/null && ibv_devinfo -l
    command -v fi_info > /dev/null && fi_info --version | head -2
} > "$OUT/env.txt" 2>&1

run() {   # run <name> <ranks per node> <exe> [args...]: one test on both nodes
    local name=$1 ppn=$2; shift 2
    echo "$(date +%T) $name"
    srun -N 2 -n $((2 * ppn)) --ntasks-per-node="$ppn" --cpu-bind=cores "$@" \
        > "$OUT/$name.txt" 2>&1
    echo "rc=$?" >> "$OUT/$name.txt"
}

M=-m1024:4194304   # one pair
MM=-m1024:1048576  # many pairs: the remaps send <= 128 KB
run bw_inter   1 "$P2P/osu_bw" $M
run bibw_inter 1 "$P2P/osu_bibw" $M
echo "$(date +%T) bw_intra"
srun -N 1 -n 2 --cpu-bind=map_cpu:0,$CCD "$P2P/osu_bw" $M > "$OUT/bw_intra.txt" 2>&1
echo "rc=$?" >> "$OUT/bw_intra.txt"
# many pairs: rank i on node 0 talks to rank i+ppn on node 1
run "mbw_mr_$PPN" "$PPN" "$P2P/osu_mbw_mr" $MM
run "mbw_mr_$((PPN / 2))" $((PPN / 2)) "$P2P/osu_mbw_mr" $MM
# all-to-all over both nodes at the remap message sizes
run "alltoall_$PPN" "$PPN" "$COLL/osu_alltoall" -m4096:131072 -i20 -x5
echo "$(date +%T) done; output in $OUT"
