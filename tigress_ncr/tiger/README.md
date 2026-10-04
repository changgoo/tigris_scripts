# TIGRESS-NCR on Tiger (tiger3)

CPU nodes: 2x Intel Xeon Platinum 8480+ (Sapphire Rapids, 56 cores each, 2.0 GHz base and
3.8 GHz turbo, one NUMA domain per socket), 112 cores and 1 TB per node, AVX-512 with two FMA
units, and InfiniBand (Slurm topology link speed 200, i.e. NDR200). The login nodes have
the same CPU, so builds made there run on the compute nodes. The 8 pc runs (128x128x768,
32^3 blocks, 384 meshblocks) use 4 nodes with 96 ranks each, one block per rank, so 16
cores per node stay idle.

Scratch is `/scratch/gpfs/EOST/$USER` (not `/scratch/gpfs/$USER`), and run directories
default to `/scratch/gpfs/EOST/$USER/tigress_ncr/<run>`. Short jobs (the 30-minute benchmark
jobs and a 4-minute test) get the `test` QOS (at most 2 running and 5 queued per user). The benchmark jobs ran there, and
`SLURM_QUEUE_FILTER` in `env.sh` keeps production jobs out of the count. Queue waits, not
run time, set the pace: a 2-minute benchmark job often waited 20-60 minutes.

## Toolchains

`env.sh` follows the machine-env contract of `../bench/BENCHMARK_SPEC.md`. All stacks use the
site's parallel HDF5 1.14.4 and FFTW 3.3.10 modules.

| `--cc`          | compiler            | MPI               | HDF5 (parallel)                         |
|-----------------|---------------------|-------------------|-----------------------------------------|
| `icpx-impi`     | oneAPI 2024.2 icpx  | Intel MPI 2021.13 | hdf5/oneapi-2024.2/intel-mpi/1.14.4     |
| `icpx`          | oneAPI 2024.2 icpx  | Open MPI 4.1.6    | hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 |
| `icpx2026-impi` | oneAPI 2026.0 icpx  | Intel MPI 2021.18 | hdf5/oneapi-2024.2/intel-mpi/1.14.4 (same C and MPI ABI) |
| `gcc-impi`      | GCC 11.5 (system)   | Intel MPI 2021.13 | hdf5/gcc/intel-mpi/1.14.4               |
| `gcc`           | GCC 11.5 (system)   | Open MPI 4.1.6    | hdf5/gcc/openmpi-4.1.6/1.14.4           |

`icpx` is the stack of the legacy tiger entry in `build_tigress.sh`. Tiger has no
`gcc-toolset`, so GCC 11.5 is the only GCC. oneAPI 2026.0 has no parallel HDF5 of its own,
so `icpx2026-impi` uses the 2024.2 Intel MPI build.

### GCC 11 and Accretion::rctrl

GCC 11 with LTO fails to link the `ncr-cr-coupling` branch with
`undefined reference to Accretion::rctrl`, just as GCC 13 does on Stellar (see
[../stellar/README.md](../stellar/README.md#gcc-13-and-accretionrctrl)). The GCC builds carry
the one-line fix (`constexpr int Accretion::rctrl;` in `src/particles/accretion.cpp`) as a
local patch in `$HOME/tigris/.worktrees/ncr-cr-coupling` and in the build lanes, so their
`.buildinfo` says `dirty: 1 modified files`. The icpx builds don't need the fix.

## Benchmark (2026-10-03)

Full report with machine specs, charts and the effect of every flag:
https://claude.ai/artifact/UMhHdYzbKcQkKxd4hsjkW2

The workload is defined in `../bench/BENCHMARK_SPEC.md`: each run restarts a production
checkpoint on 4 nodes and advances 200 cycles, built from tigris `eee94bc4f` like the Stellar
and stellarai-amd runs. Times are seconds per cycle, averaged over ranks, median of 3 runs.
Raw results are in `../bench/results/tiger.txt`; `python3 ../bench/summarize.py
../bench/results/tiger.txt` prints the full table. The campaign used 77 benchmark jobs and
8.7 node-hours, including a 4-minute test of the production script.

### Toolchain matrix (starting flags)

| toolchain     | MHD s/cycle | MHD ray tracing | MHD photochem | CRMHD s/cycle | CRMHD integrator | CRMHD photochem |
|---------------|-------------|-----------------|---------------|---------------|------------------|-----------------|
| icpx-impi     | 0.529       | 0.290           | 0.042         | 0.343         | 0.192            | 0.061           |
| icpx2026-impi | 0.529       | 0.289           | 0.043         | 0.348         | 0.190            | 0.063           |
| gcc-impi      | 0.533       | 0.281           | 0.040         | 0.347         | 0.207            | 0.054           |
| icpx          | 0.690 (n=1) | 0.444           | 0.042         | 0.351         | 0.188            | 0.061           |
| gcc           | 0.703 (n=1) | 0.442           | 0.040         | 0.368 (n=1)   | 0.208            | 0.059           |

MHD: `mhd-ncr-8pc/TIGRESS_NCR.00006.rst` (t=300). CRMHD: `crmhd-ncr-8pc/TIGRESS_NCR.00003.rst`
(t=150, CR-NCR coupled). In `../bench/results/tiger.txt`, the icpx rows with these flags are
labelled `variant=preset`.

- Ray tracing dominates MHD (55% of the cycle). Intel MPI makes it 35% faster than Open MPI
  4.1.6 (0.29 vs 0.44 s); MHD is 30% slower with Open MPI. That is more than on Stellar (20%) and much
  less than on stellarai-amd with Open MPI 5 (4x).
- In CRMHD, ray tracing is cheap (0.025 s), and the MPI stacks are within 2%, except that the
  FFT gravity solve is 30% slower with Open MPI (0.043 vs 0.033 s).
- The compilers are close here, unlike on Stellar. GCC 11 is 8-14% slower than icpx in the
  integrator but up to 10% faster in photochemistry (with icpx's default `fp-model=fast`), which
  cancels out. On Stellar, GCC 13 was 2x slower in photochemistry.
- oneAPI 2026.0 is not faster than 2024.2.
- **Node placement matters more than most flags.** 12 of the 76 runs landed on the
  `tiger-i*` racks. MHD runs there were 6-7% faster than the same executable on `tiger-g*`
  racks (e.g. icpx2026-impi 0.499 vs 0.529), about 80% of it in ray tracing; CRMHD runs were
  1-4% faster. Slurm lists the two groups as
  identical hardware, and a job can't choose a group through a feature, so treat differences
  under ~4% as ties.

### Compiler-flag sweep (Intel MPI, `flag_variants.txt`)

Each variant ran once; the top ones ran three times (GCC: twice). All variants pass the
history check.

| compiler | variant | MHD | CRMHD | notes |
|---|---|---|---|---|
| icpx 2024.2 | `fast2` (`-fp-model=fast=2`) | 0.512 | 0.328 | photochemistry 25% faster than `preset`, but it removes NaN checks: benchmark-only |
| | `fast2-v512` (+`-qopt-zmm-usage=high`) | 0.519 | 0.326 | tie |
| | `march` (`-march=sapphirerapids`) | 0.499 | 0.357 | single runs; integrator 7% slower in CRMHD |
| | `preset-v512` | 0.534 | 0.354 | |
| | `precise` | 0.558 | 0.391 | 6-14% slower than `preset` |
| icpx 2026.0 | `fast2` | 0.523 | 0.327 | ties 2024.2 |
| | `preset` | 0.536 | 0.346 | |
| GCC 11.5 | `preset` (fast math, LTO, `-fwhole-program`, prefetch) | 0.533 | 0.347 | the matrix runs |
| | `preset-v512` | 0.522 | 0.362 | ~2% slower than `preset` on like racks; its 0.500 MHD run was on a `tiger-i*` rack |
| | `fast-lto-wp` / `preset-unroll` | 0.532 / 0.534 | 0.345 / 0.350 | tie |
| | `fast-lto` / `fast` (no LTO) / `preset-O2` | 0.533 / 0.545 / 0.514 | 0.359 / 0.369 / 0.374 | single runs; the `preset-O2` MHD run was on a `tiger-i*` rack |
| | `safe-lto` / `O3` (no fast math) | 0.576 / 0.601 | 0.393 / 0.419 | photochemistry 25-40% slower |

Correctness (`../bench/compare_hst.py`, every matrix, sweep and confirmation run): no MHD
history column differs by more than 1e-3 for any build. CRMHD runs differ from the reference
in up to 16 columns by more than 1e-3 and up to 7 by more than 1e-2, and every CRMHD history
has the same 3 NaN columns. Three repeats of the reference executable already differ in 7
columns by more than 1e-2. No build is flagged.

### Recommendation

**icpx-impi** with `FLAGS_ICPX` set to **`-fp-model=fast`** (icpx's default, the `preset`
variant), the same choice as on Stellar. It is the default of `build_tigress.sh --machine=tiger`
and of the production jobs. It runs at **0.529 (MHD) and 0.343 (CRMHD)** s/cycle, or 5.88 and
3.81 node-hours per 10^4 cycles. Compared with the legacy tiger stack (icpx + Open MPI, default
`fp-model`: 0.690 and 0.351), that is 23% less on MHD and 2% less on CRMHD.

The sweep winner `fast2` (`-fp-model=fast=2`; final build 0.510 and 0.328) is **not used for
production**: it lets the compiler assume finite math, so every NaN test in the solver (C2P
floors, CR-FOFC/CRAverage NaN flags, the CR implicit-update revert, the NCR bail-out) compiles
to false. These rare-event safety nets are invisible to the history check above, and `fast2`
gains only 4% here. `fast2-v512` and oneAPI 2026.0 `fast2` are out for the same reason.
See `../README.md`, "Floating-point model"; `build_tigress.sh` refuses such flags outside the
flag sweep.

Per node-hour, an 8 pc run on tiger costs 29% (MHD) and 20% (CRMHD) less than on Stellar
(8.32, 4.79), and 1.8x more than on stellarai-amd (3.24, 2.17).

## Build

```bash
cd $HOME/tigris_scripts/tigress_ncr
bash ./build_tigress.sh --machine=tiger --physics=mhd   --worktree=ncr-cr-coupling   # icpx-impi
bash ./build_tigress.sh --machine=tiger --physics=crmhd --worktree=ncr-cr-coupling
bash ./build_tigress.sh --machine=tiger --cc=all --physics=mhd --worktree=ncr-cr-coupling  # every toolchain
```

An icpx build takes about 1 minute and a GCC build about 15 seconds. The result goes to
`tiger/tigris_ncr_<physics>-fft-<toolchain>.exe`. SSH to GitHub is not set up on tiger; the
worktree was fetched over HTTPS:

```bash
git -C $HOME/tigris fetch https://github.com/PrincetonUniversity/tigris.git \
    ncr-cr-coupling:refs/remotes/origin/ncr-cr-coupling
```

## Run

```bash
cd $HOME/tigris_scripts/tigress_ncr/tiger
sbatch tigress_ncr_mhd_8pc.slurm   -r     # run dir: /scratch/gpfs/EOST/$USER/tigress_ncr/mhd-ncr-8pc
sbatch tigress_ncr_crmhd_8pc.slurm -r     # run dir: /scratch/gpfs/EOST/$USER/tigress_ncr/crmhd-ncr-8pc
CC=gcc-impi sbatch tigress_ncr_crmhd_8pc.slurm -r   # another toolchain
```

These are the env.sh scripts of Stellar (`*_8pc_tc.slurm`) with tiger's partition, paths
and node shape. They default to `DEFAULT_TOOLCHAIN`, and a self-resubmitted segment keeps
the toolchain of the first one. To continue a run from another cluster, copy its checkpoint
into the run directory and use `-r`. See `../README.md` for restart rules.

## Benchmark again

```bash
cd $HOME/tigris_scripts/tigress_ncr
bench/submit.sh tiger mhd icpx-impi 200
nohup bench/run_matrix.sh tiger 200 1 > bench/logs/matrix.log 2>&1 &   # everything
```

To compare toolchains fairly, note which racks each run used
(`sacct -j <job> -X -o NodeList`): `tiger-i*` nodes run MHD 6-7% and CRMHD 1-4% faster than `tiger-g*` nodes.
