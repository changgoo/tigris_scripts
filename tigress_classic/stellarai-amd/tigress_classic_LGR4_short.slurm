#!/bin/bash
#SBATCH --job-name=LGR4-short
#SBATCH --account=eost
#SBATCH --partition=cpu
#SBATCH -N 2                   # node count
#SBATCH --ntasks-per-node=96   # 192 ranks = 192 meshblocks (1 block/rank)
#SBATCH --exclusive
#SBATCH --time=24:00:00
#SBATCH --mail-type=all
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=LGR4short-%j.out
#SBATCH --error=LGR4short-%j.err
#
# TIGRESS-classic LGR4 at 8 pc in a short box (|z| < 1536 pc) on stellarai-amd, from t = 0,
# to measure the shear-periodic boundary without any fix (hydro vs MHD).
#   128 x 128 x 384 cells over 1024 x 1024 x 3072 pc, 32^3 blocks
#   -> 4*4*12 = 192 blocks -> 192 ranks (1 block/rank) = 2 full nodes.
# Input: ../athinput.tigress_classic_LGR4_short (LGR4 production parameters; shear-face
# limiter and sync off; shear_flux_counters on; history at full precision).
# Executable: built from the tigris test branch shear-sync-test, which writes the boundary
# and control-plane diagnostics and the numerical-addition/flux/SN-mass budget columns:
#   build_tigress.sh --machine=stellarai-amd --physics=<hydro_duale|mhd_duale> \
#                    --grav=blockfft --worktree=shear-sync-test --exe_suffix=sbdiag
#
# Usage:
#   sbatch tigress_classic_LGR4_short.slurm <hydro|mhd|hydro_duale|mhd_duale> [-r|-i] [TAG]
#     -r  : restart from the newest restart file in the run directory (-i: fresh start)
#   env PARAMS  : extra input overrides for a fresh start, e.g.
#                 PARAMS="time/tlim=20 hydro/shear_flux_limiter=true" (with a TAG)
#   env CC      : toolchain [default: DEFAULT_TOOLCHAIN of env.sh]
#   env RUNBASE : parent of the run directory [default: $SCRATCH_BASE/tigress_classic]
# Chains itself via restart when it stops on the walltime soft limit (exit code 3).

PHYS=$1
STARTFLAG=$2
TAG=$3

SCRIPTDIR=$HOME/tigris_scripts/tigress_classic
SLURMDIR=$SCRIPTDIR/stellarai-amd
SCRIPT=tigress_classic_LGR4_short.slurm
source "$SLURMDIR/env.sh"
CC=${CC:-$DEFAULT_TOOLCHAIN}
load_toolchain "$CC" || exit 1

case "$PHYS" in
  hydro|mhd|hydro_duale|mhd_duale) ;;
  *) echo "ERROR: physics must be hydro, mhd, hydro_duale or mhd_duale (got '$PHYS')"
     exit 1 ;;
esac
EXE=tigris_${PHYS}-blockfft-${CC}-sbdiag.exe
EXEPATH=$SLURMDIR/$EXE
INPUT=$SCRIPTDIR/athinput.tigress_classic_LGR4_short
TBLDIR=$HOME/tigris/inputs/tables
PID=TIGRESS

RUNBASE=${RUNBASE:-$SCRATCH_BASE/tigress_classic}
RUNDIR=$RUNBASE/LGR4-short-8pc-${PHYS}${TAG}
echo "RUNDIR = $RUNDIR"
echo "EXE    = $EXEPATH"
[ -x "$EXEPATH" ] || { echo "ERROR: executable not found: $EXEPATH"; exit 1; }

if [ -d "$RUNDIR" ] && [[ $STARTFLAG != "-r" ]] && compgen -G "$RUNDIR/*.rst" > /dev/null; then
  echo "ERROR: $RUNDIR holds restart files; use -r, or move them away for a fresh start"
  exit 1
fi
mkdir -p "$RUNDIR" && cd "$RUNDIR"
cp "$SLURMDIR/$SCRIPT" .
cp "$EXEPATH" .
cp "$TBLDIR/tigress_coolftn.txt" "$TBLDIR/Z014_GenevaV00.txt" .

if [[ $STARTFLAG != "-r" ]]; then
  echo "Starting fresh"
  cp "$INPUT" .
  echo "PARAMS = $PARAMS"
  $MPI_LAUNCH "./$EXE" -i "$(basename "$INPUT")" -t 23:30:00 $PARAMS \
    1> out.txt 2> err.txt
else
  RST=$PID.final.rst
  [ -f "$RST" ] || RST=$(ls -1 $PID.[0-9]*.rst 2>/dev/null | sort | tail -1)
  [ -n "$RST" ] && [ -f "$RST" ] || { echo "ERROR: no restart file in $RUNDIR"; exit 1; }
  echo "Restarting from $RST"
  n=$(ls out*.txt 2>/dev/null | wc -l)
  $MPI_LAUNCH "./$EXE" -r "$RST" -t 23:30:00 1> out.r$n.txt 2> err.r$n.txt
fi
EXITCODE=$?
echo "EXITCODE = $EXITCODE"

# walltime soft limit: continue from the final restart
if [[ $EXITCODE -eq 3 ]]; then
  cd "$SLURMDIR" && CC=$CC RUNBASE=$RUNBASE sbatch "$SCRIPT" "$PHYS" -r "$TAG"
fi
