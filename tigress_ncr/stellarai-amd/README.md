# TIGRESS-NCR on stellarai-amd

CPU partition `cpu`: 95 nodes, each with 2x AMD EPYC 9475F (Turin, Zen 5), 96 cores and
370 GB. The 8 pc runs (128x128x768, 32^3 blocks, 384 meshblocks) fill exactly 4 nodes with
one block per rank.

Scratch is `/scratch/gpfs/EOST/$USER` (`/scratch/gpfs/$USER` does not exist here); run
directories default to `/scratch/gpfs/EOST/$USER/tigress_ncr/<run>`.

## Toolchains

`env.sh` follows the machine-env contract of `../bench/BENCHMARK_SPEC.md`. It holds the
module stack of each toolchain, plus the slurm/scratch settings and the benchmark checkpoints.
`build_tigress.sh`, the benchmark scripts and the job scripts all source it, and the toolchain
is part of the executable name (`tigris_ncr_<physics>-fft-<cc>.exe`, with a `.buildinfo` next to it).

| `--cc`      | compiler      | MPI               | HDF5 (parallel)                    |
|-------------|---------------|-------------------|------------------------------------|
| `gcc-impi`  | GCC 14        | Intel MPI 2021.18 | hdf5/gcc/intel-mpi/1.14.6          |
| `aocc-impi` | AOCC 5.2      | Intel MPI 2021.18 | hdf5/gcc/intel-mpi/1.14.6 (`I_MPI_CXX=clang++`) |
| `icpx-impi` | oneAPI 2026.0 | Intel MPI 2021.18 | hdf5/oneapi-2026.0/intel-mpi       |
| `aocc`      | AOCC 5.2      | Open MPI 5.0.10   | hdf5/aocc-5.2.0/openmpi-5.0.10     |
| `gcc`       | GCC 14        | Open MPI 5.0.10   | hdf5/gcc/openmpi-5.0.10            |
| `icpx`      | oneAPI 2026.0 | Open MPI 5.0.10   | hdf5/oneapi-2026.0/openmpi-5.0.10  |

All stacks link FFTW from AOCL (`aocl/{gcc,aocc}/ST/5.3.0`); there is no fftw module.

Compiler flags come from env.sh, not from configure.py: each toolchain's complete flag set
(`FLAGS_GCC`, `FLAGS_AOCC`, `FLAGS_ICPX`) replaces the Makefile's `CXXFLAGS`. The sets are
the winners of the flag sweep below. configure.py's `icpx` preset would add `-xhost`, which
on AMD builds a binary that refuses to start ("can only be run on Intel(R) processors").

## Benchmark (2026-10-02/03; stacks re-measured 2026-10-04)

Full report with machine specs, charts and an explanation of every flag:
https://claude.ai/artifact/H1B2iqL3a4F2cjiDQdvvtd

The workload is defined in `../bench/BENCHMARK_SPEC.md`. Each run restarts a Stellar
production checkpoint on 4 nodes and advances 200 cycles; the times are seconds per cycle,
averaged over ranks, from `TIGRESS_NCR.loop_time.txt`. Repeated runs agree within ~0.5-3%.
The runs are not bitwise reproducible, even for one executable, because ray tracing and CR
depend on message order. `../bench/compare_hst.py` checks each build against the spread between
repeats: every stack and flag variant passes, except AOCC `-zopt`, which gives wrong MHD
results. Raw results are in `../bench/results/stellarai-amd.txt`;
`python3 ../bench/summarize.py ../bench/results/stellarai-amd.txt` prints the full table.

Stack matrix, 2026-10-04: `ncr-cr-coupling` 4eea9f80c (iallreduce termination, PR #348), production
flags with NaN checks kept. Median of 4 runs for the GCC stacks and 2 for the others.

| toolchain    | MHD s/cycle | MHD ray tracing | CRMHD s/cycle | CRMHD integrator | CRMHD photochem |
|--------------|-------------|-----------------|---------------|------------------|-----------------|
| **gcc**      | **0.276**   | 0.145           | **0.186**     | 0.106            | 0.029           |
| gcc-impi     | 0.282       | 0.150           | 0.204         | 0.111            | 0.030           |
| aocc         | 0.294       | 0.145           | 0.231         | 0.115            | 0.041           |
| icpx         | 0.305       | 0.142           | 0.263         | 0.140            | 0.046           |
| aocc-impi    | 0.307       | 0.153           | 0.215         | 0.116            | 0.041           |
| icpx-impi    | 0.325       | 0.170           | 0.260         | 0.141            | 0.061           |

Before 2026-10-04 (rma termination, plain `-ffast-math` and icpx `fast=2`): gcc-impi 0.291/0.194,
icpx-impi 0.305/0.256, and the Open MPI stacks 1.16-1.22 s/cycle on MHD.

MHD: `mhd-ncr-8pc/TIGRESS_NCR.00006.rst` (t=300). CRMHD: `crmhd-ncr-8pc/TIGRESS_NCR.00003.rst`
(t=150, CR-NCR coupled, dt=1.2e-4).

- The MPI library no longer matters for MHD. With the old rma termination test, Open MPI took
  ~1.0 s/cycle in ray tracing against ~0.15 s with Intel MPI; changing Open MPI's `osc`
  component (`ucx`, `rdma`) or switching to `pml=ob1` did not help (1.16 to 1.18 s/cycle). The
  cause was the rank-0 `MPI_Fetch_and_op` counter. With `<ray_tracing>/termination = iallreduce`,
  the default since PR #348, every stack traces rays in ~0.15 s/cycle
  (`../bench/reports/rayt-termination-stellarai-amd.md`).
- The compiler matters for CRMHD, where the cycle is compute-bound and ray tracing is cheap
  (~0.015 s). GCC leads. `-fno-finite-math-only` costs AOCC 15-20% in photochemistry
  (0.032 -> 0.041 s/cycle), and icpx with `-fp-model=fast` is ~40% slower than GCC.
- gcc-impi CRMHD runs were bimodal (three at 0.204, one at 0.187 s/cycle); the slow runs spent
  more time in self-gravity and synchronization. gcc (Open MPI) ran 0.185-0.194.
- `--distribution=block:block` vs `block:cyclic` made no difference (within 0.3%).

### Compiler-flag sweep (Intel MPI, `flag_variants.txt`, 3 runs for the top variants)

| compiler | sweep winner | MHD | CRMHD | notes |
|---|---|---|---|---|
| GCC 14 | `preset-v512` | 0.292 | 0.195 | fast-math + LTO variants all tie within noise; plain `-O3` is 8-12% slower |
| AOCC 5.2 | `preset` | 0.299 | 0.198 | `-zopt` miscompiles (rejected); plain `-O3` is 2-13% slower |
| icpx 2026.0 | `fast2` | 0.291 | 0.220 | `-fp-model=fast=2` is 14% faster than the default on CRMHD; `precise` 35-50% slower |

Production flags differ from the sweep winners: since 2026-10-04, `FLAGS_GCC` and `FLAGS_AOCC`
add `-fno-finite-math-only`, and `FLAGS_ICPX` uses `-fp-model=fast` instead of `fast=2`. Plain
`-ffast-math` and `fast=2` assume finite math, which compiles every NaN check in the solver to
false (see `../README.md`, "Floating-point model"). The re-measured cost: none for GCC, 15-20% of
photochemistry for AOCC, and the 14% CRMHD gain of `fast=2` for icpx. Executables built here
before 2026-10-04 have no working NaN checks; rebuild them before further production use.

Recommendation: **gcc** (GCC 14 + Open MPI) with `FLAGS_GCC`, the default of `build_tigress.sh`
and of the production scripts since 2026-10-05. It is the fastest stack, tied with gcc-impi on
MHD and 9% faster on CRMHD. `CC=gcc-impi` remains a good fallback. The snapshot step at the end
of the production jobs loads the gcc-impi stack, because pyathena's mpi4py is linked against
Intel MPI 2021.18 and aborts in `MPI_Init` under the Open MPI modules (tested 2026-10-05).

## Build

```bash
cd $HOME/tigris_scripts/tigress_ncr
bash ./build_tigress.sh --machine=stellarai-amd --physics=mhd   --worktree=ncr-cr-coupling   # gcc
bash ./build_tigress.sh --machine=stellarai-amd --physics=crmhd --worktree=ncr-cr-coupling
bash ./build_tigress.sh --machine=stellarai-amd --cc=all --physics=mhd --worktree=ncr-cr-coupling  # every toolchain
```

Each build takes about 1 minute (`make -j16`) and the result goes to `stellarai-amd/`.

## Run

```bash
cd $HOME/tigris_scripts/tigress_ncr/stellarai-amd
sbatch tigress_ncr_mhd_8pc.slurm   -r     # run dir: /scratch/gpfs/EOST/$USER/tigress_ncr/mhd-ncr-8pc
sbatch tigress_ncr_crmhd_8pc.slurm -r     # run dir: /scratch/gpfs/EOST/$USER/tigress_ncr/crmhd-ncr-8pc
```

With `-r`, the job restarts from `TIGRESS_NCR.final.rst`, or from the newest
`TIGRESS_NCR.NNNNN.rst` when there is no final file. To continue a run from Stellar, put its
checkpoint in the run directory first. A fresh start (no `-r`) refuses to clean a run
directory that contains restart files. The jobs resubmit themselves on the walltime soft
limit. `CC=<toolchain>` and `RUNBASE=<dir>` override the defaults.

The snapshot step at the end needs the `pyathena` conda env, `~/pyathena_master` and
`~/TIGRESS-CR`, which are not on this cluster yet; until then the job skips it.

## Benchmark again

```bash
cd $HOME/tigris_scripts/tigress_ncr
bench/submit.sh stellarai-amd mhd gcc 200
OMPI_MCA_osc=ucx bench/submit.sh stellarai-amd mhd aocc 200      # MPI env vars are recorded
nohup bench/run_matrix.sh stellarai-amd 200 2 > bench/logs/matrix.log 2>&1 &   # everything
```

The QOS allows at most 5 queued jobs per user; `run_matrix.sh` stays under that limit.
