# TIGRESS-NCR on NASA Athena (Turin nodes)

Benchmark of 2026-10-20, following `../bench/BENCHMARK_SPEC.md` with PBS in place of Slurm.
Source: `production-diagnostics` at `23071491f` (worktree
`~/tigris/.worktrees/production-diagnostics`). The other machines in §6 of the spec ran
`4eea9f80c`/`eee94bc4f`, so the cross-machine numbers compare different commits.

## Hardware and environment

- PBS `model=tur_ath`: 2x AMD EPYC 9745 (Zen 5c, 2.4 GHz), 256 cores/node (SMT on), 768 GB,
  2 NUMA domains, 16 CCDs x 16 cores; HPE Slingshot 11 (2 Cassini NICs per node).
- HPE Cray PE 25.09, Environment Modules 3.2 (change versions with `module swap`).
- Only cray-mpich runs on Athena. Parallel HDF5 and FFTW come from `cray-hdf5-parallel` and
  `cray-fftw`; the compiler is the Cray wrapper `CC` (`MPI_CXX` in `env.sh`).
- Queues: `devel` (2 h, 1 queued + 1 running job per user), `normal` (8 h), `long`.
  SBUs = nodes x hours x 12.19 (allocation `s2800`, `acct_ytd -z`).
- `~/.bashrc` activates `~/myenv`, whose pip-installed MPICH (`mpicxx`, `mpiexec`) shadows the
  Cray tools. `load_toolchain` drops it from PATH and the launcher is PALS `mpiexec` by
  absolute path.

## Workloads

| workload | what | ranks | layout |
|---|---|---|---|
| `fresh` (toolchain search) | `athinput.tigress_ncr` from t=0, 8 pc, 128x128x1024 (z = ±4096 pc), 32³ blocks, `rseed=1`, production RT settings; CRMHD with `cr/photchem_flag=1` | 512 | 2 full nodes |
| `rst` (cross-machine) | the 8 pc checkpoints of §1, unchanged | 384 | 2 nodes x 192, 12 per CCD |

Both advance 200 cycles; s/cycle is the rank mean of `All` in `loop_time.txt`.

## Toolchains (fresh start, gravity every cycle, 3 repeats)

| toolchain | stack | mhd s/cycle | crmhd s/cycle |
|---|---|---|---|
| **gcc** (default) | GCC 14.2 + cray-mpich 8.1.33 | 0.436 | 0.433 |
| gcc-mpich9 | GCC 14.2 + cray-mpich 9.0.1 | 0.433 | 0.433 |
| aocc | AOCC 5.0 + cray-mpich 8.1.33 | 0.473 | 0.464 |
| icpx | oneAPI 2025.3 + cray-mpich 8.1.33 | 0.465 | 0.510 |
| cce | CCE 20 + cray-mpich 8.1.33 | 2.80 | 1.48 |

- gcc and gcc-mpich9 tie; gcc is the default because it needs no module swap.
- **CCE is rejected: it miscompiles.** Its MHD time step departs from the other compilers by
  cycle 10 (t = 0.50 instead of 0.27 after 200 cycles), and 35-39 CRMHD history columns are
  off. It is also 3-6x slower, all of it in NCR photochemistry (`pchem` 0.40 vs 0.02).
- One aocc crmhd run returned rc=127 after finishing all 200 cycles: PALS failed at exit
  ("ping failed ... Application not found"), not the code.

## Flag sweep (fresh start, CRMHD with sparse gravity)

`flag_variants.txt`, one run per variant; CCE left out.

- GCC: `preset` (= `FLAGS_GCC`), `preset-v512` and `fast-lto` tie within 1% (mhd 0.433-0.437,
  crmhd 0.278-0.280). Fast math + LTO is worth 7% (mhd) / 15% (crmhd) over plain `-O3`;
  `safe-lto` (no fast math) is 4% / 9% slower than `preset`.
- AOCC: all fast-math variants tie, 6% (mhd) / 11% (crmhd) behind GCC.
- icpx: `fast2` is 6% faster than `preset` but removes the NaN checks; `precise` is 29% / 56%
  slower than GCC.
- `FLAGS_*` are unchanged from the starting sets.

Correctness (`compare_hst.py`): every MHD variant matches the gcc reference in all history
columns; CRMHD variants differ in at most 2 columns by more than 1e-2, the same as
run-to-run noise. None is SUSPECT except CCE.

## Restart checkpoints (cross-machine; gcc, 2 nodes)

| physics | n | s/cycle | node-h/1e4 | tint | grav | rayt | pchem | ops |
|---|---|---|---|---|---|---|---|---|
| mhd | 4 | 0.472 | 2.62 | 0.108 | 0.089 | 0.207 | 0.030 | 0.026 |
| crmhd | 3 | 0.349 | 1.94 | 0.164 | 0.091 | 0.022 | 0.044 | 0.021 |

Per node-hour, Athena is the most efficient machine so far (stellarai-amd 3.07 / 2.07, tiger
5.88 / 3.81, stellar 8.32 / 4.79). On 4 nodes (96 ranks each, stellarai-amd's layout)
the runs are faster but cost more per cycle: mhd 0.394 s (4.38 node-h/1e4), crmhd 0.264 s
(2.93). **Use 2 nodes.**

The CRMHD checkpoint has 9 NaN history columns for every run: the passive-scalar totals
(`0/1/2-scalar`) and the new floor/ceiling columns of those scalars (`ds*_floor`,
`ds*_ceil`). The fresh start has none, so the NaNs come from the checkpoint's state.

## Sparse gravity for CRMHD

`gravity/solve_grav_hyperbolic_dt=true` solves self-gravity once per hyperbolic (MHD) time
step instead of every cycle. The tigress_classic CR runs use it; the TIGRESS-NCR input and
both checkpoints have `false`, so every number above and in §6 solves gravity every cycle.

| CRMHD, gcc | every cycle | sparse | gain |
|---|---|---|---|
| fresh start (512 ranks) | 0.433 | 0.279 | -36% |
| restart (384 ranks) | 0.349 | 0.271 | -22% |

The sparse runs stay within the run-to-run envelope of the history check.
`tigress_ncr_crmhd_8pc.pbs` turns it on with `-v SPARSE_GRAV=1`; it is off by default.

## Open: slow self-gravity

At the same layout as stellarai-amd (4 nodes x 96), `grav` takes 0.069-0.073 s/cycle against
0.020-0.023 there, while hydro (`tint`) is within 10%. It does not depend on the compiler
or on the FFT library (MKL's FFTW3 interface instead of cray-fftw: same time). None of
these changes it: `MPICH_ALLTOALLV_THROTTLE=32`, `MPICH_SMP_SINGLE_COPY_MODE=CMA`,
`MPICH_OFI_NIC_POLICY=NUMA`, `FI_CXI_RX_MATCH_MODE=hybrid`, `MPICH_SHARED_MEM_COLL_OPT=0`.
It grows with the rank count (fresh 512 ranks: 0.155). So the fftMPI remaps
(point-to-point + `MPI_Alltoallv`) are slow on Slingshot/cray-mpich. The next step is an MPI
profile (CrayPat) of the gravity solve.

## Recommendation

`gcc` (GCC 14.2 + cray-mpich 8.1.33) with `FLAGS_GCC`, 384 ranks on 2 nodes for the 8 pc
runs. For CRMHD, consider `SPARSE_GRAV=1`.

## Build and run

```bash
cd ~/tigris_scripts/tigress_ncr
bash build_tigress.sh --machine=athena --physics=crmhd --worktree=production-diagnostics   # default gcc
cd athena
qsub tigress_ncr_crmhd_8pc.pbs                                    # fresh start
qsub -v STARTFLAG=-r tigress_ncr_crmhd_8pc.pbs                    # restart, chains itself
qsub -v STARTFLAG=-r,SPARSE_GRAV=1 tigress_ncr_crmhd_8pc.pbs      # with sparse gravity
```

Benchmark runs (bundled into one PBS job; dry run without `--submit`):

```bash
bench/pbs_submit.sh athena --workload=fresh --repeats=3 --lanes=10 matrix
bench/pbs_submit.sh athena --workload=rst mhd:gcc crmhd:gcc crmhd:gcc::gravity/solve_grav_hyperbolic_dt=true
python3 bench/summarize.py bench/results/athena-fresh.txt     # fresh-start search
python3 bench/summarize.py bench/results/athena.txt           # restart
```

The production scripts were tested with a 4-minute CRMHD restart (`-v STARTFLAG=-r,NO_CHAIN=1`):
it ran 539 cycles, stopped on the soft limit with exit code 3 and did not resubmit.

Campaign cost: 113.5 SBU (smoke 0.9, matrix 58.9, sweep + restarts 35.9, MPI probes 6.6,
4-node probe 5.2, MKL probe 4.2, production-script test 1.4, a cancelled job 0.4).
