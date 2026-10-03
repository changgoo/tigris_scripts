#!/usr/bin/env python3
"""Summarize benchmark result files (bench/results/<machine>.txt) as markdown tables.

  summarize.py results/stellarai-amd.txt [results/other.txt ...] [--all]

Groups runs by machine, physics, toolchain and opts (launcher options + MPI env);
reports the number of good runs, median and min seconds per cycle, the cost in
node-hours per 10^4 cycles (median s/cycle x nodes, for comparing machines), the median
rank-mean time of each timer, and the speed relative to the best group.
Runs with rc!=0 or no timing windows are dropped; --all also lists them.
"""
import statistics
import sys
from collections import defaultdict

TIMERS = ['tint', 'grav', 'rayt', 'pchem', 'ops']


def parse(line):
    line = line.strip()
    if not line:
        return None
    head, _, opts = line.partition(' opts=')
    d = dict(tok.split('=', 1) for tok in head.split() if '=' in tok)
    d['opts'] = ' '.join(opts.split()) or 'default'
    return d


args = [a for a in sys.argv[1:] if not a.startswith('--')]
show_all = '--all' in sys.argv
runs, bad = [], []
for fn in args:
    with open(fn) as f:
        for line in f:
            d = parse(line)
            if d is None:
                continue
            ok = d.get('rc') == '0' and d.get('s_cycle', 'nan') != 'nan' and int(d.get('windows', 0)) > 0
            (runs if ok else bad).append(d)

groups = defaultdict(list)
for d in runs:
    groups[(d.get('machine', '?'), d['physics'], d['tc'], d['opts'])].append(d)

for machine in sorted({k[0] for k in groups}):
    for physics in ('mhd', 'crmhd'):
        keys = [k for k in groups if k[0] == machine and k[1] == physics]
        if not keys:
            continue
        med = {k: statistics.median(float(d['s_cycle']) for d in groups[k]) for k in keys}
        best = min(med.values())
        print(f"\n### {machine} / {physics}  (seconds per cycle; timers are rank means)\n")
        print("| toolchain | opts | n | median | min | node-h/1e4 | rel | " + " | ".join(TIMERS) + " |")
        print("|---|---|---|---|---|---|---|" + "---|" * len(TIMERS))
        for k in sorted(keys, key=med.get):
            g = groups[k]
            tmed = []
            for t in TIMERS:
                vals = [float(d[t].split('/')[0]) for d in g if t in d]
                tmed.append(f"{statistics.median(vals):.3f}" if vals else "-")
            mn = min(float(d['s_cycle']) for d in g)
            nodes = int(g[0].get('nodes', 0))
            nh = f"{med[k] * nodes * 1e4 / 3600:.2f}" if nodes else "-"
            print(f"| {k[2]} | {k[3]} | {len(g)} | {med[k]:.4f} | {mn:.4f} | {nh} | "
                  f"{med[k] / best:.2f} | " + " | ".join(tmed) + " |")

if bad:
    print(f"\n{len(bad)} failed/empty run(s) excluded" + (":" if show_all else " (--all lists them)"))
    if show_all:
        for d in bad:
            print(f"  job={d.get('job')} {d.get('physics')} {d.get('tc')} rc={d.get('rc')}")
