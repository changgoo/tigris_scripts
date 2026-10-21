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

Measured on 2026-10-20, before the `FI_MR_CACHE_MONITOR=memhooks` fix (see "Slow
self-gravity" below). The fix speeds up communication for every toolchain alike, so the
ranking holds, but the absolute numbers are from the old default.

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

## Flag sweep (fresh start, CRMHD with sparse gravity; before the memhooks fix)

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

## Restart checkpoints (cross-machine; gcc, `FI_MR_CACHE_MONITOR=memhooks`)

Re-measured on 2026-10-21 with the memhooks default (jobs 252366, 252367); the numbers from
2026-10-20, before the fix, are in brackets.

| physics | layout | n | s/cycle | node-h/1e4 | tint | grav | rayt | pchem | ops |
|---|---|---|---|---|---|---|---|---|---|
| mhd | 2 x 192 | 3 | 0.400 [0.472] | 2.22 [2.62] | 0.108 | 0.022 [0.089] | 0.203 | 0.031 | 0.024 |
| crmhd | 2 x 192 | 3 | 0.278 [0.349] | 1.54 [1.94] | 0.164 | 0.023 [0.091] | 0.021 | 0.044 | 0.020 |
| mhd | 4 x 96 | 2 | 0.319 [0.394] | 3.54 [4.38] | 0.073 | 0.017 | 0.173 | 0.028 | 0.020 |
| crmhd | 4 x 96 | 2 | 0.209 [0.264] | 2.32 [2.93] | 0.113 | 0.019 | 0.020 | 0.040 | 0.014 |

- Per node-hour, Athena on 2 nodes is the most efficient machine: stellarai-amd 3.07 / 2.07,
  tiger 5.88 / 3.81, stellar 8.32 / 4.79 (MHD / CRMHD node-h per 10^4 cycles).
- 4 nodes are faster per cycle but take 1.5-1.6x more node-hours. **Use 2 nodes.**
- gcc-mpich9 (cray-mpich 9.0.1) still ties: mhd 0.394, crmhd 0.283 on 2 nodes. gcc stays
  the default. The compute-bound ranking of the other toolchains (fresh-start matrix above)
  does not depend on the network fix, so it was not re-run.

The CRMHD checkpoint has 9 NaN history columns for every run: the passive-scalar totals
(`0/1/2-scalar`) and the new floor/ceiling columns of those scalars (`ds*_floor`,
`ds*_ceil`). The fresh start has none, so the NaNs come from the checkpoint's state.

## Sparse gravity for CRMHD

`gravity/solve_grav_hyperbolic_dt=true` solves self-gravity once per hyperbolic (MHD) time
step instead of every cycle. The tigress_classic CR runs use it; the TIGRESS-NCR input and
both checkpoints have `false`, so every number above and in §6 solves gravity every cycle.

| CRMHD, gcc | every cycle | sparse | gain |
|---|---|---|---|
| fresh start (512 ranks), before the fix | 0.433 | 0.279 | -36% |
| restart (384 ranks), before the fix | 0.349 | 0.271 | -22% |
| restart (384 ranks), memhooks | 0.278 | 0.260 | -6% |

With the cheaper gravity solve the gain is small. The sparse runs stay within the
run-to-run envelope of the history check. `tigress_ncr_crmhd_8pc.pbs` turns it on with
`-v SPARSE_GRAV=1`; it is off by default.

## Slow self-gravity: the libfabric MR cache monitor (solved 2026-10-21)

At the same layout as stellarai-amd (4 nodes x 96), `grav` took 0.069-0.073 s/cycle against
0.020 there, while hydro (`tint`) was within 10%. The diagnosis, all on branch `grav-profile`:

1. **Per-phase profile** (`gravity/profile_gravity=true`, `bench/parse_grav_profile.py`):
   94-98% of the solve and of the gap is in Forward + Backward, the six fftMPI remaps per
   solve. The shear remap, kernel and phi boundary exchange take ~4 ms. stellarai-amd at
   the same commit: Forward 0.0089 / Backward 0.0060 against Athena 0.0330 / 0.0310.
2. **fftMPI collective mode** (tigris branch `fftmpi-collective`, `<gravity>/fft_collective`):
   point-to-point only, all-to-all only and the default are all the same.
3. **OSU** (`bench/osu_net.pbs`, `bench/results/osu-athena.md`): large messages run at line
   rate (24 GB/s per pair, 49 GB/s per node on 2 NICs). For 4-64 KB messages each Cassini
   NIC sent only ~230K messages/s, so a node moved 7.5 GB/s at 16 KB and a 192-rank
   alltoall of 4-16 KB took 41.6 ms. stellarai-amd (one ConnectX-7 NDR) sends 3.0M msg/s at
   16 KB and runs at line rate from 4 KB (`bench/results/osu-stellarai-amd.md`).
4. **libfabric settings** (job 252364, CRMHD restart, 4 x 96, profiled):

   | setting | grav | Forward | Backward | s/cycle |
   |---|---|---|---|---|
   | default (`userfaultfd` monitor) | 0.0727 | 0.0355 | 0.0309 | 0.264 |
   | `FI_MR_CACHE_MONITOR=memhooks` | 0.0190 | 0.0093 | 0.0055 | 0.207 |
   | HPE libfabric 2.3.1 (`hpe-libfabric` module) preloaded | 0.0192 | 0.0093 | 0.0056 | 0.208 |
   | `FI_MR_CACHE_MONITOR=disabled` | 0.0727 | 0.0355 | 0.0309 | 0.264 |
   | `FI_CXI_RDZV_THRESHOLD=262144` / `FI_CXI_RDZV_PROTO=alt_read` | 0.0730 | 0.0358 | 0.0309 | 0.276 / 0.265 |

   With memhooks, OSU runs at line rate from 4 KB (12M msg/s at 4 KB; alltoall 0.85 ms at
   4 KB and 3.5 ms at 16 KB, as fast as stellarai-amd).

The executables load the OS libfabric (`/lib64/libfabric.so.1`, rpm libfabric-2.6.0), whose
default memory-registration cache monitor is userfaultfd. With it, the cache behaves like no
cache at all (`disabled` is exactly as slow). `env.sh` now exports
`FI_MR_CACHE_MONITOR=memhooks` in `load_toolchain`, and the tigress_classic Athena scripts
(`../../tigress_classic/nasa_athena/`) export it too. Ruled out on the way: the compiler, the
FFT library (MKL's FFTW3 interface), `MPICH_ALLTOALLV_THROTTLE=32`,
`MPICH_SMP_SINGLE_COPY_MODE=CMA`, `MPICH_OFI_NIC_POLICY=NUMA`, `FI_CXI_RX_MATCH_MODE=hybrid`,
`MPICH_SHARED_MEM_COLL_OPT=0`. A draft ticket for NAS support is in
`nas_ticket_mr_cache_monitor.md`.

## Recommendation

`gcc` (GCC 14.2 + cray-mpich 8.1.33) with `FLAGS_GCC` and `FI_MR_CACHE_MONITOR=memhooks`
(set by `env.sh`), 384 ranks on 2 nodes for the 8 pc runs. Sparse gravity is now only a 6%
gain for CRMHD.

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

Campaign cost: 113.5 SBU on 2026-10-20 (smoke 0.9, matrix 58.9, sweep + restarts 35.9, MPI
probes 6.6, 4-node probe 5.2, MKL probe 4.2, production-script test 1.4, a cancelled job 0.4),
plus 21.3 SBU on 2026-10-21 for the gravity diagnosis and re-measurement (gravity profiles 3.5,
fft_collective 1.8, OSU 2.6, libfabric settings 4.4, re-measurement 9.1). Total ~135 SBU.
