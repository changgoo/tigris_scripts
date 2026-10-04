# Ray-tracing termination test on stellarai-amd (2026-10-04)

HTML version with a phase chart: `rayt-termination-stellarai-amd.html`
(https://claude.ai/artifact/TFxkynUuuBnsAyRy7th79S).

MHD+NCR ran 4x slower with Open MPI 5.0.10 than with Intel MPI (1.18 vs 0.29 s/cycle), and
nearly all of the gap was ray tracing. The ray-tracing author added two runtime options on
branch `rayt-termination-iallreduce` (off `ncr-cr-coupling`, commit 4f309c2):

- `<ray_tracing>/termination = rma | iallreduce`: detect that every ray is done with the
  rank-0 `MPI_Fetch_and_op` counter (default) or with a nonblocking allreduce of
  destroyed-ray counts.
- `<ray_tracing>/comm_timing = true`: per-rank time in each phase of the communication loop
  (trace, send, probe+recv, send-test, termination) and a count of idle polls, written to
  `TIGRESS_NCR.mesh_task_time.txt`.

**Outcome:** iallreduce became the default (`ncr-cr-coupling` PR #348, commit 4eea9f8); the
production executables are built from it. Set `termination = rma` to get the old behavior.

The author asked for four Open MPI runs: baseline, iallreduce, `UCX_RNDV_THRESH=inf`, and
both. Two Intel MPI runs were added for reference.

## Result

200 cycles from `mhd-ncr-8pc/TIGRESS_NCR.00006.rst`, 384 ranks on 4 nodes, GCC 14 with the
`gcc`/`gcc-impi` flags of `../../stellarai-amd/env.sh`, `comm_timing = true` in every run.
Seconds per cycle are rank means from `loop_time.txt`.

| job  | MPI       | termination    | `UCX_RNDV_THRESH` | s/cycle   | ray tracing s/cycle |
|------|-----------|----------------|-------------------|-----------|---------------------|
| 1009 | Open MPI  | rma            | default           | 1.124     | 0.983               |
| 1010 | Open MPI  | **iallreduce** | default           | **0.279** | **0.139**           |
| 1011 | Open MPI  | rma            | inf               | 0.771     | 0.628               |
| 1012 | Open MPI  | iallreduce     | inf               | 0.284     | 0.141               |
| 1013 | Intel MPI | rma            | default           | 0.283     | 0.145               |
| 1014 | Intel MPI | iallreduce     | default           | 0.283     | 0.146               |

## Ray-tracing loop phases

Seconds per ray trace, average over ranks / slowest rank, over 56 traces per run (the first
output window is skipped). The last column is the RayTrace task time per rank per trace.

| job  | trace       | send        | probe+recv  | send-test   | termination     | RayTrace |
|------|-------------|-------------|-------------|-------------|-----------------|----------|
| 1009 | 0.174/0.534 | 0.126/0.476 | 0.130/0.506 | 0.299/1.432 | **2.508/3.178** | 3.336    |
| 1011 | 0.149/0.501 | 0.095/0.402 | 0.096/0.431 | 0.069/0.315 | 1.647/2.001     | 2.130    |
| 1010 | 0.123/0.423 | 0.067/0.080 | 0.069/0.081 | 0.053/0.063 | 0.104/0.129     | 0.470    |
| 1012 | 0.126/0.432 | 0.070/0.082 | 0.070/0.083 | 0.050/0.062 | 0.107/0.132     | 0.479    |
| 1013 | 0.107/0.441 | 0.041/0.051 | 0.194/0.366 | 0.033/0.040 | 0.083/0.115     | 0.492    |
| 1014 | 0.107/0.444 | 0.042/0.051 | 0.202/0.245 | 0.034/0.041 | 0.077/0.095     | 0.495    |

`python3 ../parse_rayt_comm.py <run dirs>` prints this table.

## Findings

- **Termination is the bottleneck.** With rma on Open MPI, ranks spend 2.5 s per trace (3.2 s
  on the slowest rank) in the termination check, against about 0.7 s for all other phases.
  Intel MPI runs the same RMA counter in 0.08 s. The earlier swap of Open MPI's one-sided
  component (`osc=ucx` vs `rdma`) changed nothing because both are slow when 383 ranks poll
  one counter on rank 0.
- **Message protocol is secondary.** `UCX_RNDV_THRESH=inf` helps only with rma (termination
  drops from 2.5 to 1.65 s). With iallreduce it has no effect: 0.279 vs 0.284 s/cycle. UCX
  1.22 chose `dc_mlx5` between nodes and `sysv`/`cma` shared memory within a node in every run.
- **iallreduce is safe as the default on both libraries.** With Intel MPI it runs at 0.283
  s/cycle, the same as rma, and its termination phase is slightly shorter (0.077 vs 0.083 s
  per trace).
- **Load imbalance is the next limit.** With iallreduce, a ray trace takes about 0.47 s per
  rank, close to the slowest rank's trace phase (0.42 s, against a 0.12 s average). Photons
  per rank range from 12 thousand to 4.1 million per output window. Fewer, larger messages
  or pre-posted receives would recover little on this machine; balancing the trace work
  would recover more.
- **Results are unchanged.** The final history rows of all six runs agree with job 1009 in
  every column to better than 1e-3, time step included (`../compare_hst.py`).

Caveats: each configuration ran once; the rma baseline (1.124) agrees with the earlier Open
MPI builds (1.16-1.20 s/cycle). CRMHD was not rerun; it traces rays rarely and showed little
dependence on the MPI library.

## Reproduce

The checkpoint lacks `termination` and `comm_timing`, and a command-line override of a
missing parameter is an error. `INPUT_OVERRIDE` makes the benchmark job read a partial input
file after the restart (`-r start.rst -i athinput.override`):

```bash
bash build_tigress.sh --machine=stellarai-amd --cc=gcc --physics=mhd \
    --worktree=rayt-termination-iallreduce --exe_suffix=rtterm      # and --cc=gcc-impi
O=$PWD/bench/overrides
export VARIANT=rtterm
INPUT_OVERRIDE=$O/rayt_rma_timing.in        UCX_LOG_LEVEL=info bash bench/submit.sh stellarai-amd mhd gcc 200
INPUT_OVERRIDE=$O/rayt_iallreduce_timing.in UCX_LOG_LEVEL=info bash bench/submit.sh stellarai-amd mhd gcc 200
INPUT_OVERRIDE=$O/rayt_rma_timing.in        UCX_LOG_LEVEL=info UCX_RNDV_THRESH=inf bash bench/submit.sh stellarai-amd mhd gcc 200
INPUT_OVERRIDE=$O/rayt_iallreduce_timing.in UCX_LOG_LEVEL=info UCX_RNDV_THRESH=inf bash bench/submit.sh stellarai-amd mhd gcc 200
INPUT_OVERRIDE=$O/rayt_rma_timing.in        bash bench/submit.sh stellarai-amd mhd gcc-impi 200
INPUT_OVERRIDE=$O/rayt_iallreduce_timing.in bash bench/submit.sh stellarai-amd mhd gcc-impi 200
```

Run from `tigress_ncr/`. Result lines are in `../results/stellarai-amd.txt` (jobs 1009-1014);
the run directories were deleted after the test. On `ncr-cr-coupling` after PR #348, the
`rma` override reproduces the old default.
