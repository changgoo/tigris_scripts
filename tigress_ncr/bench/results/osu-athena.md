### OSU, athena-gcc, default MR cache monitor userfaultfd (logs/osu-252363)

| size | bibw_inter MB/s | bw_inter MB/s | bw_intra MB/s | mbw_mr_192 MB/s | mbw_mr_192 msg/s | mbw_mr_96 MB/s | mbw_mr_96 msg/s | mbw_mr_96_1nic MB/s | mbw_mr_96_1nic msg/s |
|---|---|---|---|---|---|---|---|---|---|
| 4 KB | 683 | 668 | 13,755 | 1,930 | 471,154 | 1,898 | 463,260 | 947 | 231,231 |
| 16 KB | 2,691 | 2,571 | 51,899 | 7,703 | 470,146 | 7,491 | 457,237 | 3,758 | 229,348 |
| 32 KB | 4,991 | 4,912 | 46,829 | 15,107 | 461,027 | 14,806 | 451,834 | 7,090 | 216,362 |
| 64 KB | 9,347 | 9,054 | 60,787 | 29,316 | 447,320 | 28,913 | 441,177 | 13,407 | 204,575 |
| 128 KB | 16,218 | 15,228 | 71,844 | 48,529 | 370,247 | 48,344 | 368,833 | 24,305 | 185,435 |
| 256 KB | 25,407 | 23,195 | 100,423 | 48,767 | 186,031 | 48,835 | 186,289 | 24,504 | 93,475 |
| 1 MB | 37,648 | 23,946 | 52,320 | 48,878 | 46,613 | 48,996 | 46,726 | 24,463 | 23,329 |

| size | alltoall_96 avg latency us |
|---|---|
| 4 KB | 41,586 |
| 16 KB | 41,794 |
| 32 KB | 83,939 |
| 64 KB | 168,407 |
| 128 KB | 337,246 |
| 256 KB | - |
| 1 MB | - |

- mbw_mr_192: MPICH Slingshot Network Summary: 0 network timeouts
- mbw_mr_96: MPICH Slingshot Network Summary: 0 network timeouts

Nodes x1001c0s2b0n0, x1001c0s2b0n1 (same chassis); gcc 14.2 + cray-mpich 8.1.33, libfabric 2.6.0 (cxi0, cxi1); THP always. mbw_mr_192 CXI counters (MPICH_OFI_CXI_COUNTER_REPORT=2): 0 network timeouts; hni_rx_paused_0/1 ~0.5M/1.3M per s, atu_cache_evictions ~53K per s, parbs_tarb_pi_posted_blocked_cnt ~3e8 per s.

### OSU, athena-gcc, FI_MR_CACHE_MONITOR=memhooks (logs/osu-252368)

| size | bibw_inter MB/s | bw_inter MB/s | bw_intra MB/s | mbw_mr_192 MB/s | mbw_mr_192 msg/s | mbw_mr_96 MB/s | mbw_mr_96 msg/s | mbw_mr_96_1nic MB/s | mbw_mr_96_1nic msg/s |
|---|---|---|---|---|---|---|---|---|---|
| 4 KB | 11,270 | 10,301 | 13,573 | 49,402 | 12,061,032 | 49,431 | 12,068,128 | 24,259 | 5,922,591 |
| 16 KB | 30,728 | 21,395 | 54,344 | 48,328 | 2,949,733 | 49,572 | 3,025,665 | 24,209 | 1,477,583 |
| 32 KB | 35,818 | 21,940 | 47,559 | 48,575 | 1,482,389 | 47,128 | 1,438,232 | 24,402 | 744,677 |
| 64 KB | 40,898 | 23,066 | 59,562 | 48,583 | 741,317 | 48,311 | 737,173 | 24,425 | 372,698 |
| 128 KB | 43,595 | 23,507 | 69,875 | 48,814 | 372,424 | 48,679 | 371,394 | 24,523 | 187,099 |
| 256 KB | 45,094 | 23,998 | 93,502 | 48,902 | 186,547 | 48,670 | 185,661 | 24,515 | 93,517 |
| 1 MB | 46,285 | 24,217 | 54,241 | 48,609 | 46,357 | 48,364 | 46,124 | 24,393 | 23,263 |

| size | alltoall_96 avg latency us |
|---|---|
| 4 KB | 850 |
| 16 KB | 3,466 |
| 32 KB | 6,891 |
| 64 KB | 13,799 |
| 128 KB | 27,594 |
| 256 KB | - |
| 1 MB | - |

- mbw_mr_192: MPICH Slingshot Network Summary: 0 network timeouts
- mbw_mr_96: MPICH Slingshot Network Summary: 0 network timeouts

Same toolchain and settings as job 252363, plus FI_MR_CACHE_MONITOR=memhooks (the env.sh default since 2026-10-21).
