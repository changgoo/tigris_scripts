#!/usr/bin/env python3
"""
gen_job.py — Unified job script generator for tigress_classic.

Supports Slurm (stellar, tiger, anvil) and PBS (nasa_athena).

Mesh geometry
-------------
  --mesh   N  or  N1 N2 N3    (one value → N×N×N)
  --mblock N  or  N1 N2 N3    (one value → N×N×N)
  --dx     FLOAT               cell size in pc

  Domain:  x?min = -(nx? // 2) * dx,  x?max = +(nx? // 2) * dx
  nprocs = (nx1 / mb1) * (nx2 / mb2) * (nx3 / mb3)
  nodes  = ceil(nprocs / cores_per_node)   [can be overridden with --nodes]

Preset shortcuts (--preset NAME) provide default mesh/mblock/dx:
  lowres   64×64×512    mb=16   dx=16 pc
  medres   128×128×1024 mb=32   dx=8  pc
  highres  256×256×2048 mb=64   dx=4  pc
  bigbox   256×256×1024 mb=32   dx=8  pc  (wide lateral box ±1024 pc)
"""

import argparse
import datetime
import math
import sys
import os

# ---------------------------------------------------------------------------
# Machine configurations
# ---------------------------------------------------------------------------
MACHINES = {
    "stellar": {
        "scheduler": "slurm",
        "account": None,
        "partition_default": None,
        "cores_per_node": 96,
        "scratch": "/scratch/gpfs/$USER",
        "scriptdir": "$HOME/tigris_scripts/tigress_classic/stellar",
        "mod_icpx": (
            "module purge; module load anaconda3/2023.3 "
            "intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 "
            "hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10"
        ),
        "mod_gpp": (
            "module purge; module load anaconda3/2023.3 "
            "fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4"
        ),
        "mod_snap": "module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena",
        "default_cc": "icpx",
    },
    "tiger": {
        "scheduler": "slurm",
        "account": "eost",
        "partition_default": None,
        "cores_per_node": 112,
        "scratch": "/scratch/gpfs/EOST/$USER",
        "scriptdir": "$HOME/tigris_scripts/tigress_classic/tiger",
        "mod_icpx": (
            "module purge; module load anaconda3/2023.3 "
            "intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 "
            "hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10"
        ),
        "mod_gpp": (
            "module purge; module load anaconda3/2023.3 "
            "fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4"
        ),
        "mod_snap": "module purge; module load anaconda3/2024.6 openmpi/gcc/4.1.6; conda activate pyathena",
        "default_cc": "icpx",
    },
    "anvil": {
        "scheduler": "slurm",
        "account": "phy240043",
        "partition_default": "wholenode",
        "cores_per_node": 128,
        "scratch": "$SCRATCH",
        "scriptdir": "$HOME/tigris_scripts/tigress_classic/anvil",
        "mod_run": "module purge; module load gcc; module load openmpi; module load fftw hdf5",
        "mod_snap": "module purge; module load anaconda openmpi; conda activate pyathena",
        "default_cc": "g++-simd",
    },
    "nasa_athena": {
        "scheduler": "pbs",
        "queue_default": "long",
        "model": "tur_ath",
        "cores_per_node": 256,
        "scratch": "/nobackup/$USER",
        "scriptdir": "$HOME/tigris_scripts/tigress_classic/nasa_athena",
        "mod_run": (
            "module purge\n"
            "module load PrgEnv-cray cray-pals cray-libpals craype-x86-turin "
            "perftools-base cray-hdf5-parallel cray-fftw\n"
            "module switch PrgEnv-cray PrgEnv-gnu"
        ),
        "mod_snap": None,   # snapshot uses pyathena_tigris, handled separately
        "snap_ppn": 32,
    },
}

# ---------------------------------------------------------------------------
# Resolution presets
# ---------------------------------------------------------------------------
PRESETS = {
    "lowres":  {"mesh": (64,  64,  512),  "mblock": (16, 16, 16), "dx": 16},
    "medres":  {"mesh": (128, 128, 1024), "mblock": (32, 32, 32), "dx": 8},
    "highres": {"mesh": (256, 256, 2048), "mblock": (64, 64, 64), "dx": 4},
    "bigbox":  {"mesh": (256, 256, 1024), "mblock": (32, 32, 32), "dx": 8},
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def expand3(vals, name):
    """Accept 1 or 3 ints; 1 value expands to (v, v, v)."""
    if len(vals) == 1:
        return (vals[0],) * 3
    if len(vals) == 3:
        return tuple(vals)
    raise ValueError(f"--{name} requires 1 or 3 values, got {len(vals)}: {vals}")


def _fmt(v):
    """Format a domain extent as int when possible, float otherwise."""
    return int(v) if v == int(v) else v


def mesh_params_str(nx, mb, dx):
    """Build the Athena++ mesh/meshblock parameter string from geometry."""
    nx1, nx2, nx3 = nx
    mb1, mb2, mb3 = mb
    x1 = _fmt((nx1 // 2) * dx)
    x2 = _fmt((nx2 // 2) * dx)
    x3 = _fmt((nx3 // 2) * dx)
    parts = [
        f"mesh/nx1={nx1}", f"mesh/nx2={nx2}", f"mesh/nx3={nx3}",
        f"mesh/x1min=-{x1}", f"mesh/x1max={x1}",
        f"mesh/x2min=-{x2}", f"mesh/x2max={x2}",
        f"mesh/x3min=-{x3}", f"mesh/x3max={x3}",
        f"meshblock/nx1={mb1}", f"meshblock/nx2={mb2}", f"meshblock/nx3={mb3}",
    ]
    return " ".join(parts)


def nprocs_from_mesh(nx, mb):
    return (nx[0] // mb[0]) * (nx[1] // mb[1]) * (nx[2] // mb[2])


def walltime_to_sec(wt):
    h, m, s = (int(x) for x in wt.split(":"))
    return h * 3600 + m * 60 + s


def sec_to_walltime(secs):
    h, rem = divmod(secs, 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{s:02d}"


def tlim_from_walltime(wt, margin_min=30):
    secs = walltime_to_sec(wt) - margin_min * 60
    if secs <= 0:
        raise ValueError(f"walltime {wt!r} too short for {margin_min}-min margin")
    return sec_to_walltime(secs)


def run_modules(machine, cc):
    mcfg = MACHINES[machine]
    if machine in ("anvil", "nasa_athena"):
        return mcfg["mod_run"]
    return mcfg["mod_icpx"] if cc.startswith("icpx") else mcfg["mod_gpp"]


# ---------------------------------------------------------------------------
# Script body builders
# ---------------------------------------------------------------------------

def build_extra_params(args):
    physics_is_cr = args.physics.startswith("cr")
    parts = [
        "perturbation/rseed=1",
        f"particle1/fgas={args.fgas}",
        "particle1/r_return=100",
        f"gravity/solve_grav_hyperbolic_dt={str(physics_is_cr).lower()}",
        f"mesh/mhd_outflow_bc={args.mhd_bc}",
        f"problem/beta0={args.beta}",
    ]
    if physics_is_cr:
        parts += [
            "cr/sigma=1.e-25",
            "cr/self_consistent_flag=1",
            f"mesh/cr_outflow_bc={args.cr_bc}",
        ]
    if args.shear:
        parts.append("mesh/ix1_bc=shear_periodic mesh/ox1_bc=shear_periodic hydro/fofc_shear=true")
        parts.append(f"orbital_advection/Omega0={args.omega*1.e-3}")
    else:
        parts.append("mesh/ix1_bc=periodic mesh/ox1_bc=periodic")
    return " ".join(parts)


def build_params(args):
    parts = ["job/problem_id=$PID", f"time/tlim={args.sim_tlim}"]
    if args.nlim is not None:
        parts.append(f"time/nlim={args.nlim}")
    parts += ["$mesh_params", "cooling/coolftn_file=$COOL_TBL", "feedback/pop_synth_file=$POPSYNTH_TBL"]
    parts += ["hydro/dfloor=1.e-6", "hydro/pfloor=1.e-6"]  # increased floor
    parts += [f"feedback/fbinary={args.fbinary}"]  # runaway
    if not args.shear:
        parts.append("orbital_advection/Omega0=0.0")
    return " ".join(parts)


def common_body(script_name, rundir, nprocs, tlim_run, launcher, resubmit_cmd, snap_lines):
    """Shell script body shared between Slurm and PBS (after header + module load)."""
    return [
        "",
        "# ---------------------------------------------------------------------------",
        "# Paths",
        "# ---------------------------------------------------------------------------",
        "prob=tigress_classic",
        "PID=TIGRESS",
        "SRCDIR=$HOME/tigris",
        "SCRIPTDIR=$SCRIPTDIR_PLACEHOLDER",   # replaced by caller
        f"SCRIPT={script_name}",
        "",
        "physics=$PHYSICS_PLACEHOLDER",        # replaced by caller
        "EXE=tigris_${physics}.exe",
        "INPUT=athinput.$prob",
        f"RUNDIR={rundir}",
        "",
        "TBLDIR=$SRCDIR/inputs/tables",
        'COOL_TBL="tigress_coolftn.txt"',
        'POPSYNTH_TBL="Z014_GenevaV00.txt"',
        "",
        'mesh_params="$MESH_PARAMS_PLACEHOLDER"',   # replaced by caller
        "",
        'params="$PARAMS_PLACEHOLDER"',             # replaced by caller
        'extra_params="$EXTRA_PARAMS_PLACEHOLDER"', # replaced by caller
        'rst_params="output1/file_number=0 output5/file_number=0"',
    ]


def _run_block(launcher, nprocs, tlim_run, resubmit_cmd):
    """Fresh-start / restart / resubmit logic."""
    if launcher.startswith("mpiexec"):
        run_fresh  = f"    {launcher} -np {nprocs} ./$EXE -i $INPUT -t {tlim_run} $params $extra_params \\"
        run_rst    = f"        {launcher} -np {nprocs} ./$EXE -r $RSTINPUT -t {tlim_run} \\"
        run_rst_p  = f"        {launcher} -np {nprocs} ./$EXE -r $RSTINPUT -t {tlim_run} $rst_params \\"
    else:  # srun
        run_fresh = f"    {launcher} $EXE -i $INPUT -t {tlim_run} $params $extra_params \\"
        run_rst   = f"        {launcher} $EXE -r $RSTINPUT -t {tlim_run} \\"
        run_rst_p = f"        {launcher} $EXE -r $RSTINPUT -t {tlim_run} $rst_params \\"

    return [
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
        '[ ! -f "$EXE" ]          && cp -p ${SCRIPTDIR}/$EXE .',
        '[ ! -f "$COOL_TBL" ]     && cp -p $TBLDIR/$COOL_TBL .',
        '[ ! -f "$POPSYNTH_TBL" ] && cp -p $TBLDIR/$POPSYNTH_TBL .',
        "",
        "# ---------------------------------------------------------------------------",
        "# Run",
        "# ---------------------------------------------------------------------------",
        "RSTINPUT=$PID.$RSTNUM.rst",
        'if [[ ! -f "$RSTINPUT" && "$STARTFLAG" == "-i" ]]; then',
        '    echo "Starting fresh"',
        "    cp $0 ./$SCRIPT",
        "    cp ${SCRIPTDIR}/../$INPUT .",
        run_fresh,
        '        1> "$RUNDIR/out.txt" 2> "$RUNDIR/err.txt"',
        "else",
        '    echo "Restarting from $RSTINPUT"',
        "    rstnum=$(ls out.*.txt 2>/dev/null | wc -l)",
        '    if [[ "$RSTNUM" == "final" ]]; then',
        run_rst,
        '            1> "$RUNDIR/out.r${rstnum}.txt" 2> "$RUNDIR/err.r${rstnum}.txt"',
        "    else",
        run_rst_p,
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
        f"    {resubmit_cmd}",
        "fi",
    ]


# ---------------------------------------------------------------------------
# Slurm generator
# ---------------------------------------------------------------------------

def generate_slurm(args, nx, mb, dx, nprocs, nodes, tlim_run,
                   script_name, rundir, mesh_str, params_str, extra_str):
    mcfg = MACHINES[args.machine]
    cc = args.cc or mcfg["default_cc"]

    # Header
    lines = ["#!/bin/bash",
             f"#SBATCH --job-name={args.physics}-{dx}pc"]
    if mcfg["account"]:
        lines.append(f"#SBATCH --account={mcfg['account']}")
    part = args.partition or mcfg["partition_default"]
    if part:
        lines.append(f"#SBATCH -p {part}")
    lines += [
        f"#SBATCH -N {nodes}",
        f"#SBATCH -n {nprocs}",
        f"#SBATCH --time={args.walltime}",
        "#SBATCH --mail-type=all",
        f"#SBATCH --mail-user={args.email}",
        "#SBATCH --output=tigress-%j.out",
        "#SBATCH --error=tigress-%j.err",
        "",
        run_modules(args.machine, cc),
        "",
        "# ---------------------------------------------------------------------------",
        "# Arguments: positional STARTFLAG (-i or -r) + optional KEY=VALUE overrides",
        "# ---------------------------------------------------------------------------",
        f'usage="Usage: sbatch {script_name} <-i|-r> [RSTNUM=final] [CC={cc}]"',
        "STARTFLAG=",
        "RSTNUM=final",
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
        '[[ -z "$STARTFLAG" ]] && echo "$usage" && exit 1',
        'echo "submitting: STARTFLAG=$STARTFLAG RSTNUM=$RSTNUM CC=$CC"',
        "",
        "# ---------------------------------------------------------------------------",
        "# Paths",
        "# ---------------------------------------------------------------------------",
        "prob=tigress_classic",
        "PID=TIGRESS",
        "SRCDIR=$HOME/tigris",
        f"SCRIPTDIR={mcfg['scriptdir']}",
        f"SCRIPT={script_name}",
        "",
        f"physics={args.physics}",
        "EXE=tigris_${physics}.exe",
        "INPUT=athinput.$prob",
        f"RUNDIR={rundir}",
        "",
        "TBLDIR=$SRCDIR/inputs/tables",
        'COOL_TBL="tigress_coolftn.txt"',
        'POPSYNTH_TBL="Z014_GenevaV00.txt"',
        "",
        f'mesh_params="{mesh_str}"',
        "",
        f'params="{params_str}"',
        f'extra_params="{extra_str}"',
        'rst_params="output1/file_number=0 output5/file_number=0"',
    ]

    lines += _run_block("srun", nprocs, tlim_run,
                        f"sbatch $SCRIPT -r CC=$CC")

    # Snapshots
    lines += [
        "",
        "# ---------------------------------------------------------------------------",
        "# Snapshots",
        "# ---------------------------------------------------------------------------",
        "cd $RUNDIR",
        mcfg["mod_snap"],
        "PYTHONDIR=$HOME/pyathena",
        "export PYTHONPATH=$PYTHONDIR:$PYTHONPATH",
        "pythonscript=$HOME/TIGRESS-CR/python/plot_slices.py",
        "srun python -m mpi4py $pythonscript `pwd`",
    ]

    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# PBS generator
# ---------------------------------------------------------------------------

def generate_pbs(args, nx, mb, dx, nprocs, nodes, tlim_run,
                 script_name, rundir, mesh_str, params_str, extra_str):
    mcfg = MACHINES["nasa_athena"]
    snap_ranks = nodes * mcfg["snap_ppn"]

    # Validate: nprocs must divide evenly into nodes
    cpn = mcfg["cores_per_node"]
    if nprocs % cpn != 0:
        print(f"Warning: nprocs={nprocs} not divisible by {cpn} cores/node; "
              f"using {nodes} nodes ({nodes*cpn} ranks, {nodes*cpn - nprocs} wasted)",
              file=sys.stderr)

    lines = [
        f"#PBS -q {args.queue}",
        f"#PBS -l select={nodes}:ncpus={cpn}:mpiprocs={cpn}:model={mcfg['model']}",
        f"#PBS -l walltime={args.walltime}",
        "#PBS -m abe",
        f"#PBS -M {args.email}",
        "",
        'usage="Usage: qsub -v STARTFLAG=(-i or -r)[,RSTNUM=final] $0"',
        '[[ -z "$STARTFLAG" ]] && echo "$usage" && exit 1',
        '[[ -z "$RSTNUM" ]] && RSTNUM=final',
        'echo "submitting: STARTFLAG=$STARTFLAG RSTNUM=$RSTNUM"',
        "",
        f"NPROCS={nodes * cpn}",
        f"tlim={tlim_run}",
        "",
        mcfg["mod_run"],
        "",
        "# ---------------------------------------------------------------------------",
        "# Paths",
        "# ---------------------------------------------------------------------------",
        "prob=tigress_classic",
        "PID=TIGRESS",
        "SRCDIR=$HOME/tigris",
        f"SCRIPTDIR={mcfg['scriptdir']}",
        f"SCRIPT={script_name}",
        "",
        f"physics={args.physics}",
        "EXE=tigris_${physics}.exe",
        "INPUT=athinput.$prob",
        f"RUNDIR={rundir}",
        "",
        "TBLDIR=$SRCDIR/inputs/tables",
        'COOL_TBL="tigress_coolftn.txt"',
        'POPSYNTH_TBL="Z014_GenevaV00.txt"',
        "",
        f'mesh_params="{mesh_str}"',
        "",
        f'params="{params_str}"',
        f'extra_params="{extra_str}"',
        'rst_params="output1/file_number=0 output5/file_number=0"',
    ]

    lines += _run_block("mpiexec", "$NPROCS", "$tlim",
                        "qsub -v STARTFLAG=-r,RSTNUM=final $SCRIPT")

    # Snapshots
    lines += [
        "",
        "# ---------------------------------------------------------------------------",
        "# Snapshots",
        "# ---------------------------------------------------------------------------",
        "cd $RUNDIR",
        "PYTHONDIR=$HOME/pyathena_tigris",
        "export PYTHONPATH=$PYTHONDIR:$PYTHONPATH",
        "pythonscript=$HOME/TIGRESS-CR/python/plot_slices.py",
        f"$HOME/myenv/bin/mpiexec --ppn {mcfg['snap_ppn']} -n {snap_ranks} python -m mpi4py $pythonscript `pwd`",
    ]

    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def resolve_geometry(args):
    """Return (nx, mb, dx) tuples, applying preset then explicit overrides."""
    nx, mb, dx = None, None, None

    if args.preset:
        p = PRESETS[args.preset]
        nx, mb, dx = p["mesh"], p["mblock"], p["dx"]

    if args.mesh:
        nx = expand3(args.mesh, "mesh")
    if args.mblock:
        mb = expand3(args.mblock, "mblock")
    if args.dx is not None:
        dx = args.dx

    if nx is None or mb is None or dx is None:
        missing = [n for n, v in [("mesh", nx), ("mblock", mb), ("dx", dx)] if v is None]
        raise SystemExit(f"Error: {', '.join(missing)} not set. "
                         "Use --preset or provide --mesh, --mblock, and --dx.")

    for i, (n, m) in enumerate(zip(nx, mb)):
        if n % m != 0:
            raise SystemExit(f"Error: mesh[{i}]={n} not divisible by mblock[{i}]={m}")

    return nx, mb, dx


def generate(args):
    nx, mb, dx = resolve_geometry(args)
    mcfg = MACHINES[args.machine]
    scheduler = mcfg["scheduler"]

    nprocs = nprocs_from_mesh(nx, mb)
    cpn = mcfg["cores_per_node"]
    nodes = args.nodes if args.nodes else math.ceil(nprocs / cpn)
    tlim_run = tlim_from_walltime(args.walltime)

    mesh_str = mesh_params_str(nx, mb, dx)
    params_str = build_params(args)
    extra_str = build_extra_params(args)

    # Script name and run directory
    ext = "pbs" if scheduler == "pbs" else "slurm"
    dx_label = int(dx) if dx == int(dx) else dx
    label = f"{dx_label}pc"
    script_name = f"tigress_classic_{args.physics}-{label}"
    if args.rundir_suffix:
        script_name += f"-{args.rundir_suffix}"
    script_name += f".{ext}"

    physics_is_cr = args.physics.startswith("cr")
    dir_parts = [args.physics, label, f"b{args.beta}", f"mhdbc_{args.mhd_bc}"]
    if physics_is_cr:
        dir_parts.append(f"crbc_{args.cr_bc}")
    if args.shear:
        dir_parts.append("shear")
    if args.fbinary > 0:
        dir_parts.append(f"fbin_{args.fbinary}")
    if args.rundir_suffix:
        dir_parts.append(args.rundir_suffix)
    rundir = f"{mcfg['scratch']}/tigress_classic/{'-'.join(dir_parts)}"

    kw = dict(nx=nx, mb=mb, dx=dx, nprocs=nprocs, nodes=nodes, tlim_run=tlim_run,
              script_name=script_name, rundir=rundir,
              mesh_str=mesh_str, params_str=params_str, extra_str=extra_str)

    print(f"Script is generated with rundir={rundir}")

    if scheduler == "slurm":
        return generate_slurm(args, **kw), os.path.join(args.machine,script_name)
    else:
        return generate_pbs(args, **kw), os.path.join(args.machine,script_name)

def main():
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    # Machine / scheduler
    p.add_argument("--machine", choices=list(MACHINES), required=True)

    # Geometry — preset or explicit
    geo = p.add_argument_group("mesh geometry")
    geo.add_argument("--preset", choices=list(PRESETS),
                     help="Resolution shortcut (sets default mesh/mblock/dx)")
    geo.add_argument("--mesh", type=int, nargs="+", metavar="N",
                     help="Mesh cells: one value N→N³ or three N1 N2 N3")
    geo.add_argument("--mblock", type=int, nargs="+", metavar="N",
                     help="Meshblock cells: one value N→N³ or three N1 N2 N3")
    geo.add_argument("--dx", type=float, metavar="PC",
                     help="Cell size in pc (sets domain extents)")

    # Node count (optional override)
    p.add_argument("--nodes", type=int, default=None,
                   help="Override node count (default: ceil(nprocs / cores_per_node))")

    # Scheduler-specific
    p.add_argument("--walltime", default="24:00:00",
                   help="Walltime HH:MM:SS; Athena++ -t = walltime − 30 min")
    p.add_argument("--queue", default="long",
                   help="PBS queue name (nasa_athena only)")
    p.add_argument("--partition", default=None,
                   help="Override Slurm partition")
    p.add_argument("--cc", default=None,
                   help="Compiler tag for module loading (Slurm only; default: machine default)")

    # Physics
    phy = p.add_argument_group("physics")
    phy.add_argument("--physics", default="crmhd",
                     help="Physics module: mhd, crmhd, crmhd_duale, ...")
    phy.add_argument("--beta", type=float, default=1.0, help="problem/beta0")
    phy.add_argument("--fgas", type=float, default=0.9, help="particle1/fgas")
    phy.add_argument("--omega", type=float, default=28, help="orbital_advection/Omega0")
    phy.add_argument("--fbinary", type=float, default=0.7, help="feedback/fbinary")
    phy.add_argument("--mhd-bc", default="diode", help="mesh/mhd_outflow_bc")
    phy.add_argument("--cr-bc", default="lngrad_out",
                     help="mesh/cr_outflow_bc (crmhd only)")
    phy.add_argument("--shear", action="store_true", default=False,
                     help="Use shear_periodic x1 BCs (default: periodic)")
    phy.add_argument("--sim-tlim", type=int, default=500,
                     help="time/tlim in Myr")
    phy.add_argument("--nlim", type=int, default=None,
                     help="time/nlim cycle limit (omitted if not given)")

    # Output
    p.add_argument("--rundir-suffix", default="",
                   help="Extra tag appended to run directory and script name")
    p.add_argument("--email", default="changgookim@gmail.com")
    p.add_argument("--output", "-o", default=None,
                   help="Write to file (default: stdout)")

    args = p.parse_args()
    script, script_name = generate(args)

    if args.output:
        outpath = args.output
    else:
        outpath = script_name
        sys.stdout.write(script)
        if os.path.exists(outpath):
            ans = input(f"'{outpath}' already exists. Overwrite? [y/n] ").strip().lower()
            if ans != "y":
                print("Aborted. Script printed to stdout above.", file=sys.stderr)
                sys.exit(0)

    with open(outpath, "w") as f:
        f.write(script)
    print(f"Written to {outpath}", file=sys.stderr)

    # Log the command that generated this script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    log_path = os.path.join(script_dir, "gen_job.log")
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cmd = os.path.relpath(sys.argv[0]) + " " + " ".join(sys.argv[1:])
    with open(log_path, "a") as lf:
        lf.write(f"[{timestamp}] {cmd}  # -> {outpath}\n")
    print(f"Logged to {log_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
