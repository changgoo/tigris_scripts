# Draft NAS support ticket (to support@nas.nasa.gov)

**Subject:** Athena Turin: default libfabric MR cache monitor (userfaultfd) limits MPI medium-message rate to ~230K msg/s per NIC

---

Hello,

On the Athena Turin nodes (model=tur_ath), MPI messages of about 4-64 KB run at a fraction of
the expected rate with the default software stack. Setting `FI_MR_CACHE_MONITOR=memhooks`, or
using HPE's libfabric from the `hpe-libfabric/2.3.1` module, removes the problem. Our FFT-based
solver gets 3.8x faster with either one. We are reporting it because other users are probably
affected, and we would like to know which setting you recommend.

## Environment

- User ckim14, group s2800; queue devel; `-l select=2:ncpus=256:model=tur_ath`,
  `-l place=scatter:excl`
- PrgEnv-gnu 8.6.0 (GCC 14.2), cray-mpich 8.1.33, craype-network-ofi, cray-pals 1.7.1,
  `FI_PROVIDER=cxi`, `OMP_NUM_THREADS=1`
- The executables load the OS libfabric: `/lib64/libfabric.so.1` -> `libfabric-2.6.0-3.t5`
  (rpm), with `cray-libcxi-13.1.0-1.t5`. The domains are cxi0 and cxi1, and transparent huge
  pages are `[always]`.
- Test nodes: x1001c0s2b0n0 and x1001c0s2b0n1 (same chassis), among others.

## What we measured

OSU micro-benchmarks 7.5, built with `cc`/`CC` from the stack above, between two nodes.
Rank i on node 0 is paired with rank i+ppn on node 1.

**osu_mbw_mr, default settings** (PBS job 252363):

| message size | 96 pairs/node, msg/s | 192 pairs/node, msg/s | 96 pairs, `MPICH_OFI_NUM_NICS=1`, msg/s | 96 pairs, MB/s |
|---|---|---|---|---|
| 4 KB | 463K | 471K | 231K | 1,898 |
| 16 KB | 457K | 470K | 229K | 7,491 |
| 32 KB | 452K | 461K | 216K | 14,806 |
| 64 KB | 441K | 447K | 205K | 28,913 |
| 128 KB | 369K | 370K | 185K | 48,344 |
| 1 MB | 47K | 47K | 23K | 48,996 |

- Large messages reach line rate (one pair 24 GB/s; 96 pairs 49 GB/s on both NICs), with 0
  network timeouts reported.
- From 1 KB to 64 KB, the aggregate message rate is flat at ~460K msg/s per node. It does not
  change between 96 and 192 pairs, and it halves with one NIC: about 230K msg/s per NIC.
- `osu_alltoall` over 192 ranks (2 x 96) takes 41.6 ms at 4 KB and 41.8 ms at 16 KB.
- On an InfiniBand NDR cluster at Princeton (one ConnectX-7, 400 Gb/s per node, Open MPI
  5.0.10 and Intel MPI 2021.18), the same tests give 3.0M msg/s at 16 KB, line rate from
  4 KB, and an all-to-all of 1.25 ms at 4 KB and 3.5 ms at 16 KB.

**The same tests with `FI_MR_CACHE_MONITOR=memhooks`** (PBS job 252368, otherwise identical):

| message size | 96 pairs/node, msg/s (default -> memhooks) | 96 pairs, MB/s (default -> memhooks) | alltoall 192 ranks, ms (default -> memhooks) |
|---|---|---|---|
| 4 KB | 463K -> 12.1M | 1,898 -> 49,431 | 41.6 -> 0.85 |
| 16 KB | 457K -> 3.03M | 7,491 -> 49,572 | 41.8 -> 3.47 |
| 64 KB | 441K -> 737K | 28,913 -> 48,311 | 168 -> 13.8 |
| 128 KB | 369K -> 371K | 48,344 -> 48,679 | 337 -> 27.6 |

- With memhooks, many pairs reach line rate from 4 KB, and the all-to-all is 12-50x faster
  at 4-64 KB.
- One pair between nodes goes from 668 to 10,301 MB/s at 4 KB and from 2,571 to 21,395 MB/s
  at 16 KB.

**Cassini counters** (`MPICH_OFI_CXI_COUNTER_REPORT=2`, 192 pairs, default settings), mean
per second: `hni_rx_paused_0/1` about 0.5M/1.3M, `atu_cache_evictions` about 53K,
`parbs_tarb_pi_posted_blocked_cnt` about 3e8, and `lpe_net_match_overflow_0` up to 31K.

## Application impact and the settings we tried

The application is TIGRESS, an Athena++-based MHD code. Its self-gravity solver does six FFT
pencil transposes per solve with fftMPI (16-128 KB point-to-point messages plus
`MPI_Alltoallv`). We ran it with 384 ranks on 4 nodes x 96, restarting the same checkpoint
for 200 cycles (PBS job 252364). Gravity solve time in s/cycle, rank mean:

| setting | gravity s/cycle | whole step s/cycle |
|---|---|---|
| default | 0.0727 | 0.264 |
| `FI_MR_CACHE_MONITOR=memhooks` | **0.0190** | **0.207** |
| `LD_PRELOAD` of libfabric.so.1 from `hpe-libfabric/2.3.1` | **0.0192** | **0.208** |
| `FI_MR_CACHE_MONITOR=disabled` | 0.0727 | 0.264 |
| `FI_CXI_RDZV_THRESHOLD=262144` | 0.0730 | 0.276 |
| `FI_CXI_RDZV_PROTO=alt_read` | 0.0730 | 0.265 |

The same solver takes 0.020 s/cycle on the Princeton NDR cluster. Earlier tests that also made
no difference: `MPICH_ALLTOALLV_THROTTLE=32`, `MPICH_SMP_SINGLE_COPY_MODE=CMA`,
`MPICH_OFI_NIC_POLICY=NUMA`, `FI_CXI_RX_MATCH_MODE=hybrid`, `MPICH_SHARED_MEM_COLL_OPT=0`,
fftMPI's point-to-point-only and all-to-all-only modes, and a different FFT library.

## Questions

1. Is it intended that cray-mpich on the Turin nodes loads the OS libfabric 2.6.0 (TOSS rpm)
   rather than HPE's Slingshot libfabric? With the OS library, the userfaultfd monitor is the
   default, and the results above suggest its registration cache does not work.
   `FI_MR_CACHE_MONITOR=disabled` performs exactly like the default.
2. Would you consider making `FI_MR_CACHE_MONITOR=memhooks` (or kdreg2, which is not loaded on
   the nodes) or the HPE libfabric the system default, or documenting it in the "Preparing to
   run on Athena Turin nodes" article?
3. Every job prints `PE 0: Launcher/PMI did not supply NIC data (node_idx=0, rc=0,
   num_pmi_nics=0)`. Both NICs are used and reach line rate, so this looks harmless. Can you
   confirm?

## How to reproduce

```bash
# PrgEnv-gnu, cray-mpich 8.1.33, cray-pals; OSU 7.5 configured with CC=cc CXX=CC
export FI_PROVIDER=cxi OMP_NUM_THREADS=1
mpiexec -n 192 --ppn 96 --cpu-bind list:<6 cores per CCD> osu_mbw_mr -m1024:1048576
FI_MR_CACHE_MONITOR=memhooks mpiexec -n 192 --ppn 96 ... osu_mbw_mr -m1024:1048576
mpiexec -n 192 --ppn 96 ... osu_alltoall -m4096:131072 -i20 -x5
```

The full outputs and job scripts are available if useful.

Thank you,
Chang-Goo Kim (ckim14), Princeton University
