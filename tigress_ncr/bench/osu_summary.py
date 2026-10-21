#!/usr/bin/env python3
"""Summarize an osu_net.pbs / osu_net.slurm output directory as markdown tables.

Usage: osu_summary.py bench/logs/osu-<job> [MACHINE]

Tables: bandwidth (MB/s) of one pair (osu_bw, osu_bibw, inter- and intra-node) and of
many pairs (osu_mbw_mr, with messages/s), and osu_alltoall latency, at the message
sizes of the FFT-gravity remaps (16-128 KB) and around them.
"""
import os
import sys

SIZES = [4096, 16384, 32768, 65536, 131072, 262144, 1048576]


def read(path):
    """size -> list of the numeric columns after it"""
    rows = {}
    if not os.path.exists(path):
        return rows
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2 and parts[0].isdigit():
                try:
                    rows[int(parts[0])] = [float(x) for x in parts[1:]]
                except ValueError:
                    pass
    return rows


def label(n):
    return f'{n // 1048576} MB' if n >= 1048576 else f'{n // 1024} KB'


d = sys.argv[1]
machine = sys.argv[2] if len(sys.argv) > 2 else os.path.basename(os.path.normpath(d))
tests = sorted(f[:-4] for f in os.listdir(d) if f.endswith('.txt') and f != 'env.txt')
bw = [t for t in tests if t.startswith(('bw_', 'bibw_'))]
mbw = [t for t in tests if t.startswith('mbw_mr')]
a2a = [t for t in tests if t.startswith('alltoall')]

print(f'### OSU, {machine} ({d})\n')
cols = [(t, 0, 'MB/s') for t in bw] + [(t, i, u) for t in mbw
                                      for i, u in ((0, 'MB/s'), (1, 'msg/s'))]
data = {t: read(os.path.join(d, t + '.txt')) for t in bw + mbw + a2a}
print('| size | ' + ' | '.join(f'{t} {u}' for t, _, u in cols) + ' |')
print('|---' * (len(cols) + 1) + '|')
for s in SIZES:
    vals = []
    for t, i, _ in cols:
        v = data[t].get(s)
        vals.append(f'{v[i]:,.0f}' if v and len(v) > i else '-')
    print(f'| {label(s)} | ' + ' | '.join(vals) + ' |')
if a2a:
    print('\n| size | ' + ' | '.join(f'{t} avg latency us' for t in a2a) + ' |')
    print('|---' * (len(a2a) + 1) + '|')
    for s in SIZES:
        vals = [f'{data[t][s][0]:,.0f}' if s in data[t] else '-' for t in a2a]
        print(f'| {label(s)} | ' + ' | '.join(vals) + ' |')
notes = []
for t in tests:
    with open(os.path.join(d, t + '.txt')) as f:
        for line in f:
            if 'Network Summary' in line or line.startswith('rc=') and line.strip() != 'rc=0':
                notes.append(f'{t}: {line.strip()}')
if notes:
    print('\n' + '\n'.join(f'- {n}' for n in notes))
