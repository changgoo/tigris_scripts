"""Side-by-side shear-boundary comparison of the LGR4 short-box runs up to a common time.

Cumulative shb-*/ctl-* counters and per-interval budget columns are evaluated at
t <= T (default 20), split into windows of 10, together with the supernova counts.

usage: python LGR4_short_compare.py [T] [run ...]
"""
import re
import sys
import numpy as np

BASE = '/scratch/gpfs/EOST/changgoo/tigress_classic'
RUNS = ['hydro_duale', 'hydro-t20', 'hydro-lim-t20', 'mhd_duale', 'mhd-t20', 'mhd-lim-t20']


def read_hst(fname):
    names, rows = None, []
    for line in open(fname):
        if line.startswith('# ['):
            names = re.findall(r'\[\d+\]=(\S+)', line)
        elif not line.startswith('#') and line.strip():
            rows.append([float(x) for x in line.split()])
    d = np.array(rows)
    return {n: d[:, i] for i, n in enumerate(names)}


def sn_count(run, t0, t1):
    n = 0
    with open(f'{BASE}/LGR4-short-8pc-{run}/TIGRESS.sn') as f:
        next(f)
        for line in f:
            t = float(line.split(',')[3])
            n += (t0 < t <= t1)
    return n


T = float(sys.argv[1]) if len(sys.argv) > 1 else 20.0
runs = sys.argv[2:] or RUNS
windows = [(0, 10), (10, T)]
rows = {}
for r in runs:
    h = read_hst(f'{BASE}/LGR4-short-8pc-{r}/TIGRESS.hst')
    t = h['time']
    res = {}
    for a, b in windows:
        i0 = 0 if a == 0 else np.searchsorted(t, a) - 1
        i1 = np.searchsorted(t, b, side='right') - 1
        lab = f'{a:g}-{b:g}'
        cum = lambda k: h[k][i1] - (h[k][i0] if a > 0 else 0.0)
        per = lambda k: h[k][i0 + 1:i1 + 1].sum() if a > 0 else h[k][1:i1 + 1].sum()
        res[lab] = {
            'SNe': sn_count(r, a, min(b, t[i1])),
            'shb dflag': cum('shb-dflag'), 'ctl dflag': cum('ctl-dflag'),
            'shb pflag': cum('shb-pflag'), 'ctl pflag': cum('ctl-pflag'),
            'shb dm0': cum('shb-dm0'), 'shb dm1': cum('shb-dm1'), 'ctl dm0': cum('ctl-dm0'),
            'shb dei0': cum('shb-dei0'), 'ctl dei0': cum('ctl-dei0'),
            'all dei': cum('shb-dei'),
            'shb ceil n': cum('shb-cn0'), 'ctl ceil n': cum('ctl-cn0'),
            'shb ceil m': cum('shb-cm0'), 'ctl ceil m': cum('ctl-cm0'),
            'dm_floor': per('dm_floor'), 'mass_added': per('mass_added'),
            'outflow': per('dm_x3i') + per('dm_x3o'),
            'cs_max': h['cs_max'][i0 + 1:i1 + 1].max(),
            'T_max': h['temp_max'][i0 + 1:i1 + 1].max(),
            't_end': t[i1],
        }
    rows[r] = res
for lab in [f'{a:g}-{b:g}' for a, b in windows]:
    print(f'\n### t = {lab}')
    keys = list(next(iter(rows.values()))[lab].keys())
    print('%-12s' % '' + ''.join('%14s' % r for r in runs))
    for k in keys:
        print('%-12s' % k + ''.join('%14.4g' % rows[r][lab][k] for r in runs))
