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

## Benchmark (2026-10-02/03)

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

| toolchain   | MHD s/cycle | MHD ray tracing | CRMHD s/cycle | CRMHD integrator |
|-------------|-------------|-----------------|---------------|------------------|
| **gcc-impi**| **0.291**   | 0.153           | **0.194**     | 0.109            |
| icpx-impi   | 0.305       | 0.158           | 0.256         | 0.139            |
| aocc        | 1.161       | 1.023           | 0.197         | 0.111            |
| gcc         | 1.205       | 1.065           | 0.198         | 0.106            |
| icpx        | 1.216       | 1.046           | 0.256         | 0.135            |

MHD: `mhd-ncr-8pc/TIGRESS_NCR.00006.rst` (t=300). CRMHD: `crmhd-ncr-8pc/TIGRESS_NCR.00003.rst`
(t=150, CR-NCR coupled, dt=1.2e-4).

- MPI dominates the MHD run: with Open MPI, ray tracing takes ~1.0 s/cycle; with Intel MPI it takes ~0.15 s.
  Ray tracing passes photons with asynchronous point-to-point messages and counts finished
  rays with `MPI_Fetch_and_op` on rank 0. Changing Open MPI's `osc` component (`ucx`,
  `rdma`) or switching to `pml=ob1` did not help (1.16 to 1.18 s/cycle). The cause is that
  rank-0 counter: with `<ray_tracing>/termination = iallreduce` (branch
  `rayt-termination-iallreduce`), Open MPI runs at 0.279 s/cycle and Intel MPI is unchanged
  (0.283). See `../bench/reports/rayt-termination-stellarai-amd.md`.
- The compiler matters for CRMHD, where the cycle is compute-bound and ray tracing is cheap
  (~0.015 s): GCC and AOCC are ~25% faster than icpx in the integrator.
- `--distribution=block:block` vs `block:cyclic` made no difference (within 0.3%).

### Compiler-flag sweep (Intel MPI, `flag_variants.txt`, 3 runs for the top variants)

| compiler | chosen variant | MHD | CRMHD | notes |
|---|---|---|---|---|
| GCC 14 | `preset-v512` | 0.292 | 0.195 | fast-math + LTO variants all tie within noise; plain `-O3` is 8-12% slower |
| AOCC 5.2 | `preset` | 0.299 | 0.198 | `-zopt` miscompiles (rejected); plain `-O3` is 2-13% slower |
| icpx 2026.0 | `fast2` | 0.291 | 0.220 | `-fp-model=fast=2` is 14% faster than the default on CRMHD; `precise` 35-50% slower |

Recommendation: use **gcc-impi** with `FLAGS_GCC`. It is the default of `build_tigress.sh` and
of the production scripts. The final build reran at 0.291 (MHD) and 0.198 (CRMHD) s/cycle.

## Build

```bash
cd $HOME/tigris_scripts/tigress_ncr
bash ./build_tigress.sh --machine=stellarai-amd --physics=mhd   --worktree=ncr-cr-coupling   # gcc-impi
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
bench/submit.sh stellarai-amd mhd gcc-impi 200
OMPI_MCA_osc=ucx bench/submit.sh stellarai-amd mhd aocc 200      # MPI env vars are recorded
nohup bench/run_matrix.sh stellarai-amd 200 1 > bench/logs/matrix.log 2>&1 &   # everything
```

The QOS allows at most 5 queued jobs per user; `run_matrix.sh` stays under that limit.
