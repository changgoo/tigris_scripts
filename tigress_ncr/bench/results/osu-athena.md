### OSU, athena-gcc (logs/osu-252363)

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
