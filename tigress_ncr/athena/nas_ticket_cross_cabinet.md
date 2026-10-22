# Draft NAS support ticket (to support@nas.nasa.gov)

**Subject:** Athena Turin: MPI jobs whose nodes span two cabinets slow down by ~200x (79,721 Slingshot network timeouts in one job)

---

Hello,

Twice in the last two days, a 2-node MPI job on the Athena Turin nodes ran 150-400x slower
than the same job on other nodes. Both times the two nodes were in different cabinets. Every
job of ours whose nodes were all in one cabinet ran normally, including a 16-node job that
communicated heavily for 7.5 hours. One of the slow jobs reported 79,721 Slingshot network
timeouts at exit. We would like to know whether there is a known problem with the links
between cabinets, and which placement you recommend for multi-node jobs.

## Environment

- User ckim14, group s2800; queue normal; `-l select=2:ncpus=256:mpiprocs=192:model=tur_ath`,
  `-l place=scatter:excl`
- PrgEnv-gnu 8.6.0 (GCC 14.2), cray-mpich 8.1.33, cray-pals 1.7.1, OS libfabric 2.6.0
  (cxi), `FI_PROVIDER=cxi`, `FI_MR_CACHE_MONITOR=memhooks`, `OMP_NUM_THREADS=1`. The good and
  the slow jobs below used the same executable and settings.
- Application: TIGRESS (Athena++-based MHD with ray tracing and FFT self-gravity), 384 ranks,
  restarting from a checkpoint and running 7.5-hour segments that chain themselves.

## Jobs (times PDT)

| job | start | end | nodes | cabinets | behaviour |
|---|---|---|---|---|---|
| 252376 | 10-21 03:30 | 10-21 11:00 | x1001c0s2b0n0, x1001c0s2b0n1 | x1001 | normal, ~0.3 s/cycle |
| **252547** | 10-21 11:08 | 10-21 11:54 | **x1002c5s3b0n1, x1003c7s1b0n2** | **x1002 + x1003** | **startup 33 min instead of ~1; then ~50 s/cycle; we deleted it** |
| 252586 | 10-21 11:55 | 10-21 19:25 | x1001c0s3b0n3, x1001c0s4b0n0 | x1001 | normal |
| **252758** | 10-21 19:25 | 10-22 03:05 | **x1001c7s5b0n3, x1000c0s1b0n0** | **x1001 + x1000** | **50-115 s/cycle for the whole 7.6 h (230 cycles); 79,721 network timeouts at exit** |
| 252810 | 10-22 03:05 | 10-22 06:14 | x1001c0s3b0n1, x1001c4s2b0n1 | x1001 | normal; same restart file as 252758 ended with |
| 252381 | 10-21 03:43 | 10-21 11:14 | 16 nodes, all in chassis x1001c0 | x1001 | normal, 3072 ranks; 66 network timeouts at exit |

- The slow jobs were not hung: both advanced, just very slowly. In job 252547 all 384 ranks
  were busy (PBS reported 38,275% CPU). Job 252758 wrote a valid final restart file, and job 252810
  continued from it at normal speed on different nodes.
- In job 252547 everything was slow, including the startup (reading a 2.8 GB restart file and
  setting up the communication pattern), not only the time-stepping.
- Each run communicates with point-to-point messages (ray tracing, ghost-zone exchange) and
  all-to-all FFT transposes. On a good node pair one cycle takes 0.2-0.4 s.
- The exit message of job 252758 is MPICH's own summary
  (`MPICH Slingshot Network Summary: 79721 network timeouts`), with the default
  `MPICH_OFI_CXI_COUNTER_REPORT`.

## What we changed

We now submit with `-l place=scatter:excl:group=cabinet`. We noticed that the server has
`node_group_key = cabinet` but `node_group_enable = False`, so jobs are not kept within a cabinet
unless they ask for it.

## Questions

1. Is there a known problem with the links between cabinets (dragonfly global links), or with
   any of the four nodes above, at those times?
2. Is `node_group_enable = False` intentional? Do you recommend `group=cabinet` (or
   `group=chassis`) for multi-node MPI jobs on Athena?
3. Is there a counter or log we could collect on our side (for example
   `MPICH_OFI_CXI_COUNTER_REPORT=2`) that would help you diagnose this if it happens again?

This is based on two incidents, so the cabinet pattern may be a coincidence. One node of the
second slow pair (x1001c7s5b0n3) is in the same cabinet as our good jobs. We are happy to
provide the job scripts and logs.

Thank you,
Chang-Goo Kim (ckim14), Princeton University
