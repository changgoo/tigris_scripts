# Handoff: FFT self-gravity phase profile on stellarai-amd

## Why
On NASA Athena (2x EPYC 9745, Slingshot, cray-mpich) the self-gravity solve (`grav` in
`loop_time.txt`) is about 3.5x slower than on stellarai-amd at the same layout (384 ranks,
4 nodes x 96): 0.069-0.073 s/cycle against 0.020-0.023, while hydro (`tint`) is within 10%.
The compiler, the FFT library and several MPICH settings are already ruled out
(`tigress_ncr/athena/README.md`, "Open: slow self-gravity").

Production builds use `--grav=fft`, i.e. `FFTGravityDriver` (`src/gravity/fft_gravity.cpp`,
fftMPI `FFT3d` with the disk BC, plus the `ShearingRemapper` for the shearing box). It has a
built-in profiler: `gravity/profile_gravity=true` writes `<problem_id>.fft_gravity_time.txt`
with one line per solve and per-phase times (Load, ShearSource, Forward, Kernel, Backward,
Retrieve, TaskList). The same profile is running on Athena now. Your job is the
stellarai-amd reference, so the two can be compared phase by phase.

## Steps

1. **Get the tooling on a branch.** In `~/tigris_scripts`, check out the branch
   `grav-profile`. This prompt is on it, as
   `tigress_ncr/bench/reports/grav-profile-handoff-stellarai-amd.md`. If you received this
   prompt without the branch, create `grav-profile` from `main` and apply the patch at the
   end with `git am`; the patch reproduces the branch's first commit. The branch adds
   `tigress_ncr/bench/parse_grav_profile.py` and tags profiled runs with `gprof` in the `opts`
   field of the results line. The tag matters because the profiler's per-solve
   `MPI_Allreduce` calls fall inside the `grav` timer. Do not touch `env.sh` or the flags.

2. **Rebuild from Athena's commit.** The code has moved on since the earlier stellarai-amd
   benchmark builds, so build from exactly the commit Athena runs: `production-diagnostics`
   at `23071491f`. It is the tip of `origin/production-diagnostics`.
   ```bash
   git -C ~/tigris fetch origin
   # if ~/tigris/.worktrees/production-diagnostics does not exist:
   git -C ~/tigris worktree add --detach ~/tigris/.worktrees/production-diagnostics 23071491f
   ```
   - If that worktree already exists, check that it is clean (`git status`) before running
     `git checkout --detach 23071491f` in it.
   - If it has local changes, don't touch them. Create a separate worktree (for example
     `.worktrees/grav-profile-src`) and use `--worktree=grav-profile-src` below.

   Build with a suffix so the production exes stay intact. Run the builds one at a time,
   because they share `obj/`:
   ```bash
   cd ~/tigris_scripts/tigress_ncr
   for p in mhd crmhd; do
     bash build_tigress.sh --machine=stellarai-amd --cc=gcc --physics=$p \
          --worktree=production-diagnostics --exe_suffix=gprof
   done
   ```
   Check that each `stellarai-amd/tigris_ncr_<physics>-fft-gcc-gprof.buildinfo` shows commit
   `23071491f`, no dirty files, and `nan_checks: kept`.

3. **Submit** (384 ranks = 4 full nodes; one job each). `VARIANT=gprof` selects the new
   exes. `SRCDIR` points the job at that tree's data tables (`sbatch` exports the
   environment):
   ```bash
   cd ~/tigris_scripts/tigress_ncr
   export SRCDIR=$HOME/tigris/.worktrees/production-diagnostics
   VARIANT=gprof bench/submit.sh stellarai-amd mhd   gcc 200 gravity/profile_gravity=true
   VARIANT=gprof bench/submit.sh stellarai-amd crmhd gcc 200 gravity/profile_gravity=true
   ```
   Optional, if the queue allows: build and run the same pair with `--cc=gcc-impi` (Intel
   MPI). That shows whether the gravity time depends on the MPI library on this machine.

4. **Reduce.** For each run (run dir
   `/scratch/gpfs/EOST/$USER/tigress_ncr/bench/<physics>-gcc-gprof-<jobid>/`):
   ```bash
   python3 bench/parse_grav_profile.py <rundir>/TIGRESS_NCR.fft_gravity_time.txt
   grep gprof bench/results/stellarai-amd.txt
   ```
   Sanity checks:
   - rc=0.
   - 2 solves per cycle (rk2).
   - `grav` in the results line within ~10-15% of the earlier non-profiled stellarai-amd
     runs (0.019-0.025 s/cycle). If it is much higher, the profiler overhead is distorting
     the numbers; say so.

5. **Commit** the new results lines on `grav-profile` (message prefix `stellarai-amd:`).
   Don't merge into `main`. Push the branch if GitHub is reachable.

## Report back
- The `parse_grav_profile.py` output for each run (rank-mean/slowest s/cycle per phase).
- The `gprof` results lines.
- The job IDs, the exe's buildinfo commit, and the `module list`.
- Anything unexpected (rc != 0, NaN, a phase that is far off).

Runs are not bitwise reproducible (ray tracing depends on MPI message order). Differences
under ~2% are ties.

## Patch (apply with `git am`)
```
From b3a33ef84db01c17113d502825c245e263791d7b Mon Sep 17 00:00:00 2001
From: Chang-Goo Kim <cgkim@astro.princeton.edu>
Date: Wed, 21 Oct 2026 01:31:37 -0700
Subject: [PATCH] tigress_ncr: profile the FFT gravity solve phase by phase

parse_grav_profile.py reduces <problem_id>.fft_gravity_time.txt (written with
gravity/profile_gravity=true) to rank-mean/slowest seconds per cycle for each phase.
The bench scripts tag such runs gprof in opts: the profiler's per-solve
allreduces sit inside the grav timer.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
---
 tigress_ncr/bench/parse_grav_profile.py       | 53 +++++++++++++++++++
 tigress_ncr/bench/tigress_ncr_8pc_bench.pbs   |  2 +-
 tigress_ncr/bench/tigress_ncr_8pc_bench.slurm |  2 +-
 3 files changed, 55 insertions(+), 2 deletions(-)
 create mode 100755 tigress_ncr/bench/parse_grav_profile.py

diff --git a/tigress_ncr/bench/parse_grav_profile.py b/tigress_ncr/bench/parse_grav_profile.py
new file mode 100755
index 0000000..67f565b
--- /dev/null
+++ b/tigress_ncr/bench/parse_grav_profile.py
@@ -0,0 +1,53 @@
+#!/usr/bin/env python3
+"""Reduce <problem_id>.fft_gravity_time.txt to per-phase seconds per cycle.
+
+The file is written when <gravity>/profile_gravity=true (FFTGravityDriver::Solve, i.e.
+--grav=fft). It has one line per solve, with, per phase, <Phase>Sum (summed over ranks)
+and <Phase>Max (slowest rank). Phases:
+  Load        density -> remap buffer (transpose)
+  ShearSource roll to shearing coordinates (ShearingRemapper) + load into the FFT brick
+  Forward     fftMPI remaps block->x->y->z pencils, xy FFTs, even/odd z FFTs
+  Kernel      disk-BC kernel
+  Backward    inverse of Forward
+  Retrieve    FFT brick -> buffer, unroll, transpose into phi
+  TaskList    gravity boundary task list (phi ghost zones)
+The first SKIP cycles (default 10, the partial window after a restart) are dropped.
+
+Usage: parse_grav_profile.py FILE [FILE ...] [--skip=N]
+Prints one row per file: rank-mean / slowest-rank seconds per cycle for each phase.
+"""
+import sys
+
+PHASES = ['Total', 'Load', 'ShearSource', 'Forward', 'Kernel', 'Backward', 'Retrieve',
+          'TaskList']
+
+skip = 10
+files = []
+for a in sys.argv[1:]:
+    if a.startswith('--skip='):
+        skip = int(a.split('=', 1)[1])
+    else:
+        files.append(a)
+if not files:
+    sys.exit(__doc__)
+
+print('file solves/cycle ' + ' '.join(PHASES) + '   (s/cycle, rank-mean/slowest)')
+for fname in files:
+    rows = []
+    with open(fname) as f:
+        for line in f:
+            d = dict(item.split('=', 1) for item in line.strip().split(','))
+            rows.append(d)
+    c0 = int(rows[0]['ncycle']) + skip
+    rows = [r for r in rows if int(r['ncycle']) >= c0]
+    if not rows:
+        print(f'{fname}: no solves after skipping {skip} cycles')
+        continue
+    ncyc = len({r['ncycle'] for r in rows})
+    nr = int(rows[0]['Nblocks'])   # one meshblock per rank
+    cols = []
+    for p in PHASES:
+        mean = sum(float(r[p + 'Sum']) for r in rows) / nr / ncyc
+        slow = sum(float(r[p + 'Max']) for r in rows) / ncyc
+        cols.append(f'{mean:.4f}/{slow:.4f}')
+    print(f'{fname} {len(rows) / ncyc:.1f} ' + ' '.join(cols))
diff --git a/tigress_ncr/bench/tigress_ncr_8pc_bench.pbs b/tigress_ncr/bench/tigress_ncr_8pc_bench.pbs
index 1bf4206..348a44a 100644
--- a/tigress_ncr/bench/tigress_ncr_8pc_bench.pbs
+++ b/tigress_ncr/bench/tigress_ncr_8pc_bench.pbs
@@ -123,7 +123,7 @@ run_task() {   # run_task <index> <lane> <hosts>
     python3 "$BENCHDIR/parse_loop_time.py" TIGRESS_NCR.loop_time.txt \
         machine="$MACHINE" workload="$WORKLOAD" physics="$PHYSICS" tc="$TC" variant="${VARIANT:-default}" \
         job="$JOBID.$k" nranks="$NR" nodes="$NPR" rc="$EXITCODE" job_wall="$((T1 - T0))" \
-        opts="${LAUNCH_OPTS:-default} ${BENCH_MPIENV:-}${TASKENV}${NODETAG}$([[ "$params" == *solve_grav_hyperbolic_dt=true* ]] && echo " grav=hyp")" > bench-summary.txt
+        opts="${LAUNCH_OPTS:-default} ${BENCH_MPIENV:-}${TASKENV}${NODETAG}$([[ "$params" == *solve_grav_hyperbolic_dt=true* ]] && echo " grav=hyp")$([[ "$params" == *profile_gravity=true* ]] && echo " gprof")" > bench-summary.txt
     cat bench-summary.txt >> "$RESULTS"
     echo "$(date +%T) lane $lane task $k: $WORKLOAD $PHYSICS $TC${VARIANT:+-$VARIANT} rc=$EXITCODE wall=$((T1 - T0))s $(grep -o 's_cycle=[^ ]*' bench-summary.txt)"
     # keep only what the analysis needs: logs, timing, history
diff --git a/tigress_ncr/bench/tigress_ncr_8pc_bench.slurm b/tigress_ncr/bench/tigress_ncr_8pc_bench.slurm
index 26d6e32..ef68657 100644
--- a/tigress_ncr/bench/tigress_ncr_8pc_bench.slurm
+++ b/tigress_ncr/bench/tigress_ncr_8pc_bench.slurm
@@ -93,7 +93,7 @@ echo "EXITCODE = $EXITCODE"
 python3 "$BENCHDIR/parse_loop_time.py" TIGRESS_NCR.loop_time.txt \
     machine="$MACHINE" physics="$PHYSICS" tc="$TC" variant="${VARIANT:-default}" job="$SLURM_JOB_ID" \
     nranks="$SLURM_NTASKS" nodes="$SLURM_JOB_NUM_NODES" rc="$EXITCODE" \
-    job_wall="$((T1 - T0))" opts="${SRUN_OPTS:-default} ${BENCH_MPIENV:-}${INPUT_OVERRIDE:+ input=$(basename "$INPUT_OVERRIDE")}" | tee bench-summary.txt
+    job_wall="$((T1 - T0))" opts="${SRUN_OPTS:-default} ${BENCH_MPIENV:-}${INPUT_OVERRIDE:+ input=$(basename "$INPUT_OVERRIDE")}$([[ "$params" == *profile_gravity=true* ]] && echo " gprof")" | tee bench-summary.txt
 mkdir -p "$BENCHDIR/results"
 cat bench-summary.txt >> "$BENCHDIR/results/$MACHINE.txt"
 
-- 
2.52.0

```
