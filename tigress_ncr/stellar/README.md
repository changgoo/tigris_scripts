# TIGRESS-NCR on Stellar

Intel nodes: 4x Intel Xeon Platinum 8268 (Cascade Lake, 24 cores at 2.9 GHz each, one NUMA
domain per socket), 96 cores and 760 GB per node, AVX-512 with two FMA units, and ConnectX-6
InfiniBand at 100 Gb/s. The login nodes are Cascade Lake too (Xeon Gold 6242R), so builds made
there run on the compute nodes. The 8 pc runs (128x128x768, 32^3
blocks, 384 meshblocks) fill exactly 4 nodes with one block per rank.

Scratch is `/scratch/gpfs/$USER`, and run directories default to
`/scratch/gpfs/$USER/tigress_ncr/<run>`. Slurm picks the QOS from the walltime: jobs of 30
minutes or less go to `stellar-debug` (partition `all`, forced onto Intel nodes, at most 2
running and 10 queued per user). Longer jobs go to `pu-{short,medium,long}-stellar`. The
site's submit filter sets the partition and the account from your group.

## Toolchains

`env.sh` follows the machine-env contract of `../bench/BENCHMARK_SPEC.md`. All stacks use the
site's parallel HDF5 1.14.4 and FFTW 3.3.10 modules.

| `--cc`      | compiler                   | MPI               | HDF5 (parallel)                       |
|-------------|----------------------------|-------------------|---------------------------------------|
| `icpx-impi` | oneAPI 2024.2 icpx         | Intel MPI 2021.13 | hdf5/oneapi-2024.2/intel-mpi/1.14.4   |
| `icpx`      | oneAPI 2024.2 icpx         | Open MPI 4.1.6    | hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 |
| `gcc-impi`  | GCC 13 (`gcc-toolset/13`)  | Intel MPI 2021.13 | hdf5/gcc/intel-mpi/1.14.4             |
| `gcc`       | GCC 13 (`gcc-toolset/13`)  | Open MPI 4.1.6    | hdf5/gcc/openmpi-4.1.6/1.14.4         |

`icpx` is the stack of the legacy Stellar build and the old job scripts (`tigress_ncr_*_8pc.slurm`,
16 pc tests), which also made the benchmark checkpoints. The icpx toolchains use configure's
`clang++` preset only to run configure (mpicxx still calls icpx), so their configure summary
reports `Compiler = clang++`. NVHPC 25.5 is installed but was not tried: nvc++ is not a
contender for CPU-only code on x86, and there is no parallel HDF5 built for it.

## Benchmark (2026-10-03)

Full report with machine specs, charts and the effect of every flag:
https://claude.ai/artifact/3re4pmVb3w7LYwZw5S3GL6

The workload is defined in `../bench/BENCHMARK_SPEC.md`: each run restarts a production
checkpoint on 4 nodes and advances 200 cycles, built from tigris `eee94bc4f` like the
stellarai-amd runs. Times are seconds per cycle, averaged over ranks, median of 3 runs for the
top two toolchains (repeats agree within 1-3%). Raw results are in
`../bench/results/stellar.txt`; `python3 ../bench/summarize.py ../bench/results/stellar.txt`
prints the full table.

| toolchain     | MHD s/cycle | MHD ray tracing | MHD photochem | CRMHD s/cycle | CRMHD integrator | CRMHD photochem |
|---------------|-------------|-----------------|---------------|---------------|------------------|-----------------|
| icpx-impi     | 0.749       | 0.452           | 0.045         | 0.431         | 0.218            | 0.064           |
| icpx          | 0.870       | 0.564           | 0.045         | **0.420**     | 0.215            | 0.064           |
| gcc-impi      | 0.820       | 0.433           | 0.082         | 0.514         | 0.231            | 0.122           |
| gcc           | 0.931       | 0.563           | 0.082         | 0.500         | 0.228            | 0.123           |

MHD: `mhd-ncr-8pc/TIGRESS_NCR.00006.rst` (t=300). CRMHD: `crmhd-ncr-8pc/TIGRESS_NCR.00003.rst`
(t=150, CR-NCR coupled). These rows all use the starting flags (icpx: configure's preset with
`-xCASCADELAKE`). The flag sweep below then made icpx-impi 1-4% faster.

- Ray tracing dominates MHD (60% of the cycle). Intel MPI makes it 20% faster than Open MPI
  4.1.6 (0.45 vs 0.56 s), which is much less than the 4x on stellarai-amd with Open MPI 5.
- In CRMHD, ray tracing is cheap (0.04 s), and the two MPIs are within 3%, which is about the noise.
- Unlike on Zen 5, GCC loses here: GCC 13 is 2x slower than icpx in NCR photochemistry
  (`pchem`) and 6-8% slower in the integrator. A likely cause, not checked, is that icpx
  vectorizes the photochemistry's `exp`/`log`/`pow` calls with SVML.
- Correctness (`../bench/compare_hst.py`, for every matrix, sweep and confirmation run): no
  MHD history column differs by more than 1e-3 for any build. CRMHD runs differ from the
  reference in 8-13 columns by more than 1e-3 (2-6 by more than 1e-2), and every CRMHD history
  has the same 3 NaN columns. Two repeats of the reference executable already differ in 12
  columns, and on stellarai-amd repeats of one executable reached 6 columns above 1e-2 (ray
  tracing and CR depend on message order). No build is flagged.

### Compiler-flag sweep (Intel MPI, `flag_variants.txt`)

Each variant ran once, and the top icpx variants three times. All variants pass the history
check.

| compiler | variant | MHD | CRMHD | notes |
|---|---|---|---|---|
| icpx 2024.2 | **`fast2`** (`-fp-model=fast=2`) | **0.740** | **0.416** | NCR photochemistry 16% faster than the default `fp-model=fast` (0.749, 0.431) |
| | `march` (`-march=cascadelake` for `-xCASCADELAKE`) | 0.748 | 0.445 | |
| | `precise` | 0.763 | 0.479 | only 2-11% slower (35-70% on Zen 5) |
| | `-qopt-zmm-usage=high` | 0.793 | 0.447 | full 512-bit vectors are slower |
| | no `-ipo` | | | does not link: `omp declare simd` variants of functions in other files are not emitted |
| GCC 13 | `preset` (fast math, LTO, `-fwhole-program`, prefetch) | 0.822 | 0.512 | `fast-lto`, `fast-lto-wp` and `-funroll-loops` tie within 2% |
| | `preset-v512` | 0.841 | 0.546 | 512-bit vectors are 3-6% slower, unlike on Zen 5 |
| | `fast` (no LTO) / `preset-O2` | 0.854 / 0.865 | 0.550 / 0.550 | |
| | `safe-lto` / `O3` (no fast math) | 0.965 / 1.019 | 0.621 / 0.667 | photochemistry 60% slower |

Recommendation: **icpx-impi** with `FLAGS_ICPX` (the `fast2` variant). It is the fastest stack
for both physics. It is the default of `build_tigress.sh --machine=stellar` and of the
`*_8pc_tc.slurm` jobs. The final build, rebuilt from `env.sh`, reran at 0.734 (MHD) and
0.407 (CRMHD) s/cycle, so the median of 4 is **0.737 and 0.411**, or 8.2 and 4.6 node-hours
per 10^4 cycles. Compared with the old production build (icpx + Open MPI, default
`fp-model`, 0.870 and 0.420), that is 15% less on MHD and 2% less on CRMHD.

The rows of `../bench/results/stellar.txt` labelled `icpx:preset`/`icpx-impi:preset` with job
IDs up to 2952058 are the matrix runs. They were built with the flags in use before the sweep
(identical to `preset`), and were relabelled from `default` when `FLAGS_ICPX` changed.
`default` rows of the icpx toolchains are runs of the final flags.

## Build

```bash
cd $HOME/tigris_scripts/tigress_ncr
bash ./build_tigress.sh --machine=stellar --physics=mhd   --worktree=ncr-cr-coupling   # icpx-impi
bash ./build_tigress.sh --machine=stellar --physics=crmhd --worktree=ncr-cr-coupling
bash ./build_tigress.sh --machine=stellar --cc=all --physics=mhd --worktree=ncr-cr-coupling  # every toolchain
```

An icpx build takes 3-4 minutes, most of it in the single-threaded IPO link. The result goes to
`stellar/tigris_ncr_<physics>-fft-<toolchain>.exe`.

### GCC 13 and Accretion::rctrl

The GCC toolchains do not link the current `ncr-cr-coupling` branch:

```
undefined reference to `Accretion::rctrl'
```

`src/particles/accretion.hpp` declares `static constexpr int rctrl = 1;`, and
`ResolveControlVolumeExtent()` in `src/feedback/radiation_sources.cpp` passes it to
`std::max`, which takes its arguments by reference. In C++11 that requires a definition at
namespace scope, and the code doesn't have one. icpx and GCC 14 (stellarai-amd) inline the value
anyway; GCC 13 with LTO does not. The fix is one line in `src/particles/accretion.cpp`:

```cpp
constexpr int Accretion::rctrl;
```

The benchmark GCC builds have this line as a local patch (their `.buildinfo` says
`dirty: 1 modified files`). The icpx default is not affected.

## Run

```bash
cd $HOME/tigris_scripts/tigress_ncr/stellar
sbatch tigress_ncr_mhd_8pc_tc.slurm   -r     # run dir: /scratch/gpfs/$USER/tigress_ncr/mhd-ncr-8pc
sbatch tigress_ncr_crmhd_8pc_tc.slurm -r     # run dir: /scratch/gpfs/$USER/tigress_ncr/crmhd-ncr-8pc
CC=icpx sbatch tigress_ncr_crmhd_8pc_tc.slurm -r   # another toolchain
```

These are the env.sh versions of `tigress_ncr_{mhd,crmhd}_8pc.slurm`, the same as the
stellarai-amd scripts. They default to `DEFAULT_TOOLCHAIN`, and a self-resubmitted segment
keeps the toolchain of the first one. The old scripts stay as they were (icpx + Open MPI,
`tigris_ncr_<physics>-fft.exe`). Both use the same run directory, so `-r` with the new script
continues a run the old script started. See `../README.md` for restart rules.

## Benchmark again

```bash
cd $HOME/tigris_scripts/tigress_ncr
bench/submit.sh stellar mhd icpx-impi 200
I_MPI_FABRICS=shm:ofi bench/submit.sh stellar mhd icpx-impi 200    # MPI env vars are recorded
nohup bench/run_matrix.sh stellar 200 1 > bench/logs/matrix.log 2>&1 &   # everything
```

Benchmark jobs run 30 minutes or less, so they go to `stellar-debug`. `SLURM_QUEUE_FILTER` in
`env.sh` makes `run_matrix.sh` and `flag_sweep.sh` count only those jobs against the
10-job limit, not your production jobs.
