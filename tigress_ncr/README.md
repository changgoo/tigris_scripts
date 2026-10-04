# Build and run TIGRESS-NCR (with cosmic rays)

This directory builds the TIGRESS-NCR problem generator (`src/pgen/tigress_ncr.cpp` of
[tigris](https://github.com/PrincetonUniversity/tigris)) and runs it on the Princeton
clusters. Every machine has a directory `<machine>/` with:

- `env.sh`: the module stack of each toolchain and its complete compiler flags. The
  default toolchain (`DEFAULT_TOOLCHAIN`) is the one that benchmarked fastest on that machine.
- the production Slurm scripts, which source `env.sh`, so a job always loads the modules its
  executable was built with;
- the executables `tigris_ncr_<physics>-fft-<toolchain>.exe`, each with a `.buildinfo`
  (commit, modules, flags);
- `README.md`: hardware, benchmark results and machine-specific notes.

## Machines

The best toolchain is chosen by `bench/` (see [Benchmarks](#9-benchmarks-and-new-machines)).
Times are seconds per cycle for the 8 pc runs (128x128x768, 384 meshblocks of 32^3, one MPI
rank per block, 4 nodes).

| machine | CPU (cores/node) | default `--cc` | stack | MHD | CRMHD | jobs | notes |
|---|---|---|---|---|---|---|---|
| stellarai-amd | 2x AMD EPYC 9475F, Zen 5 (96) | `gcc-impi` | GCC 14 + Intel MPI 2021.18, `-march=znver5`, fast math, LTO, 512-bit vectors | 0.291 | 0.195 | `tigress_ncr_{mhd,crmhd}_8pc.slurm` | [README](stellarai-amd/README.md) |
| stellar | 4x Intel Xeon Platinum 8268, Cascade Lake (96) | `icpx-impi` | oneAPI 2024.2 icpx + Intel MPI 2021.13, `-xCASCADELAKE -ipo -fp-model=fast=2` | 0.737 | 0.411 | `tigress_ncr_{mhd,crmhd}_8pc_tc.slurm` | [README](stellar/README.md) |
| tiger | 2x Intel Xeon Platinum 8480+, Sapphire Rapids (112; 96 used) | `icpx-impi` | oneAPI 2024.2 icpx + Intel MPI 2021.13, `-xSAPPHIRERAPIDS -ipo -fp-model=fast=2` | 0.510 | 0.328 | `tigress_ncr_{mhd,crmhd}_8pc.slurm` | [README](tiger/README.md) |
| anvil | | (legacy) | fixed modules in `build_tigress.sh` | | | | no `env.sh` yet |

An 8 pc run costs 2.1-2.5x fewer node-hours on stellarai-amd than on Stellar (newer cores,
and ray tracing is 3x faster there). On both machines Intel MPI is clearly faster than
Open MPI for MHD, whose cycle is dominated by ray tracing, which is limited by MPI
point-to-point latency and one-sided progress (4x on stellarai-amd, 1.25x on Stellar). On
stellarai-amd the Open MPI gap comes from the rank-0 RMA termination counter and disappears
with `<ray_tracing>/termination = iallreduce`
([report](bench/reports/rayt-termination-stellarai-amd.md)). The
best compiler differs: GCC on Zen 5, icpx on Cascade Lake, where GCC 13 is 2x slower in NCR
photochemistry.

All three machines side by side: https://claude.ai/artifact/28UKFCgYPf9bFjSzwRyksr

## 1. Shell and modules

Use Bash. If `module` is not already a shell function, initialize Environment Modules:

```bash
source /usr/share/Modules/init/bash
type module sbatch squeue
```

## 2. Repositories

The build and job scripts assume these paths (home directories are not shared between
clusters, so set them up on each one):

```text
$HOME/tigris                                  # source
$HOME/tigris/.worktrees/ncr-cr-coupling       # the branch that is built and run
$HOME/tigris_scripts/tigress_ncr              # this directory
```

```bash
git clone git@github.com:PrincetonUniversity/tigris.git "$HOME/tigris"
git -C "$HOME/tigris" fetch origin ncr-cr-coupling
git -C "$HOME/tigris" worktree add "$HOME/tigris/.worktrees/ncr-cr-coupling" ncr-cr-coupling
```

For an existing worktree, check that it is clean and fast-forward it:

```bash
git -C "$HOME/tigris/.worktrees/ncr-cr-coupling" status --short --branch
git -C "$HOME/tigris/.worktrees/ncr-cr-coupling" merge --ff-only origin/ncr-cr-coupling
```

The jobs copy two data tables from the worktree, so both must exist:

```bash
ls "$HOME/tigris/.worktrees/ncr-cr-coupling/inputs/tables/"{tigress_coolftn_ncr.txt,Z014_GenevaV00.txt}
```

## 3. The coupled CR + NCR configuration

A coupled run has all three of these settings:

- the executable is configured with `--cr=mg` and `-ncr` (`--physics=crmhd`);
- `athinput.tigress_ncr` sets `<photchem>/mode = ncr` and `<cr>/self_consistent_flag = 1`;
- the job passes the runtime override `cr/photchem_flag=1`.

Together they let the CR energy density set the local NCR cosmic-ray ionization rate, and the
NCR ion/neutral abundances set the CR scattering coefficient. The MHD build
(`--physics=mhd`) runs NCR photochemistry and ray tracing without cosmic rays.

## 4. Build

Run from anywhere; the executable goes to `<machine>/`. Without `--cc`, the build uses the
machine's default toolchain and its benchmarked flags:

```bash
cd "$HOME/tigris_scripts/tigress_ncr"
bash ./build_tigress.sh --machine=<machine> --physics=crmhd --worktree=ncr-cr-coupling
bash ./build_tigress.sh --machine=<machine> --physics=mhd   --worktree=ncr-cr-coupling
```

For example, on Stellar this produces `stellar/tigris_ncr_crmhd-fft-icpx-impi.exe` and
`stellar/tigris_ncr_mhd-fft-icpx-impi.exe`. Other options:

| option | meaning |
|---|---|
| `--cc=<toolchain>` | another stack from `TOOLCHAINS` in `env.sh`; `--cc=all` builds each in turn |
| `--physics=` | `mhd`, `crmhd`, or `*_duale`/`*_duals` (dual energy) |
| `--exe_suffix=<tag>` | appends `-<tag>` to the name, to keep the production executable intact |
| `--cxxflags='...'` | replaces the toolchain's complete compiler flags (flag tests) |
| `--srcdir=<path>` | builds another source tree instead of `--worktree` |

`build_tigress.sh` loads the modules with `load_toolchain` from `env.sh`, runs `configure.py`,
then writes the toolchain's complete flags (`TC_CXXFLAGS`) into the Makefile in place of
configure's preset flags. Check the result:

```bash
cat stellar/tigris_ncr_crmhd-fft-icpx-impi.buildinfo    # commit, dirty files, CXXFLAGS, modules
```

Builds of one source tree share its `obj/` directory, so run them one at a time.

## 5. Run the 8 pc production jobs

The jobs run the production input `athinput.tigress_ncr` with the mesh refined to 8 pc
(`mesh/nx1=128 nx2=128 nx3=768`), on 4 full nodes with 384 ranks.

```bash
cd "$HOME/tigris_scripts/tigress_ncr/<machine>"
sbatch tigress_ncr_crmhd_8pc<_tc>.slurm          # fresh start
sbatch tigress_ncr_crmhd_8pc<_tc>.slurm -r       # restart
sbatch tigress_ncr_crmhd_8pc<_tc>.slurm -r TAG   # run directory crmhd-ncr-8pc<TAG>
CC=icpx sbatch tigress_ncr_mhd_8pc<_tc>.slurm -r       # another toolchain (built first)
```

The script names are in the [machine table](#machines). The run directory is
`$RUNBASE/<physics>-ncr-8pc<TAG>`; `RUNBASE` defaults to `<scratch>/tigress_ncr`
(`/scratch/gpfs/$USER/tigress_ncr` on Stellar, `/scratch/gpfs/EOST/$USER/tigress_ncr` on
stellarai-amd and tiger).

- With `-r`, the job restarts from `TIGRESS_NCR.final.rst`, or from the newest
  `TIGRESS_NCR.NNNNN.rst` when there is no final file. To continue a run from another
  cluster, copy its checkpoint into the run directory first.
- A fresh start refuses to clean a run directory that contains restart files.
- Each segment copies the executable and tables again, so `CC=...` with `-r` switches a running
  campaign to another build.
- Athena stops on a 23.5 h soft limit (exit code 3) and the job resubmits itself with the same
  `CC`, `RUNBASE` and `TAG`.
- Parameters that are missing from a restart file go in `athinput.restart_add` in the run
  directory (CRMHD job).

Monitor with:

```bash
squeue --user "$USER"
tail -f "$RUNBASE/crmhd-ncr-8pc/out.r0.txt"   # Athena stdout (out.txt for a fresh start)
```

## 6. Other job scripts on Stellar

`stellar/` also has the older scripts, which load oneAPI 2024.2 + Open MPI 4.1.6 directly and
run `stellar/tigris_ncr_<physics>-fft.exe` (no toolchain in the name):
`tigress_ncr_{mhd,crmhd}_8pc.slurm`, the one-node 16 pc tests
`tigress_ncr_crmhd_16pc_test_{coupled,uniform}.slurm` and `tigress_ncr_mhd_16pc_test.slurm`,
`tigress_ncr_mhd_8pc_diag.slurm`, and `tigress_ncr_slices.slurm`.

Since `stellar/env.sh` exists, `build_tigress.sh --machine=stellar` names executables after
their toolchain. To rebuild the executable for an old script, build the `icpx` toolchain
(the same modules) and copy it:

```bash
bash ./build_tigress.sh --machine=stellar --cc=icpx --physics=crmhd --worktree=ncr-cr-coupling
cp stellar/tigris_ncr_crmhd-fft-icpx.exe stellar/tigris_ncr_crmhd-fft.exe
```

The old and new 8 pc scripts use the same run directories, so `sbatch
tigress_ncr_crmhd_8pc_tc.slurm -r` continues a run that the old script started.

## 7. Snapshot postprocessing

After Athena exits, the jobs make slice plots with `$HOME/TIGRESS-CR/python/plot_slices_ncr.py`
in the `pyathena` conda env (`$HOME/.conda/envs/pyathena`, `$HOME/pyathena_master`). The
env.sh-based scripts skip this step when those are missing. A failed plot does not affect
the simulation; check `out*.txt`/`err*.txt` in the run directory.

## 8. Troubleshooting

- `executable not found`: build it for the toolchain in `CC` (section 4).
- `can only be run on Intel(R) processors`: an icpx `-x...`/`-xhost` build on AMD. The env.sh
  flags use `-march=<arch>` there.
- GCC 13 fails to link with `undefined reference to Accretion::rctrl`: a source bug in
  tigris (an odr-used `static constexpr` member without a definition, which C++11 requires).
  See [stellar/README.md](stellar/README.md#gcc-13-and-accretionrctrl).

## 9. Benchmarks and new machines

[`bench/BENCHMARK_SPEC.md`](bench/BENCHMARK_SPEC.md) describes how a machine's `env.sh`,
default toolchain and flags are chosen: two production checkpoints restarted for 200 cycles,
every toolchain, then a compiler-flag sweep. Follow it to port to a new cluster. Raw results
are in `bench/results/<machine>.txt`:

```bash
python3 bench/summarize.py bench/results/stellar.txt
```
