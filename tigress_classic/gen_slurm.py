#!/usr/bin/env python3
"""Generate tigress_classic Slurm job scripts for stellar, tiger, and anvil."""

import argparse
import sys

# ---------------------------------------------------------------------------
# Machine configuration
# ---------------------------------------------------------------------------
MACHINES = {
    "stellar": {
        "account": None,
        "partition": None,
        "cores_per_node": 96,
        "scratch": "/scratch/gpfs/$USER",
        "scriptdir_base": "$HOME/tigris_scripts/tigress_classic/stellar",
        "modules_icpx": (
            "module purge; module load anaconda3/2023.3 "
            "intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 "
            "hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10"
        ),
        "modules_gpp": (
            "module purge; module load anaconda3/2023.3 "
            "fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4"
        ),
        "modules_snap": (
            "module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; "
            "conda activate pyathena"
        ),
        "default_cc": "icpx",
    },
    "tiger": {
        "account": "eost",
        "partition": None,
        "cores_per_node": 112,
        "scratch": "/scratch/gpfs/EOST/$USER",
        "scriptdir_base": "$HOME/tigris_scripts/tigress_classic/tiger",
        "modules_icpx": (
            "module purge; module load anaconda3/2023.3 "
            "intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 "
            "hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10"
        ),
        "modules_gpp": (
            "module purge; module load anaconda3/2023.3 "
            "fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4"
        ),
        "modules_snap": (
            "module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; "
            "conda activate pyathena"
        ),
        "default_cc": "icpx",
    },
    "anvil": {
        "account": "phy240043",
        "partition": "wholenode",
        "cores_per_node": 128,
        "scratch": "$SCRATCH",
        "scriptdir_base": "$HOME/tigris_scripts/tigress_classic/anvil",
        "modules_run": (
            "module purge; module load gcc; module load openmpi; "
            "module load fftw hdf5"
        ),
        "modules_snap": (
            "module purge; module load anaconda openmpi; conda activate pyathena"
        ),
        "default_cc": "g++-simd",
    },
}

# ---------------------------------------------------------------------------
# Resolution presets
# ---------------------------------------------------------------------------
RESOLUTIONS = {
    "lowres": (
        "meshblock/nx1=16 meshblock/nx2=16 meshblock/nx3=16 "
        "mesh/nx1=64 mesh/nx2=64 mesh/nx3=512 "
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

RES_LABEL = {
    "lowres": "16pc",
    "medres": "8pc",
    "highres": "4pc",
    "bigbox": "8pc_big",
}


def walltime_to_seconds(wt):
    h, m, s = (int(x) for x in wt.split(":"))
    return h * 3600 + m * 60 + s


def seconds_to_walltime(secs):
    h, rem = divmod(secs, 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{s:02d}"


def compute_tlim(walltime, margin_min=30):
    secs = walltime_to_seconds(walltime) - margin_min * 60
    if secs <= 0:
        raise ValueError(f"walltime {walltime!r} too short for {margin_min}-min margin")
    return seconds_to_walltime(secs)


def module_block(machine, cc):
    """Return the module load line(s) for runtime."""
    mcfg = MACHINES[machine]
    if machine == "anvil":
        return mcfg["modules_run"]
    if cc.startswith("icpx"):
        return mcfg["modules_icpx"]
    return mcfg["modules_gpp"]


def generate(args):
    mcfg = MACHINES[args.machine]
    cc = args.cc or mcfg["default_cc"]
    physics_is_cr = args.physics.startswith("cr")
    selfg_dt = physics_is_cr  # true for crmhd, false for mhd
    nodes = args.nodes
    ntasks = nodes * mcfg["cores_per_node"]
    tlim_run = compute_tlim(args.walltime)
    res_label = RES_LABEL[args.resolution]
    res_params = RESOLUTIONS[args.resolution]
    scratch = mcfg["scratch"]
    scriptdir = mcfg["scriptdir_base"]

    # --- Script / run-directory name ---
    # Build a compact label: physics-resLabel-b{beta}-mhdbc_{mhdbc}[-crbc_{crbc}][-{suffix}]
    name_parts = [args.physics, res_label, f"b{args.beta}", f"mhdbc_{args.mhd_bc}"]
    if physics_is_cr:
        name_parts.append(f"crbc_{args.cr_bc}")
    if not args.shear:
        name_parts.append("noShear")
    if args.rundir_suffix:
        name_parts.append(args.rundir_suffix)
    run_label = "-".join(name_parts)
    script_name = f"tigress_classic_{args.physics}-{res_label}"
    if args.rundir_suffix:
        script_name += f"-{args.rundir_suffix}"
    script_name += ".slurm"

    rundir = f"{scratch}/tigress_classic/{run_label}"

    # --- Athena++ params ---
    params_parts = [
        "job/problem_id=$PID",
        f"time/tlim={args.sim_tlim}",
        "$mesh_params",
        "cooling/coolftn_file=$COOL_TBL",
        "feedback/pop_synth_file=$POPSYNTH_TBL",
    ]
    if not args.shear:
        params_parts.append("orbital_advection/Omega0=0.0")
    params_str = " ".join(params_parts)

    extra_parts = [
        "perturbation/rseed=1",
        f"particle1/fgas={args.fgas}",
        "particle1/r_return=100",
        f"gravity/solve_grav_hyperbolic_dt={str(selfg_dt).lower()}",
        "hydro/dfloor=1.e-6",
        "hydro/pfloor=1.e-6",
        f"mesh/mhd_outflow_bc={args.mhd_bc}",
        f"problem/beta0={args.beta}",
    ]
    if physics_is_cr:
        extra_parts += [
            "cr/sigma=1.e-25",
            "cr/self_consistent_flag=1",
            f"mesh/cr_outflow_bc={args.cr_bc}",
        ]
    if args.shear:
        extra_parts.append(
            "mesh/ix1_bc=shear_periodic mesh/ox1_bc=shear_periodic hydro/fofc_shear=true"
        )
    else:
        extra_parts.append("mesh/ix1_bc=periodic mesh/ox1_bc=periodic")
    extra_str = " ".join(extra_parts)

    # --- SBATCH header ---
    sbatch = [
        f"#SBATCH --job-name={args.physics}-{res_label}",
    ]
    if mcfg["account"]:
        sbatch.append(f"#SBATCH --account={mcfg['account']}")
    if args.partition or mcfg["partition"]:
        sbatch.append(f"#SBATCH -p {args.partition or mcfg['partition']}")
    sbatch += [
        f"#SBATCH -N {nodes}",
        f"#SBATCH -n {ntasks}",
        f"#SBATCH --time={args.walltime}",
        "#SBATCH --mail-type=all",
        f"#SBATCH --mail-user={args.email}",
        "#SBATCH --output=tigress-%j.out",
        "#SBATCH --error=tigress-%j.err",
    ]

    lines = ["#!/bin/bash"] + sbatch + [
        "",
        module_block(args.machine, cc),
        "",
        "# ---------------------------------------------------------------------------",
        "# Arguments: KEY=VALUE pairs + one positional STARTFLAG (-i or -r)",
        "# ---------------------------------------------------------------------------",
        f'usage="Usage: sbatch {script_name} <STARTFLAG=-i|-r> [RSTNUM=final] [CC={cc}]"',
        "STARTFLAG=",
        f"RSTNUM=final",
        f"CC={cc}",
        "",
        'for arg in "$@"; do',
        '    if [[ "$arg" == *=* ]]; then',
        "        key=${arg%%=*}; val=${arg#*=}",
        '        case "$key" in',
        "            STARTFLAG|startflag) STARTFLAG=$val ;;",
        "            RSTNUM|rstnum)       RSTNUM=$val ;;",
        "            CC|cc)               CC=$val ;;",
        '            *) echo "Unknown parameter: $key" >&2; exit 1 ;;',
        "        esac",
        "    else",
        '        [[ -z "$STARTFLAG" ]] && STARTFLAG=$arg || { echo "Unexpected arg: $arg" >&2; exit 1; }',
        "    fi",
        "done",
        "",
        '[[ -z "$STARTFLAG" ]] && echo "$usage" && exit 1',
        "",
        'echo "submitting: STARTFLAG=$STARTFLAG RSTNUM=$RSTNUM CC=$CC"',
        "",
        "# ---------------------------------------------------------------------------",
        "# Paths",
        "# ---------------------------------------------------------------------------",
        "prob=tigress_classic",
        "PID=TIGRESS",
        "SRCDIR=$HOME/tigris",
        f"SCRIPTDIR={scriptdir}",
        f"SCRIPT={script_name}",
        "",
        "EXE=tigris_${CC}.exe",
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
        f'extra_params="{extra_str}"',
        'rst_params="output1/file_number=0 output5/file_number=0"',
        "",
        "# ---------------------------------------------------------------------------",
        "# Run directory",
        "# ---------------------------------------------------------------------------",
        "echo $RUNDIR",
        "if [ -d $RUNDIR ]; then",
        "    echo 'directory exists'",
        '    if [[ $STARTFLAG != "-r" ]]; then',
        "        echo 'cleaning up'; rm -rf $RUNDIR/*",
        "    fi",
        "else",
        "    mkdir -p $RUNDIR",
        "fi",
        "cd $RUNDIR",
        "echo $params $extra_params",
        "",
        "set -o pipefail",
        "",
        "[ ! -f \"$EXE\" ]          && cp -p ${SCRIPTDIR}/$EXE .",
        "[ ! -f \"$COOL_TBL\" ]     && cp -p $TBLDIR/$COOL_TBL .",
        "[ ! -f \"$POPSYNTH_TBL\" ] && cp -p $TBLDIR/$POPSYNTH_TBL .",
        "",
        "# ---------------------------------------------------------------------------",
        "# Run",
        "# ---------------------------------------------------------------------------",
        "RSTINPUT=$PID.$RSTNUM.rst",
        'if [[ ! -f "$RSTINPUT" && "$STARTFLAG" == "-i" ]]; then',
        '    echo "Starting fresh"',
        "    cp $0 ./$SCRIPT",
        "    cp ${SCRIPTDIR}/../$INPUT .",
        f"    srun $EXE -i $INPUT -t {tlim_run} $params $extra_params \\",
        '        1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"',
        "else",
        '    echo "Restarting from $RSTINPUT"',
        "    rstnum=$(ls out.*.txt 2>/dev/null | wc -l)",
        '    if [[ "$RSTNUM" == "final" ]]; then',
        f"        srun $EXE -r $RSTINPUT -t {tlim_run} \\",
        '            1> "$RUNDIR/out.r${rstnum}.txt" 2> "$RUNDIR/err.r${rstnum}.txt"',
        "    else",
        f"        srun $EXE -r $RSTINPUT -t {tlim_run} $rst_params \\",
        '            1> "$RUNDIR/out.r${rstnum}.txt" 2> "$RUNDIR/err.r${rstnum}.txt"',
        "    fi",
        "fi",
        "",
        "EXITCODE=$?",
        'echo "EXITCODE = $EXITCODE"',
        "set +o pipefail",
        "",
        "if [[ $EXITCODE -eq 3 ]]; then",
        '    echo "Resubmitting"',
        "    sbatch $SCRIPT -r CC=$CC",
        "fi",
        "",
        "# ---------------------------------------------------------------------------",
        "# Snapshots",
        "# ---------------------------------------------------------------------------",
        "cd $RUNDIR",
        mcfg["modules_snap"],
        "PYTHONDIR=$HOME/pyathena",
        "export PYTHONPATH=$PYTHONDIR:$PYTHONPATH",
        "pythonscript=$HOME/TIGRESS-CR/python/plot_slices.py",
        "srun python -m mpi4py $pythonscript `pwd`",
    ]

    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(
        description="Generate a tigress_classic Slurm script for stellar, tiger, or anvil.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--machine", choices=list(MACHINES), required=True,
                        help="Target HPC system")
    parser.add_argument("--physics",
                        default="crmhd",
                        help="Physics module (mhd, crmhd, crmhd_duale, crmhd_duals, ...)")
    parser.add_argument("--nodes", type=int, default=5,
                        help="Number of nodes; ntasks = nodes × cores_per_node")
    parser.add_argument("--walltime", default="24:00:00",
                        help="Walltime HH:MM:SS; Athena++ -t is set to walltime-30min")
    parser.add_argument("--partition", default=None,
                        help="Override SBATCH partition (default: machine default)")
    parser.add_argument("--resolution", choices=list(RESOLUTIONS), default="lowres",
                        help="Mesh resolution preset")
    parser.add_argument("--cc", default=None,
                        help="Compiler tag used in EXE name (default: machine default)")
    parser.add_argument("--beta", type=float, default=1.0,
                        help="problem/beta0")
    parser.add_argument("--fgas", type=float, default=0.7,
                        help="particle1/fgas")
    parser.add_argument("--mhd-bc", default="diode",
                        help="mesh/mhd_outflow_bc")
    parser.add_argument("--cr-bc", default="lngrad_out",
                        help="mesh/cr_outflow_bc (crmhd only)")
    parser.add_argument("--shear", action="store_true", default=False,
                        help="Use shear_periodic x1 BCs instead of periodic")
    parser.add_argument("--sim-tlim", type=int, default=500,
                        help="time/tlim for the simulation (Myr)")
    parser.add_argument("--rundir-suffix", default="",
                        help="Extra suffix appended to run directory and script name")
    parser.add_argument("--email", default="changgookim@gmail.com",
                        help="SBATCH mail address")
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
