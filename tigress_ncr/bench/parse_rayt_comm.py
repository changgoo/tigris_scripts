#!/usr/bin/env python3
"""Ray-tracing communication-loop phases from TIGRESS_NCR.mesh_task_time.txt.

  parse_rayt_comm.py RUNDIR [RUNDIR ...]

Needs a build with <ray_tracing>/comm_timing = true (branch rayt-termination-iallreduce),
which writes per output window a RaytWork line (photons, segments, polls, idle_polls:
per-rank min/mean/max) and a RaytCommTime line (seconds per rank in each phase of
TraverseAll's loop: trace, send, probe+recv, send-test, termination).

The first window is skipped (it holds start-up and, after a restart, no ray trace).
Over the remaining windows, prints per ray trace: the rank-mean and rank-max seconds of each
phase, the mean RayTrace task time per rank, and polls/idle polls per rank.
"""
import os
import re
import sys

PHASES = ['t_trace', 't_send', 't_probe_recv', 't_send_test', 't_termination']
NUM = r'([-+0-9.eE]+)'


def parse(path):
    wins, cur = [], None
    for ln in open(path):
        if ln.startswith('# ncycle='):
            cur = {}
            wins.append(cur)
        elif cur is None:
            continue
        elif ln.strip().startswith('RayTrace,'):
            cur['raytrace'] = float(re.search(r'time=' + NUM, ln).group(1))
        elif ln.strip().startswith('RaytWork,'):
            cur['ntrace'] = int(re.search(r'ntrace=(\d+)', ln).group(1))
            for k in ('polls', 'idle_polls'):
                m = re.search(r'(?<![a-z_])' + k + r' min/mean/max=' + '/'.join([NUM] * 3), ln)
                if m:
                    cur[k] = float(m.group(2))
        elif ln.strip().startswith('RaytCommTime,'):
            for k in PHASES:
                m = re.search(k + r' min/mean/max=' + '/'.join([NUM] * 3), ln)
                cur[k] = (float(m.group(2)), float(m.group(3)))
    return wins[1:]


print(f"{'run':34s} {'ntr':>4s} {'RayT/rank':>9s} " +
      ' '.join(f"{p[2:]:>15s}" for p in PHASES) + f" {'polls':>8s} {'idle%':>6s}")
print(f"{'':34s} {'':>4s} {'s/trace':>9s} " + ' '.join(f"{'mean/max':>15s}" for _ in PHASES))
for d in sys.argv[1:]:
    f = os.path.join(d, 'TIGRESS_NCR.mesh_task_time.txt')
    try:
        wins = [w for w in parse(f) if w.get('ntrace')]
    except OSError:
        print(f"{os.path.basename(d):34s} no mesh_task_time.txt")
        continue
    ntr = sum(w['ntrace'] for w in wins)
    if not ntr or 't_trace' not in wins[0]:
        print(f"{os.path.basename(d):34s} no RaytCommTime (comm_timing off?)")
        continue
    # RayTrace task time is summed over ranks in the file
    nranks = None
    for ln in open(os.path.join(d, 'bench-summary.txt')):
        m = re.search(r'nranks=(\d+)', ln)
        nranks = int(m.group(1)) if m else nranks
    rt = sum(w.get('raytrace', 0) for w in wins) / (nranks or 1) / ntr
    cols = []
    for p in PHASES:
        mean = sum(w[p][0] for w in wins) / ntr
        mx = sum(w[p][1] for w in wins) / ntr
        cols.append(f"{mean:7.3f}/{mx:<7.3f}")
    polls = sum(w.get('polls', 0) for w in wins) / ntr
    idle = sum(w.get('idle_polls', 0) for w in wins) / ntr
    print(f"{os.path.basename(d):34s} {ntr:4d} {rt:9.3f} " + ' '.join(f"{c:>15s}" for c in cols)
          + f" {polls:8.2e} {100 * idle / polls if polls else 0:6.1f}")
