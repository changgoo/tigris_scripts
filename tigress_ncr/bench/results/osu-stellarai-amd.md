### OSU, stellarai-amd-gcc (logs/osu-4321)

| size | bibw_inter MB/s | bw_inter MB/s | bw_intra MB/s | mbw_mr_48 MB/s | mbw_mr_48 msg/s | mbw_mr_96 MB/s | mbw_mr_96 msg/s |
|---|---|---|---|---|---|---|---|
| 4 KB | 13,726 | 8,838 | 5,121 | 44,742 | 10,923,451 | 48,967 | 11,954,852 |
| 16 KB | 31,477 | 23,849 | 30,485 | 44,497 | 2,715,873 | 49,671 | 3,031,666 |
| 32 KB | 48,079 | 33,433 | 35,696 | 44,920 | 1,370,859 | 49,779 | 1,519,147 |
| 64 KB | 62,503 | 38,871 | 54,418 | 44,866 | 684,606 | 49,504 | 755,366 |
| 128 KB | 72,806 | 40,992 | 58,776 | 44,776 | 341,610 | 49,383 | 376,765 |
| 256 KB | 79,715 | 42,824 | 57,993 | 44,874 | 171,181 | 49,315 | 188,122 |
| 1 MB | 83,871 | 43,655 | 62,018 | 47,055 | 44,875 | 49,273 | 46,990 |

| size | alltoall_96 avg latency us |
|---|---|
| 4 KB | 1,250 |
| 16 KB | 3,475 |
| 32 KB | 7,686 |
| 64 KB | 12,618 |
| 128 KB | 24,863 |
| 256 KB | - |
| 1 MB | - |

Nodes sai-n04n10, sai-n04n11; gcc 14 + Open MPI 5.0.10 (hpcx-stack); THP always. One HCA per node: mlx5_0, Mellanox ConnectX-7 (MT2910, fw 28.50.1002), InfiniBand 4X NDR, 400 Gb/s.

### OSU, stellarai-amd-gcc-impi (logs/osu-4322)

| size | bibw_inter MB/s | bw_inter MB/s | bw_intra MB/s | mbw_mr_48 MB/s | mbw_mr_48 msg/s | mbw_mr_96 MB/s | mbw_mr_96 msg/s |
|---|---|---|---|---|---|---|---|
| 4 KB | 11,877 | 8,331 | 4,593 | 43,295 | 10,569,969 | 48,776 | 11,908,144 |
| 16 KB | 20,526 | 17,988 | 15,614 | 43,849 | 2,676,322 | 49,814 | 3,040,431 |
| 32 KB | 44,837 | 32,683 | 24,039 | 44,905 | 1,370,386 | 51,470 | 1,570,739 |
| 64 KB | 59,127 | 38,510 | 28,208 | 44,659 | 681,449 | 48,771 | 744,192 |
| 128 KB | 72,006 | 41,276 | 33,831 | 44,583 | 340,143 | 48,602 | 370,807 |
| 256 KB | 78,979 | 42,793 | 37,148 | 45,516 | 173,628 | 48,615 | 185,453 |
| 1 MB | 83,707 | 43,654 | 43,853 | 48,008 | 45,784 | 49,370 | 47,083 |

| size | alltoall_96 avg latency us |
|---|---|
| 4 KB | 1,473 |
| 16 KB | 3,628 |
| 32 KB | 7,615 |
| 64 KB | 14,003 |
| 128 KB | 26,584 |
| 256 KB | - |
| 1 MB | - |

Nodes sai-n04n1, sai-n04n12; gcc 14 + Intel MPI 2021.18 (libfabric 2.4.0-impi); THP always. Same HCA (one ConnectX-7 NDR 400 Gb/s per node).

Against Athena (osu-athena.md): no message-rate ceiling here. mbw_mr_96 is bandwidth-bound at ~49 GB/s (NDR line rate) from 4 KB up, i.e. 3.0M msg/s at 16 KB and 0.75M at 64 KB, against Athena's ~460K msg/s per node at 4-64 KB. alltoall_96 takes 1.3-1.5 ms at 4 KB and 3.5-3.6 ms at 16 KB, against Athena's 41.6 / 41.8 ms. Large-message rates match Athena (49 GB/s many-pair). Open MPI and Intel MPI agree within ~10% except bw_intra, where Open MPI is faster.
