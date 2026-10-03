#!/usr/bin/env python3
"""Reduce <PID>.loop_time.txt to one benchmark result line.

loop_time.txt has one line per ncycle_out_timing (=10) cycles with, per timer,
  <Timer>=<sum over ranks of seconds per cycle>, <Timer>_imb=<max*nranks/sum>.
The first window after a restart is partial and is skipped.

Usage: parse_loop_time.py LOOP_TIME_FILE key=value ... [opts=...]
Prints: date=... key=value ... windows=N s_cycle=... zc_core_s=... <timer>=mean/max ...
        opts=...   (opts is always last and may contain spaces)
Timers are reported as rank-mean / slowest-rank seconds per cycle.
"""
import datetime
import sys

TIMERS = {'TimeIntegratorTaskList': 'tint', 'SelfGravity': 'grav', 'RayT': 'rayt',
          'Photchem': 'pchem', 'OpSplit': 'ops', 'NewDt': 'newdt'}

fname, *kv = sys.argv[1:]
meta = dict(a.split('=', 1) for a in kv)
opts = meta.pop('opts', 'default')

rows = []
try:
    with open(fname) as f:
        for line in f:
            rows.append({k: float(v) for k, v in
                         (item.split('=', 1) for item in line.strip().split(','))})
except FileNotFoundError:
    pass
rows = rows[1:]

out = [f"date={datetime.date.today().isoformat()}"] + [f"{k}={v}" for k, v in meta.items()]
if not rows:
    out += ["windows=0", "s_cycle=nan"]
else:
    nr = rows[0]['Nblocks']   # one meshblock per rank
    nw = len(rows)
    mean = lambda k: sum(r[k] for r in rows) / nr / nw
    slow = lambda k: sum(r[k] * r[k + '_imb'] for r in rows) / nr / nw
    ncell = 32**3 * nr        # 32^3 meshblocks
    s_cyc = mean('All')
    out += [f"windows={nw}", f"s_cycle={s_cyc:.4f}", f"zc_core_s={ncell / s_cyc / nr:.4g}"]
    out += [f"{v}={mean(k):.4f}/{slow(k):.4f}" for k, v in TIMERS.items() if k in rows[0]]
out.append(f"opts={opts}")
print(' '.join(out))
