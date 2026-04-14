#!/usr/bin/env python3
"""Generate NASA Athena (tur_ath) PBS scripts for tigress_classic runs."""

import argparse
import sys

# ---------------------------------------------------------------------------
# Resolution presets (mesh + meshblock parameters passed to Athena++)
# ---------------------------------------------------------------------------
RESOLUTIONS = {
    "lowres": (
        "meshblock/nx1=16 meshblock/nx2=16 meshblock/nx3=16 "
        "mesh/nx1=64 mesh/nx2=64 mesh/nx3=512 "
        "mesh/x1min=-512 mesh/x1max=512 mesh/x2min=-512 mesh/x2max=512 "
        "mesh/x3min=-4096 mesh/x3max=4096"
    ),
    "medres": (
        "mesh/nx1=128 mesh/nx2=128 mesh/nx3=1024 "
        "mesh/x3min=-4096 mesh/x3max=4096"
    ),
    "highres": (
        "mesh/nx1=256 mesh/nx2=256 mesh/nx3=2048 "
        "meshblock/nx1=64 meshblock/nx2=64 meshblock/nx3=64 "
        "mesh/x3min=-4096 mesh/x3max=4096"
    ),
    "bigbox": (
        "mesh/nx1=256 mesh/nx2=256 mesh/nx3=1024 "
        "meshblock/nx1=32 meshblock/nx2=32 meshblock/nx3=32 "
        "mesh/x1min=-1024 mesh/x1max=1024 mesh/x2min=-1024 mesh/x2max=1024 "
        "mesh/x3min=-4096 mesh/x3max=4096"
    ),
}

# Human-readable resolution label used in RUNDIR names
RES_LABEL = {
    "lowres": "16pc",
    "medres": "8pc",
    "highres": "4pc",
    "bigbox": "8pc_big",
}


def walltime_to_seconds(wt: str) -> int:
    parts = wt.split(":")
    h, m, s = int(parts[0]), int(parts[1]), int(parts[2])
    return h * 3600 + m * 60 + s


def seconds_to_walltime(secs: int) -> str:
    h = secs // 3600
    m = (secs % 3600) // 60
    s = secs % 60
    return f"{h:02d}:{m:02d}:{s:02d}"


def compute_tlim(walltime: str, margin_min: int = 30) -> str:
    """Return Athena++ -t limit = PBS walltime minus margin."""
    secs = walltime_to_seconds(walltime) - margin_min * 60
    if secs <= 0:
        raise ValueError(f"walltime {walltime!r} is too short for a {margin_min}-min margin")
    return seconds_to_walltime(secs)


def build_extra_params(args) -> str:
    physics_is_cr = args.physics.startswith("cr")
    selfg_dt = physics_is_cr  # true for crmhd, false for mhd
    parts = [
        "perturbation/rseed=1",
        f"particle1/fgas={args.fgas}",
        f"mesh/mhd_outflow_bc={args.mhd_bc}",
        f"problem/beta0={args.beta}",
        "particle1/r_return=100",
        "hydro/dfloor=1.e-6",
        "hydro/pfloor=1.e-6",
        f"gravity/solve_grav_hyperbolic_dt={str(selfg_dt).lower()}",
    ]
    if args.physics == "crmhd":
        parts += [
            "cr/ecfloor=1.e-18",
            f"mesh/cr_outflow_bc={args.cr_bc}",
        ]
    return " ".join(parts)


def generate(args) -> str:
    nodes = args.nodes
    nprocs = nodes * 256
    res_label = RES_LABEL[args.resolution]
    res_params = RESOLUTIONS[args.resolution]
    tlim_run = compute_tlim(args.walltime)

    # Run directory
    rundir_name = f"{args.physics}_{res_label}_shear"
    if args.rundir_suffix:
        rundir_name += f"-{args.rundir_suffix}"
    rundir = f"/nobackup/$USER/tigress_classic/{rundir_name}"

    # Script filename (for self-copy on restart)
    script_name = f"tigress_classic-{args.physics}-{res_label}"
    if args.rundir_suffix:
        script_name += f"-{args.rundir_suffix}"
    script_name += ".pbs"

    # params line
    params_parts = [
        "job/problem_id=$PID",
        f"time/tlim={args.sim_tlim}",
    ]
    if args.nlim is not None:
        params_parts.append(f"time/nlim={args.nlim}")
    params_parts += [
        f"$mesh_params",
        "cooling/coolftn_file=$COOL_TBL",
        "feedback/pop_synth_file=$POPSYNTH_TBL",
    ]
    params_str = " ".join(params_parts)

    extra_params_str = build_extra_params(args)

    # snapshot MPI ranks: 16 ranks per node
    snap_ranks = nodes * 16

    lines = [
        f"#PBS -q {args.queue}",
        f"#PBS -l select={nodes}:ncpus=256:mpiprocs=256:model=tur_ath",
        f"#PBS -l walltime={args.walltime}",
        "#PBS -m abe",
        f"#PBS -M {args.email}",
        "",
        'usage="Usage: qsub -v STARTFLAG=(-r or -i),RSTNUM=final $0"',
        "",
        "# Validate required arguments",
        'valid_flag="-i -r"',
        '[[ -z "$STARTFLAG" || ! $valid_flag =~ $STARTFLAG ]] && echo "$usage" && exit 1',
        "",
        "# Set default RSTNUM",
        '[[ -z "$RSTNUM" ]] && RSTNUM=final',
        "",
        'echo "submitting a job: with STARTFLAG=$STARTFLAG RSTNUM=$RSTNUM"',
        "",
        f"NPROCS={nprocs}",
        f"tlim={tlim_run}",
        "",
        "module purge",
        "module load PrgEnv-cray cray-pals cray-libpals craype-x86-turin perftools-base cray-hdf5-parallel cray-fftw",
        "module switch PrgEnv-cray PrgEnv-gnu",
        "",
        f"fgas={args.fgas}",
        "",
        "# Define problem and paths",
        f"physics={args.physics}",
        "prob=tigress_classic",
        "PID=TIGRESS",
        "SRCDIR=$HOME/tigris",
        "SCRIPTDIR=$HOME/tigris_scripts/${prob}/nasa_athena",
        f'SCRIPT={script_name}',
        "",
        "# Define executable and input files",
        "EXE=tigris_${physics}.exe",
        "INPUT=athinput.$prob",
        f"RUNDIR={rundir}",
        "",
        "TBLDIR=$SRCDIR/inputs/tables",
        'COOL_TBL="tigress_coolftn.txt"',
        'POPSYNTH_TBL="Z014_GenevaV00.txt"',
        "",
        f'mesh_params="{res_params}"',
        "",
        f'params="{params_str}"',
        f'extra_params="{extra_params_str}"',
        'rst_params="output1/file_number=0 output5/file_number=0"',
        "",
        "# Print the run directory",
        "echo $RUNDIR",
        "",
        "# Create run directory if it doesn't exist, or clean it if it does",
        "if [ -d $RUNDIR ] ; then",
        "    echo \"directory exists\"",
        "    if [[ $STARTFLAG != \"-r\" ]]; then",
        "        echo \"cleaning up\"",
        "        rm -rf $RUNDIR/*",
        "    fi",
        "else",
        "    mkdir -p $RUNDIR",
        "fi",
        "",
        "cd $RUNDIR",
        "echo $params $extra_params",
        "",
        "set -o pipefail",
        "",
        "[ ! -f \"$EXE\" ]         && cp -p ${SCRIPTDIR}/$EXE .",
        "[ ! -f \"$COOL_TBL\" ]    && cp -p \"$TBLDIR/$COOL_TBL\" .",
        "[ ! -f \"$POPSYNTH_TBL\" ] && cp -p \"$TBLDIR/$POPSYNTH_TBL\" .",
        "",
        "RSTINPUT=$PID.$RSTNUM.rst",
        "",
        "if [[ ! -f \"$RSTINPUT\" && \"$STARTFLAG\" == \"-i\" ]]; then",
        "    echo \"Starting fresh\"",
        "    cp $0 ./$SCRIPT",
        "    cp ${SCRIPTDIR}/../$INPUT .",
        "    mpiexec -np $NPROCS ./$EXE -i $INPUT -t $tlim $params $extra_params \\",
        "        1> \"$RUNDIR/out.txt\" 2> \"$RUNDIR/err.txt\"",
        "else",
        "    echo \"Restarting\"",
        "    rstnum=$(ls out.*.txt 2>/dev/null | wc -l)",
        "    if [[ $RSTNUM == \"final\" ]]; then",
        "        mpiexec -np $NPROCS ./$EXE -r $RSTINPUT -t $tlim \\",
        "            1> \"$RUNDIR/out.r${rstnum}.txt\" 2> \"$RUNDIR/err.r${rstnum}.txt\"",
        "    else",
        "        mpiexec -np $NPROCS ./$EXE -r $RSTINPUT -t $tlim $rst_params \\",
        "            1> \"$RUNDIR/out.r${rstnum}.txt\" 2> \"$RUNDIR/err.r${rstnum}.txt\"",
        "    fi",
        "fi",
        "",
        "EXITCODE=$?",
        "echo \"EXITCODE = $EXITCODE\"",
        "",
        "set +o pipefail",
        "",
        "if [[ $EXITCODE -eq 3 ]]; then",
        "    echo \"Resubmitting\"",
        "    qsub -v STARTFLAG=-r,RSTNUM=final $SCRIPT",
        "fi",
        "",
        "# Make quick snapshots",
        "cd $RUNDIR",
        "PYTHONDIR=$HOME/pyathena_tigris",
        "export PYTHONPATH=$PYTHONDIR:$PYTHONPATH",
        "pythonscript=$HOME/TIGRESS-CR/python/plot_slices.py",
        f"mpiexec --ppn 16 -n {snap_ranks} python -m mpi4py $pythonscript `pwd`",
    ]

    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(
        description="Generate a tigress_classic PBS script for NASA Athena (tur_ath).",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--physics", choices=["mhd", "crmhd"], required=True,
                        help="Physics module")
    parser.add_argument("--queue", default="long",
                        help="PBS queue (devel, long, normal, ...)")
    parser.add_argument("--nodes", type=int, default=2,
                        help="Number of nodes (256 cores each → NPROCS = nodes*256)")
    parser.add_argument("--walltime", default="48:00:00",
                        help="PBS walltime HH:MM:SS; Athena++ -t limit is set to walltime-30min")
    parser.add_argument("--resolution", choices=list(RESOLUTIONS), default="highres",
                        help="Mesh resolution preset")
    parser.add_argument("--rundir-suffix", default="",
                        help="Extra suffix appended to the run directory and script name")
    parser.add_argument("--beta", type=float, default=1.0,
                        help="problem/beta0")
    parser.add_argument("--fgas", type=float, default=0.9,
                        help="particle1/fgas")
    parser.add_argument("--mhd-bc", default="diode",
                        help="mesh/mhd_outflow_bc")
    parser.add_argument("--cr-bc", default="lngrad_out",
                        help="mesh/cr_outflow_bc (crmhd only)")
    parser.add_argument("--sim-tlim", type=int, default=500,
                        help="time/tlim for the simulation (Myr)")
    parser.add_argument("--nlim", type=int, default=None,
                        help="time/nlim cycle limit (omitted if not set)")
    parser.add_argument("--email", default="changgookim@gmail.com",
                        help="PBS mail address")
    parser.add_argument("--output", "-o", default=None,
                        help="Write to file instead of stdout")

    args = parser.parse_args()

    script = generate(args)

    if args.output:
        with open(args.output, "w") as f:
            f.write(script)
        print(f"Written to {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(script)


if __name__ == "__main__":
    main()
