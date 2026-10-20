# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

Build and job scripts for TIGRESS++ simulations run with the
[tigris](https://github.com/PrincetonUniversity/tigris) Athena++ fork. No simulation source code
lives here. The scripts expect these paths (home directories are not shared between clusters, so
each cluster needs its own copy):

```text
$HOME/tigris                         # source checkout
$HOME/tigris/.worktrees/<branch>     # worktrees selected with --worktree (e.g. ncr-cr-coupling)
$HOME/tigris_scripts                 # this repo
```

Each top-level directory is one problem generator (`tigress_classic`, `tigress_ncr`, `tigress_nc`,
`sf_cloud`, `turb_dynamo`, `cooling_halo`, `radiative_snr`) or the `benchmark/` blast-wave scaling
tests. Inside it, `athinput.*` files are the Athena inputs, and `<machine>/` subdirectories
(stellar, tiger, stellarai-amd, anvil, delta, nasa, ...) hold that cluster's slurm/PBS scripts and
built executables. `tigress_classic` and `tigress_ncr` are the actively maintained ones; the other
directories use older one-off `compile.sh` scripts with module loads hard-coded.

## Machine-env contract (the core design)

On stellar, tiger and stellarai-amd, `<problem>/<machine>/env.sh` is the single source of truth for
modules and compiler flags, so builds and jobs always load the same stack. It defines machine
variables (`CORES_PER_NODE`, `SLURM_*`, `SCRATCH_BASE`, `MPI_LAUNCH`, `TOOLCHAINS`,
`DEFAULT_TOOLCHAIN`, `FLAGS_<COMPILER>`, ...) and one function, `load_toolchain <tc>`, which purges
and loads modules and sets `CXX_PRESET` and `TC_CXXFLAGS`. The full spec is in
`tigress_ncr/bench/BENCHMARK_SPEC.md` §2; `tigress_ncr/bench/env_template.sh` is the template.

- `tigress_ncr/<machine>/env.sh` holds the actual definitions. `tigress_classic/<machine>/env.sh`
  just `source`s the NCR one so the two cannot drift. Edit the NCR file.
- `TC_CXXFLAGS` is the **complete** flag set. `build_tigress.sh` runs `configure.py` with
  `CXX_PRESET` and then overwrites the Makefile's `CXXFLAGS` with `TC_CXXFLAGS`. Don't stack
  `--cflag` on a configure preset.
- Toolchain names are `<compiler>[-<mpi>]` (`gcc`, `gcc-impi`, `icpx-impi`, `aocc`, ...). The
  toolchain is part of the executable name, and a job must run `load_toolchain` with the same
  toolchain the exe was built with.
- Default toolchains: `icpx-impi` on stellar and tiger, `gcc` (GCC 14 + Open MPI) on stellarai-amd.
- Machines without `env.sh` (anvil, delta, nasa, ...) keep hard-coded module sets inside
  `build_tigress.sh`.

### NaN checks must survive the flags

The solver's safety nets (C2P floors, CR-FOFC/CRAverage, implicit-CR revert, NCR bail-out) are NaN
tests. Production flags must not assume finite math: no icpx `-fp-model=fast=2`, and GCC/Clang
`-ffast-math` always comes with `-fno-finite-math-only`. `tigress_ncr/build_tigress.sh` compiles and
runs `tigress_ncr/bench/nan_check.cpp` with each build's final flags and refuses the build unless
`ALLOW_FINITE_MATH=1` (set only by `bench/flag_sweep.sh` for timing-only variants). To test a flag
set by hand:

```bash
mpicxx <flags> tigress_ncr/bench/nan_check.cpp -o nan_check && ./nan_check 0   # expect nan_checks=kept
```

## Building

```bash
# TIGRESS-NCR: exe -> tigress_ncr/<machine>/tigris_ncr_<physics>-fft-<tc>[-<suffix>].exe
bash tigress_ncr/build_tigress.sh --machine=<machine> --physics=crmhd --worktree=ncr-cr-coupling
# TIGRESS-classic: exe -> tigress_classic/<machine>/tigris[-master]_<physics>-<grav>-<tc>.exe
bash tigress_classic/build_tigress.sh --machine=<machine> --physics=crmhd
```

Run either script with no arguments for the options. Useful ones: `--cc=<tc>|all`,
`--physics=hydro|mhd|crmhd[_duale|_duals]`, `--exe_suffix=<tag>` (keeps the production exe intact),
`--cxxflags='...'`, `--srcdir=<path>`, `--grav=`. Every exe gets a `.buildinfo` (commit, dirty
files, modules, flags, `nan_checks:`). Builds of one source tree share its `obj/` directory, so run
them one at a time. In NCR builds, `--physics=crmhd` adds `--cr=mg`, and `-ncr` sets
`--nspecies`/`--nfreq_rayt` itself, so don't pass `--nspecies`.

## Running jobs

- `tigress_ncr`: hand-written production scripts in `<machine>/`, for example
  `sbatch tigress_ncr_crmhd_8pc.slurm [-r] [TAG]`, with `CC=<tc>` in the environment to pick
  another toolchain. See `tigress_ncr/README.md` §5 for script names per machine.
- `tigress_classic`: generate scripts with `tigress_classic/gen_job.py` (Slurm and PBS):
  `python3 gen_job.py --machine stellar --preset medres --physics crmhd --walltime 24:00:00 -o x.slurm`.
  Node count is derived from mesh/meshblock (one MPI rank per meshblock). Invocations are logged
  to `gen_job.log`. `gen_slurm.py` is the older generator. The hand-written scripts in
  `tigress_classic/stellar/` and `tiger/` still load their own modules and old exe names.

Shared job conventions: `-i` / no flag = fresh start, `-r` = restart (from `*.final.rst` or the
newest `*.NNNNN.rst`). Athena stops on a soft wall-time limit with exit code 3 and the job
resubmits itself. A fresh start wipes the run directory (the NCR scripts refuse if restart files
are present). Run directories go under `$SCRATCH_BASE` (`/scratch/gpfs/$USER` on stellar,
`/scratch/gpfs/EOST/$USER` on tiger and stellarai-amd). Jobs end by plotting snapshots with the
`pyathena` conda env; a failure there does not affect the run.

## Benchmarks (`tigress_ncr/bench/`)

`BENCHMARK_SPEC.md` is the step-by-step procedure, written for an agent to follow, for picking a
machine's toolchain and flags (and for porting to a new cluster). It also lists pitfalls already
hit; read §5 before debugging builds. Key commands:

```bash
bench/submit.sh <M> <mhd|crmhd> <tc> [NCYC] [overrides]   # one 200-cycle restart run
bench/run_matrix.sh <M> 200 <repeats>                     # all toolchains x physics
bench/flag_sweep.sh                                       # variants in <M>/flag_variants.txt
python3 bench/summarize.py bench/results/<M>.txt          # markdown tables
python3 bench/compare_hst.py ...                          # correctness gate on final hst rows
```

Results go in `bench/results/<M>.txt` (committed), and slurm logs go in `bench/logs/`
(git-ignored). Runs are not bitwise reproducible (ray tracing depends on MPI message order), so
correctness is judged against the spread between repeats, and differences under ~2% count as ties.
The checkpoints live in `/projects/EOSTRIKE/tigris-benchmark`, which compute nodes cannot see;
`submit.sh` stages them to scratch.

## Repo conventions

- Python is linted with ruff via pre-commit (`.pre-commit-config.yaml`; `.ruff.toml` ignores
  F841, E741, E402, E731), along with the end-of-file and trailing-whitespace hooks. Run
  `pre-commit run --all-files`.
- `.gitignore` excludes `*.exe`, `*.out`, `*.err`, `*.png`, `*.dat`, `*.buildinfo`. Executables
  and job logs sit next to the scripts but are never committed.
- Commit messages are prefixed with the directory or machine they touch, e.g.
  `tigress_ncr: ...` or `stellarai-amd: ...`.
- Machine READMEs (`tigress_ncr/<machine>/README.md`) record hardware, benchmark numbers and
  dates. When you change a default toolchain or flags, update the env.sh header comment, the
  machine README and the machine table in `tigress_ncr/README.md` together.
