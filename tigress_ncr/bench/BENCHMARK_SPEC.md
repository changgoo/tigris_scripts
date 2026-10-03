# TIGRESS-NCR toolchain benchmark: specification

This spec is for porting TIGRESS-NCR to a new cluster: pick the compiler + MPI stack,
write that machine's build and job environment, and record results that can be compared
across machines. It is written so that an agent (Claude) or a person can repeat the procedure step
by step. The first machine done this way was stellarai-amd (2026-10-02/03), with results in
`results/stellarai-amd.txt` and a write-up in `../stellarai-amd/README.md`.

The outcome for each machine is a `<M>/env.sh` that records the best module stack and the
best **complete** compiler flags for each compiler. `build_tigress.sh --machine=<M>` with no
other choices then builds the benchmarked best.

## 1. What is measured

**Workload (fixed; do not change between machines).** Two 8 pc production checkpoints from
`/projects/EOSTRIKE/tigris-benchmark/`. That directory is readable from the login nodes of the
Princeton clusters (stellar, tiger, stellarai-amd), but **not from compute nodes**, so
`submit.sh` stages the files to scratch (§2). For outside clusters, copy the two files
(Globus or rsync) and set `BENCH_DATA` in that machine's `env.sh`.

| physics | checkpoint | state | build |
|---|---|---|---|
| `mhd`   | `mhd-ncr-8pc/TIGRESS_NCR.00006.rst` (2.77 GB)   | t=300, cycle 646619, MHD + NCR + ray tracing | `--physics=mhd` |
| `crmhd` | `crmhd-ncr-8pc/TIGRESS_NCR.00003.rst` (3.75 GB) | t=150, cycle 1250001, CRMHD + NCR, `cr/photchem_flag=1` | `--physics=crmhd` |

Both have a 128x128x768 mesh with 32^3 meshblocks, so 384 blocks, run as **one rank per
block (384 MPI ranks), no OpenMP**. Every run restarts the checkpoint unchanged and advances
**200 cycles** (`time/nlim = restart cycle + 200`). The only runtime overrides are timing and
stdout cadence (`time/ncycle_out=10 time/ncycle_out_timing=10 job/output_timing=true`).
The physics, including the `rayt_sparse` cadence, comes from the checkpoint's own parameters.

**Source.** Build from the `ncr-cr-coupling` branch in `$HOME/tigris/.worktrees/ncr-cr-coupling`.
Record the commit; stellarai-amd used `eee94bc4f`. If you benchmark a newer commit, also
rerun the reference machine's default toolchain, or say in the results that the commits differ.

**Metric.** `TIGRESS_NCR.loop_time.txt` gets one line per 10 cycles. Each line has, for each
timer, the per-cycle wall time summed over ranks and the imbalance `max*nranks/sum`. The
first window after a restart is partial and is dropped, which leaves 19 windows from
200 cycles. `parse_loop_time.py` reports:

- `s_cycle`: the rank-mean wall seconds per cycle of `All`, the whole main-loop iteration.
  This is the headline number. Start-up, restart reading and the final dump are excluded.
- per-timer `mean/max` seconds per cycle:
  - `tint`: the time-integrator task list (hydro/MHD/CR)
  - `grav`: the FFT self-gravity solve
  - `rayt`: ray tracing
  - `pchem`: NCR photochemistry
  - `ops`: the operator-split task list
- `zc_core_s`: zone-cycles per core-second.
- derived in `summarize.py`: `node-h/1e4`, the node-hours per 10^4 cycles. Use it to compare
  machines; `s_cycle` compares toolchains on one machine.

**Correctness gate.** All runs of one physics end at the same time, so their final
`TIGRESS_NCR.hst` rows must agree. Builds with the same compiler and math flags agree
exactly, at the printed 6 digits. Different compilers or math modes differ at round-off level,
and the turbulent flow amplifies that over 200 cycles. On stellarai-amd, the maximum relative
difference over all columns was about 1e-5 (aocc vs gcc) to 6e-5 (icpx vs gcc).
`compare_hst.py` reports it. A difference above ~1e-3, a NaN, or a different end time
means the build is suspect and its timing is invalid. See §4 G.

## 2. Files

```
tigress_ncr/
  build_tigress.sh                 --machine=<M> [--cc=<tc>|all] [--cxxflags=...] [--srcdir=...]
  <M>/env.sh                       machine-env contract (from bench/env_template.sh)
  <M>/flag_variants.txt            compiler-flag sweep definition: <tc> <variant> <complete flags>
  <M>/tigris_ncr_<phys>-fft-<tc>[-<variant>].exe  (+ .buildinfo: commit, modules, flags)
  <M>/README.md                    results + recommendation for the machine
  <M>/tigress_ncr_{mhd,crmhd}_8pc.slurm   production jobs (copy from stellarai-amd/)
  bench/
    BENCHMARK_SPEC.md              this file
    env_template.sh                template for <M>/env.sh
    submit.sh                      submit one run:  M PHYS TC [NCYC] [overrides]
    run_matrix.sh                  all toolchains x physics x repeats, respects SLURM_MAX_JOBS
    flag_sweep.sh                  build (parallel lanes) + run every flag variant
    compare_hst.py                 correctness: max relative diff of final hst rows
    tigress_ncr_8pc_bench.slurm    the job (machine-independent; submit via submit.sh)
    parse_loop_time.py             loop_time.txt -> one result line
    summarize.py                   results/*.txt -> markdown tables
    rst_info.py                    nbtotal/time/dt/ncycle from a restart header
    results/<M>.txt                one line per run (committed)
    logs/                          slurm stdout/err (git-ignored)
```

### Machine-env contract (`<M>/env.sh`)

`env.sh` defines these variables and one function, and does nothing else when sourced:

| name | meaning |
|---|---|
| `MACHINE_CPU`, `CORES_PER_NODE` | hardware; nodes requested = ceil(384 / CORES_PER_NODE) |
| `SLURM_PARTITION`, `SLURM_ACCOUNT`, `SLURM_EXTRA` | sbatch options (`SLURM_EXTRA` is free-form, may be empty) |
| `SLURM_MAX_JOBS` | the per-user queued-job limit; `run_matrix.sh` stays below it |
| `SCRATCH_BASE` | run directories go under `$SCRATCH_BASE/tigress_ncr/` |
| `MAKE_JOBS` | `make -j` |
| `MPI_LAUNCH` | the launcher prefix, e.g. `srun --cpu-bind=cores` |
| `TOOLCHAINS`, `DEFAULT_TOOLCHAIN` | toolchain names; the default is the benchmarked best and is what `build_tigress.sh` builds with no `--cc` |
| `BENCH_DATA` | where the checkpoints are kept (e.g. `/projects/EOSTRIKE/tigris-benchmark`; may be login-only) |
| `BENCH_CACHE` | compute-visible copy (`$SCRATCH_BASE/tigris-benchmark`); `submit.sh` stages into it |
| `BENCH_RST_mhd`, `BENCH_RST_crmhd` | checkpoint paths **relative to** `BENCH_DATA`/`BENCH_CACHE` |
| `FLAGS_<COMPILER>` | the best complete flag set for each compiler (from the flag sweep) |
| `load_toolchain <tc>` | `module purge`, load the stack, and set `CXX_PRESET` and `TC_CXXFLAGS` |

**Compiler flags are owned by env.sh, not by configure.py.** `CXX_PRESET` (`g++`, `clang++`,
...) is only used to run configure. After configure, `build_tigress.sh` replaces the
Makefile's `CXXFLAGS` with `TC_CXXFLAGS -I$HDF5DIR/include`. `CXXFLAGS` is used for both
compiling and linking, so LTO/IPO works. `TC_CXXFLAGS` must be complete: optimization level, `-std=c++11`,
arch, vectorization, LTO/IPO and math mode. `--cxxflags=...` overrides it for a single build
(flag sweeps).

Toolchain naming: `<compiler>[-<mpi>]`, where the MPI suffix is omitted for the MPI build
that matches the compiler. Examples: `gcc`, `gcc-impi`, `icpx-impi`, `aocc`, `nvhpc`,
`cray`. Keep a name's meaning stable on a machine, because results refer to it.

## 3. Prerequisites on the new machine

1. Clone the repos. Home directories are usually not shared between clusters; on
   stellarai-amd it was a different home from Stellar.
   ```bash
   git clone git@github.com:PrincetonUniversity/tigris.git $HOME/tigris
   git -C $HOME/tigris fetch origin ncr-cr-coupling
   git -C $HOME/tigris worktree add $HOME/tigris/.worktrees/ncr-cr-coupling ncr-cr-coupling
   git clone <tigris_scripts remote> $HOME/tigris_scripts && git -C $HOME/tigris_scripts switch benchmark
   ```
   Check out the commit recorded in §1 if comparability matters. The data tables
   `inputs/tables/{tigress_coolftn_ncr.txt,Z014_GenevaV00.txt}` come from the worktree.
2. Checkpoints: at Princeton, set `BENCH_DATA=/projects/EOSTRIKE/tigris-benchmark`; the
   first `submit.sh` stages them to `BENCH_CACHE`. Elsewhere, copy
   `{mhd,crmhd}-ncr-8pc/` there first. Verify with `python3 bench/rst_info.py <file>`, which
   must print `384 300.000... 0.000569... 646619` (mhd) and `384 150.000... 0.00012 1250001`
   (crmhd). Check the sizes against §1 too. Check whether compute nodes see `BENCH_DATA`
   (`srun -N1 -n1 -t 2 ls $BENCH_DATA`); it doesn't matter for the benchmark, but it tells
   you where production runs can read from.

3. **Machines with legacy entries in `build_tigress.sh` (stellar, tiger, anvil).** Creating
   `<M>/env.sh` switches `--machine=<M>` to the generic path, so executables get the
   `-<toolchain>` suffix, e.g. `stellar/tigris_ncr_mhd-fft-gcc-impi.exe` instead of
   `stellar/tigris_ncr_mhd-fft.exe`. The machine's existing production slurm scripts then need
   the same update as the stellarai-amd ones (`source env.sh; load_toolchain "$CC"`,
   toolchain in `EXE`). Do that at the end (§4 I), and tell the user, because it changes
   how their production jobs find the executable. The legacy module lines in `build_tigress.sh` and
   the old slurm scripts show which stacks the production runs used so far. Include
   that stack among the candidates (on stellar: oneAPI 2024.2 icpx + Open MPI 4.1.6, which built
   the benchmark checkpoints).

### What the agent discovers vs. what the user provides

The agent finds these itself (§4 A–C): the CPU model and arch, cores per node and NUMA
layout; the partitions, time limits and QOS limits; the module catalogue, and which
compiler + MPI + HDF5 + FFTW combinations exist; the scratch root and its quota; whether
filesystems are visible from compute nodes; and whether the login node's CPU matches the
compute nodes.

Ask the user before starting:
- **the account/allocation to charge**, and any partition or QOS to avoid (debug, preemptible);
- **the node-hour budget**. A full stellarai-amd campaign (matrix, repeats, a 19-variant flag
  sweep) cost about 60 runs x 4 nodes x ~2 min, roughly 10 node-hours;
- **access**: whether git/SSH to GitHub works from that machine, or the repos must be copied;
- outside Princeton: **where the checkpoints are** (or how to transfer 6.5 GB);
- any site rule on login-node builds (`make -j16` with LTO for ~1 min per build).

## 4. Procedure

### A. Inventory (record findings in the env.sh header)

```bash
lscpu; nproc; free -g                         # CPU model/arch, sockets, NUMA, L3 layout
sinfo -o "%P %D %c %m %G %f %l"               # partitions, cores/node, features, limits
scontrol show partition <p>
sacctmgr -nP show assoc user=$USER format=account,partition,qos
module avail 2>&1                             # compilers, MPIs, hdf5, fftw, vendor libs
```

Confirm that the login node has the same CPU as the compute nodes, since builds use the
login node's arch. If it doesn't, give the target arch explicitly and never use
`-march=native` or `-xhost`. Find the scratch root; it might not be `/scratch/gpfs/$USER`.
Find the queue limit; if it isn't listed, a 6th `sbatch` fails with
`QOSMaxSubmitJobPerUserLimit`.

### B. Choose candidate toolchains

Build the cross product of available compilers and MPI implementations. Keep only
combinations that have an **MPI-enabled HDF5 for that compiler + MPI**; Athena++ `-mpi -hdf5`
needs parallel HDF5, so a serial build fails to link or run. At minimum include:

- GCC with every available MPI;
- each vendor compiler (oneAPI icpx, AOCC, NVHPC, Cray) with its natural MPI;
- the vendor MPI (Intel MPI, HPE/Cray MPICH, ...) if it differs from Open MPI.

Use 4 to 6 toolchains. For FFTW, any serial libfftw3 works; Athena does its own MPI
decomposition. Use, in order of preference: an fftw module, then AOCL-FFTW (AMD), then
MKL's FFTW3 interface, then a system `libfftw3`. Headers must be visible, through
`CPLUS_INCLUDE_PATH` or module flags.

Starting flags for the matrix (`FLAGS_*` in env.sh, before the sweep refines them).
icpx's default is `fp-model=fast`, which the Stellar production builds used; fast math
everywhere keeps the comparison fair:

| family | `CXX_PRESET` | starting `FLAGS_*` |
|---|---|---|
| GCC | `g++` | `-O3 -std=c++11 -march=<arch> -ffast-math -fopenmp-simd -flto=auto -fwhole-program -fprefetch-loop-arrays` |
| AOCC / LLVM clang | `clang++` | `-O3 -std=c++11 -march=<arch> -ffast-math -fopenmp-simd -flto -fuse-ld=lld` |
| oneAPI icpx | `clang++` | `-O3 -std=c++11 -march=<arch> -ipo -qopenmp-simd -Wno-tautological-constant-compare -Wno-array-bounds` |
| NVHPC / Cray | `clang++` (or `g++`) | the vendor's `-O3 -fast`-style set with its arch flag |

Use the arch name (`znver5`, `sapphirerapids`, `icelake-server`, `neoverse-v2`, ...), never
`-march=native`/`-xhost` (icpx `-xhost` does not run on AMD). Vendor compilers can be
combined with another MPI through the wrapper's compiler variable. Examples:
`I_MPI_CXX=clang++` makes Intel MPI drive AOCC (as `aocc-impi` does on stellarai-amd), and
`OMPI_CXX`/`MPICH_CXX` do the same for Open MPI and MPICH. HDF5 built by another C compiler
is fine (C ABI). Verify which compiler runs with `mpicxx --showme` (Open MPI) or
`mpicxx -show` (MPICH / Intel MPI); `.buildinfo` records it as `CXX: mpicxx -> <compiler>`.

### C. Write `<M>/env.sh` and probe each toolchain

Copy `bench/env_template.sh` to `<M>/env.sh` and fill it in. Then, for each toolchain:

```bash
bash -c 'source tigress_ncr/<M>/env.sh; load_toolchain <tc> && module -t list;
         (mpicxx --showme || mpicxx -show); echo HDF5DIR=$HDF5DIR'
```

`HDF5DIR`, or `HDF5_ROOT`, must be set, because the build reads it. Compile and run a
trivial program with the chosen `-march` and IPO flags, to catch problems like `-xhost`
failing on AMD.

### D. Build

```bash
cd $HOME/tigris_scripts/tigress_ncr
bash ./build_tigress.sh --machine=<M> --cc=all --physics=mhd   --worktree=ncr-cr-coupling
bash ./build_tigress.sh --machine=<M> --cc=all --physics=crmhd --worktree=ncr-cr-coupling
```

Builds share one source tree, so they run one at a time (`--cc=all` does that). Check each
`.buildinfo` for the commit, the modules, the actual compiler and `CXXFLAGS`. Then run
`ldd <exe>` with the toolchain loaded: libfftw3, libhdf5 and libmpi must resolve to the
intended stack.

### E. Smoke test

```bash
bench/submit.sh <M> mhd <first-tc> 50
```

Wait with an `until` loop on `squeue`; don't `pgrep` for the script, because that matches
the loop itself. Then check:

- `rc=0` and `windows>=4` in `results/<M>.txt`;
- `logs/ncr8bench-<id>.err` is clean;
- the run directory has `out.txt` with `cycle=` lines.

Remove smoke lines from the results file, or keep them; the summary groups by run, so
50-cycle runs only add noise.

### F. Matrix

```bash
nohup bench/run_matrix.sh <M> 200 1 > bench/logs/matrix.log 2>&1 &
```

Each run takes about 1 to 5 minutes of wall time on 4 nodes. Then repeat the contenders
until each has n >= 3. The contenders are the best two toolchains per physics, plus any
within 5% of the best:

```bash
TOOLCHAINS="tcA tcB" nohup bench/run_matrix.sh <M> 200 2 > bench/logs/matrix2.log 2>&1 &
python3 bench/summarize.py bench/results/<M>.txt
```

On stellarai-amd, repeats agreed within 0.5%. Treat differences under ~2% as ties.

### F2. Compiler-flag sweep

The matrix picks the MPI stack. The sweep then picks each compiler's complete flag set,
with every variant on the best MPI, so only the compiler changes. Write
`<M>/flag_variants.txt` (copy stellarai-amd's and change the arch). For each compiler,
cover:

- `preset`: the starting flags;
- `O3`: plain `-O3 -march`, to show what fast math and LTO buy;
- `safe-lto`: no reassociation or finite-math assumptions (`-fno-math-errno -fno-trapping-math`). Prefer it
  if it is within ~2% of the fastest, because it keeps NaN checks meaningful;
- with and without LTO/IPO and `-fwhole-program`;
- `-mprefer-vector-width=512` on AVX-512 CPUs;
- `-funroll-loops` and `-O2`;
- vendor extras (AOCC `-zopt`; icpx `-fp-model=fast=2` and `precise`).

```bash
nohup bench/flag_sweep.sh <M> 200 1 > bench/logs/sweep.log 2>&1 &
```

It builds each variant for both physics in `LANES` (default 3) parallel detached worktrees
`$HOME/tigris/.worktrees/build-lane-<i>`, at the same commit as the reference worktree. Then
it submits everything with `VARIANT=<name>` and prints the summary (rows `tc:variant`). The
build step for 19 variants x 2 physics takes about 15 minutes. Repeat the top 2–3 variants per
compiler (`ONLY='gcc-impi (preset|fast-lto)' SKIP_BUILD=1 bench/flag_sweep.sh <M> 200 2`).
Then copy the winners into `FLAGS_*` in env.sh and rebuild the defaults
(`--cc=all`, both physics). Do not edit `flag_sweep.sh`, `submit.sh` or `run_matrix.sh` while
one of them is running: bash reads scripts incrementally.

### G. Correctness check

```bash
cd $SCRATCH_BASE/tigress_ncr/bench
python3 $HOME/tigris_scripts/tigress_ncr/bench/compare_hst.py mhd-*   --ref=mhd-gcc-impi
python3 $HOME/tigris_scripts/tigress_ncr/bench/compare_hst.py crmhd-* --ref=crmhd-gcc-impi
```

Use the reference machine's default toolchain as `--ref` when it exists. Runs with the same
build give 0. Expect up to ~1e-4 between compilers and math modes. Investigate anything
above 1e-3, NaN, or a different end time. Runs that advanced a different NCYC are reported
as not comparable.

### H. Diagnose with the timer breakdown

- **`rayt` dominates**: the run is limited by MPI latency and progress. Ray tracing passes photon
  packets with asynchronous point-to-point messages (`MPI_Iprobe`/`Isend`/`Testsome`), and
  counts finished rays with `MPI_Fetch_and_op` on a rank-0 window. Compare MPI
  implementations first. Probe MPI tuning with env vars (recorded automatically):
  ```bash
  OMPI_MCA_osc=ucx bench/submit.sh <M> mhd <tc>
  SRUN_OPTS=--distribution=block:block bench/submit.sh <M> mhd <tc>
  ```
  On stellarai-amd, Open MPI 5.0.10 was 4x slower than Intel MPI in `rayt`, and no
  `osc`/`pml` setting fixed it.
- **`tint` dominates** (CRMHD): the run is compute-bound, so the compiler and flags matter.
  On Zen 5, GCC and AOCC were about 25% faster than icpx.
- **`grav`** (FFT) is usually small. A large value points to the FFTW library or
  the all-to-all performance.
- A large `max/mean` gap in `pchem` or `ops` is load imbalance from the physics; it isn't a
  toolchain problem.

### I. Decide and deliver

1. Default toolchain: the lowest `max(rel_mhd, rel_crmhd)`, using the sweep-tuned flags. Break
   ties of under 2% by preferring fewer exotic modules. Set `DEFAULT_TOOLCHAIN` and `FLAGS_*` in
   `env.sh`, and put the default first in `TOOLCHAINS`. Rebuild with `--cc=all`, then confirm the
   default with one run per physics (`bench/submit.sh`) using the final executables.
2. Production scripts: copy `stellarai-amd/tigress_ncr_{mhd,crmhd}_8pc.slurm` to `<M>/` and
   adapt them:
   - the `#SBATCH` partition, account and node lines (4 nodes x 96 there);
   - `CC` default, `RUNBASE`, and the mail address.

   Smoke-test one with `sbatch --time=00:04:00 --mail-type=NONE ... -r` in a scratch
   `RUNBASE` that holds a symlinked checkpoint. Then delete that directory, because it
   gets a 3-4 GB `final.rst`.
3. Write `<M>/README.md`: the hardware, the toolchain table, the summary table, the findings
   (§H), the recommendation, and build/run commands. Add a pointer line to `tigress_ncr/README.md`.
4. Commit `<M>/env.sh`, `<M>/flag_variants.txt`, `<M>/README.md`, `<M>/*.slurm` and `bench/results/<M>.txt` on the
   `benchmark` branch of tigris_scripts. Don't commit executables, `.buildinfo` files or logs;
   they're git-ignored. Then add a row for the machine to §6.

## 5. Pitfalls already hit (check these first)

- configure.py's `icpx` preset hard-codes `-xhost`. On AMD that builds a binary that exits
  with "can only be run on Intel(R) processors". Use the `clang++` preset with `-march`.
- `configure.py` has a `#!/usr/bin/env python` shebang; clusters without `python` fail.
  `build_tigress.sh` calls `python3 ./configure.py`.
- configure.py's presets add flags of their own (e.g. `g++-simd` adds `-march=native`).
  Don't stack `--cflag` on a preset; env.sh's `TC_CXXFLAGS` replaces `CXXFLAGS` in the Makefile.
- `/projects` is not mounted on compute nodes. The checkpoints are staged to scratch.
- The hst rows of different builds differ at about 1e-5. Compare all columns with a tolerance
  (`compare_hst.py`), not by cutting the line: an 80-character prefix hides the differences.
- With `-flto`, `-ipo` and `-fuse-ld=lld`, clang warns "argument unused during compilation"
  on every compile. That's harmless, because the flag is used at link time.
- There might be no FFTW module. Look for AMD AOCL, the MKL FFTW interface, or a system lib.
- `time/nlim` is an absolute cycle count. The bench job reads the restart cycle with `rst_info.py`.
- Athena always writes `<PID>.final.rst` at exit (3-4 GB). The bench job deletes it
  unless `KEEP_RST=1`.
- Without OpenMP, the stdout summary has no wall-clock rate, and `cpu time` includes the final
  dump. Use `loop_time.txt`.
- The QOS can cap queued jobs per user (5 on stellarai-amd), which `run_matrix.sh` handles. It
  can also cap running jobs (`QOSMaxJobsPerUserLimit`, about 2 x 4-node jobs on
  stellarai-amd), so a 10-run matrix takes about 30 minutes.
- Modules and the site can export `I_MPI_HYDRA_*` and `OMPI_MCA_plm_slurm_args`. `submit.sh`
  records only the MPI variables set in your shell before modules load.
- Run `module load` inside `$(...)` or a pipe and it runs in a subshell, so nothing
  stays loaded. Load first, then inspect.

## 6. Cross-machine results (median s/cycle, 200 cycles, 384 ranks)

| machine | CPU | nodes | best toolchain | mhd s/cycle | crmhd s/cycle | mhd node-h/1e4 | crmhd node-h/1e4 | commit |
|---|---|---|---|---|---|---|---|---|
| stellarai-amd | 2x EPYC 9475F (Zen 5), 96 c | 4 | gcc-impi | 0.290 | 0.194 | 3.23 | 2.16 | eee94bc4f |
