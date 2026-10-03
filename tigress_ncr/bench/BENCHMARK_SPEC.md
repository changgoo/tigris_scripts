# TIGRESS-NCR toolchain benchmark: specification

This spec is for porting TIGRESS-NCR to a new cluster: pick the compiler + MPI stack,
write that machine's build and job environment, and record results that can be compared
across machines. It is written so that an agent (Claude) or a person can repeat the procedure step
by step. The first machine done this way was stellarai-amd (2026-10-02), with results in
`results/stellarai-amd.txt` and a write-up in `../stellarai-amd/README.md`.

## 1. What is measured

**Workload (fixed; do not change between machines).** Two 8 pc production checkpoints:

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

**Correctness gate.** Every run of a physics must end with the same last line of
`TIGRESS_NCR.hst`, to the printed precision. If one doesn't, the build or toolchain is
suspect and its timing is invalid. See §4 G.

## 2. Files

```
tigress_ncr/
  build_tigress.sh                 --machine=<M> --cc=<tc>|all  (generic path when <M>/env.sh exists)
  <M>/env.sh                       machine-env contract (from bench/env_template.sh)
  <M>/tigris_ncr_<phys>-fft-<tc>.exe  (+ .buildinfo: commit, modules, flags)
  <M>/README.md                    results + recommendation for the machine
  <M>/tigress_ncr_{mhd,crmhd}_8pc.slurm   production jobs (copy from stellarai-amd/)
  bench/
    BENCHMARK_SPEC.md              this file
    env_template.sh                template for <M>/env.sh
    submit.sh                      submit one run:  M PHYS TC [NCYC] [overrides]
    run_matrix.sh                  all toolchains x physics x repeats, respects SLURM_MAX_JOBS
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
| `TOOLCHAINS`, `DEFAULT_TOOLCHAIN` | toolchain names; the default is set after benchmarking |
| `BENCH_RST_mhd`, `BENCH_RST_crmhd` | checkpoint paths on this machine |
| `load_toolchain <tc>` | `module purge`, load the stack, set `CXX_CHOICE` (configure `--cxx` preset) and `CFLAG` (passed as `--cflag`, applied to compile and link) |

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
2. Copy the two checkpoints into `$SCRATCH_BASE/{mhd,crmhd}-ncr-8pc/`. Verify them with
   `python3 bench/rst_info.py <file>`, which must print `384 300.000... 0.000569... 646619`
   (mhd) and `384 150.000... 0.00012 1250001` (crmhd). Check the sizes against §1 too.
3. Ask the user for anything that can't be discovered: the account, any partition
   restrictions, and the scratch path if it isn't obvious.

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

Flags policy: arch-specific (`-march=<cpu>`), LTO/IPO on, and fast math everywhere. icpx
uses `fp-model=fast` by default, and the Stellar production builds used that. Starting points:

| family | `CXX_CHOICE` | `CFLAG` |
|---|---|---|
| GCC | `g++-simd` | `-march=<arch> -flto=auto` |
| AOCC / LLVM clang | `clang++` | `-march=<arch> -ffast-math -fopenmp-simd -flto -fuse-ld=lld` |
| oneAPI icpx on Intel CPUs | `icpx` | (preset already has `-ipo -xhost`) |
| oneAPI icpx on non-Intel CPUs | `clang++` | `-march=<arch> -ipo -qopenmp-simd -Wno-tautological-constant-compare -Wno-array-bounds` |

The `clang++` preset goes through `mpicxx`, so the MPI module decides which compiler
actually runs. Verify that with `mpicxx --showme` (Open MPI) or `mpicxx -show` (MPICH /
Intel MPI).

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
`.buildinfo` for the commit, the modules and the flags. Then run `ldd <exe>` with the
toolchain loaded: libfftw3, libhdf5 and libmpi must resolve to the intended stack.

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

### G. Correctness check

```bash
cd $SCRATCH_BASE/tigress_ncr/bench
for d in mhd-*;   do echo "$d $(tail -1 $d/TIGRESS_NCR.hst | cut -c1-80)"; done | sort -k2 | uniq -c -f1
for d in crmhd-*; do echo "$d $(tail -1 $d/TIGRESS_NCR.hst | cut -c1-80)"; done | sort -k2 | uniq -c -f1
```

Each physics should collapse to one distinct line. Only compare runs that advanced the
same NCYC.

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

1. Default toolchain: the lowest `max(rel_mhd, rel_crmhd)`. Break ties of under 2% by preferring
   fewer exotic modules. Set `DEFAULT_TOOLCHAIN` in `env.sh`, and put it first in `TOOLCHAINS`.
2. Production scripts: copy `stellarai-amd/tigress_ncr_{mhd,crmhd}_8pc.slurm` to `<M>/` and
   adapt them:
   - the `#SBATCH` partition, account and node lines (4 nodes x 96 there);
   - `CC` default, `RUNBASE`, and the mail address.

   Smoke-test one with `sbatch --time=00:04:00 --mail-type=NONE ... -r` in a scratch
   `RUNBASE` that holds a symlinked checkpoint. Then delete that directory, because it
   gets a 3-4 GB `final.rst`.
3. Write `<M>/README.md`: the hardware, the toolchain table, the summary table, the findings
   (§H), the recommendation, and build/run commands. Add a pointer line to `tigress_ncr/README.md`.
4. Commit `<M>/env.sh`, `<M>/README.md`, `<M>/*.slurm` and `bench/results/<M>.txt` on the
   `benchmark` branch of tigris_scripts. Don't commit executables, `.buildinfo` files or logs;
   they're git-ignored. Then add a row for the machine to §6.

## 5. Pitfalls already hit (check these first)

- configure.py's `icpx` preset hard-codes `-xhost`. On AMD that builds a binary that exits
  with "can only be run on Intel(R) processors". Use the `clang++` preset with `-march`.
- `configure.py` has a `#!/usr/bin/env python` shebang; clusters without `python` fail.
  `build_tigress.sh` calls `python3 ./configure.py`.
- Multi-word `--cflag` values must be passed as one argument. The build script keeps the
  configure options in a bash array.
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
