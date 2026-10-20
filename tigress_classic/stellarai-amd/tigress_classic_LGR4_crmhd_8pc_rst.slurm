#!/bin/bash
#SBATCH --job-name=LGR4-cr8pc
#SBATCH --account=eost
#SBATCH --partition=cpu
#SBATCH -N 8
#SBATCH --ntasks-per-node=96   # 768 ranks = 768 meshblocks (BlockFFT: 1 block/rank)
#SBATCH --exclusive
#SBATCH --time=24:00:00        # site maximum since 2026-10-07 (QOS medium); chains via -r
#SBATCH --mail-type=all
#SBATCH --mail-user=changgoo@princeton.edu
#SBATCH --output=LGR4-cr8pc-%j.out
#
# LGR4 CRMHD, 8 pc: continue the production run from t = 450 to t = 550 with the
# shear-face positivity limiter (hydro + CR, eps = 0.5; no synchronised boundary fix)
# and the numerical-addition history columns.
#   mesh 128x128x1536 over +-512 x +-512 x +-6144 pc, 32^3 blocks -> 768 blocks
#   cost (crmhd-sync test with the sync fix, 2026-10-06): dt = 1.2e-4 (CR-limited), 1224 s per unit time
#
# Usage:
#   sbatch tigress_classic_LGR4_crmhd_8pc_rst.slurm        # first segment, from $SRC_RST
#   sbatch tigress_classic_LGR4_crmhd_8pc_rst.slurm -r     # continue from the run directory
#   env SUFFIX : exe suffix, tigris_crmhd_duale-blockfft-gcc-<SUFFIX>.exe [default: run, branch lgr4-crmhd-run]
#   env CC     : toolchain [default: gcc]
# Stops on the walltime soft limit (exit code 3) and resubmits itself with -r.
# After every segment it submits tigress_classic_postproc.slurm (quick-look frames + movies;
#   redraws all frames each time).

STARTFLAG=$1
CC=${CC:-gcc}
SUFFIX=${SUFFIX:-run}
TLIM=550

PID=TIGRESS
SLURMDIR=$HOME/tigris_scripts/tigress_classic/stellarai-amd
SCRIPT=tigress_classic_LGR4_crmhd_8pc_rst.slurm
TBLDIR=$HOME/tigris/inputs/tables
SRC_RST=/scratch/gpfs/EOST/$USER/tigress_classic_sync/rst/crmhd.00014.rst   # t = 450
RUNDIR=/scratch/gpfs/EOST/$USER/tigress_classic/LGR4-crmhd-8pc-t450
TWALL=23:30:00  # athena soft limit, inside the slurm limit

source "$SLURMDIR/env.sh"
load_toolchain "$CC" || exit 1
EXE=tigris_crmhd_duale-blockfft-${CC}-${SUFFIX}.exe
if [ ! -x "$SLURMDIR/$EXE" ]; then
    echo "ERROR: executable not found: $SLURMDIR/$EXE"
    echo "  build: build_tigress.sh --machine=stellarai-amd --cc=$CC --physics=crmhd_duale --grav=blockfft --worktree=<branch> --exe_suffix=$SUFFIX"
    exit 1
fi

if [[ $STARTFLAG != "-r" ]]; then
    if compgen -G "$RUNDIR/*.rst" > /dev/null; then
        echo "ERROR: $RUNDIR holds restart files; use -r"; exit 1
    fi
    mkdir -p "$RUNDIR"
fi
cd "$RUNDIR" || exit 1
cp "$SLURMDIR/$SCRIPT" "$SLURMDIR/$EXE" "$SLURMDIR/${EXE%.exe}.buildinfo" .
cp "$TBLDIR/tigress_coolftn.txt" "$TBLDIR/Z014_GenevaV00.txt" .

# Switches that are not in the t = 450 checkpoint's input.
cat > athinput.restart_add <<EOF
<hydro>
shear_flux_limiter     = true
shear_flux_limiter_eps = 0.5
<cr>
shear_flux_limiter     = true
shear_flux_limiter_eps = 0.5
EOF

set -o pipefail
if [[ $STARTFLAG != "-r" ]]; then
    # Production outputs of the checkpoint are kept (hst/phase_hst 0.01, prim/parbin/zprof 1,
    # uov 10, rst 25); history files start fresh in this directory.
    echo "Restarting from $SRC_RST (t = 450)"
    srun --cpu-bind=cores "./$EXE" -r "$SRC_RST" -i athinput.restart_add -t $TWALL \
        time/tlim=$TLIM output1/file_number=0 output5/file_number=0 \
        1> out.txt 2> err.txt
else
    RSTINPUT=$PID.final.rst
    [ -f "$RSTINPUT" ] || RSTINPUT=$(ls -1 $PID.[0-9]*.rst 2>/dev/null | sort | tail -1)
    if [ -z "$RSTINPUT" ]; then echo "ERROR: no restart file in $RUNDIR"; exit 1; fi
    rstnum=$(ls out*.txt 2>/dev/null | wc -l)
    echo "Restarting from $RUNDIR/$RSTINPUT"
    srun --cpu-bind=cores "./$EXE" -r "$RSTINPUT" -i athinput.restart_add -t $TWALL \
        1> out.r${rstnum}.txt 2> err.r${rstnum}.txt
fi
EXITCODE=$?
set +o pipefail
echo "EXITCODE = $EXITCODE"

if [[ $EXITCODE -eq 3 ]]; then
    echo "Resubmitting"
    cd "$SLURMDIR" && CC=$CC SUFFIX=$SUFFIX sbatch "$SCRIPT" -r
fi

# Quick-look figures and movies of everything written so far.
PPNAME=pp-$(basename "$RUNDIR")   # wait for any postproc of this run still queued or running
PPDEP=$(squeue -h -u $USER -n $PPNAME -o %i | paste -sd: -)
cd "$SLURMDIR" && sbatch -J $PPNAME ${PPDEP:+--dependency=afterany:$PPDEP} --ntasks-per-node=24 tigress_classic_postproc.slurm "$RUNDIR"
