"""Shear-boundary report for the LGR4 short-box runs (tigress_classic_LGR4_short.slurm).

Compares the cells next to the shear-periodic x1 faces (row 0, row 1) with the cells next
to the x1 = centre plane (an ordinary MeshBlock face; same number of cells), from the
cumulative shb-*/ctl-* history columns, and checks the gas mass budget.

usage: python LGR4_short_report.py [run-dir ...]
"""
import re
import sys
import numpy as np

BASE = '/scratch/gpfs/EOST/changgoo/tigress_classic'


def read_hst(fname):
    names, rows = None, []
    for line in open(fname):
        if line.startswith('# ['):
            names = re.findall(r'\[\d+\]=(\S+)', line)
        elif not line.startswith('#') and line.strip():
            rows.append([float(x) for x in line.split()])
    d = np.array(rows)
    return {n: d[:, i] for i, n in enumerate(names)}


def report(run):
    h = read_hst(f'{BASE}/{run}/TIGRESS.hst')
    t = h['time']
    print(f'=== {run}: t = {t[0]:.2f} .. {t[-1]:.2f}, {len(t)} rows')
    pairs = [('density-flag cells', 'shb-dflag', 'ctl-dflag'),
             ('pressure-flag cells', 'shb-pflag', 'ctl-pflag'),
             ('floor mass, row 0', 'shb-dm0', 'ctl-dm0'),
             ('floor mass, row 1', 'shb-dm1', 'ctl-dm1'),
             ('int. energy, row 0', 'shb-dei0', 'ctl-dei0'),
             ('int. energy, row 1', 'shb-dei1', 'ctl-dei1'),
             ('ceiling events, row 0', 'shb-cn0', 'ctl-cn0'),
             ('ceiling mass, row 0', 'shb-cm0', 'ctl-cm0')]
    print('%-24s %14s %14s %10s' % ('cumulative', 'shear', 'control', 'ratio'))
    for lab, a, b in pairs:
        if a in h and b in h:
            va, vb = h[a][-1], h[b][-1]
            print('%-24s %14.5g %14.5g %10.3g' % (lab, va, vb,
                                                 va/vb if vb != 0 else np.inf))
    tot = h['shb-dei'][-1] if 'shb-dei' in h else np.nan
    print('%-24s %14.5g   (shear rows 0+1: %.1f%%)' % ('int. energy, all cells', tot,
          100*(h['shb-dei0'][-1] + h['shb-dei1'][-1])/tot if tot else np.nan))
    # rates per 10 time units
    edges = np.arange(np.floor(t[0]), t[-1] + 10, 10)
    print('rates per 10 time units:  t      dflag(sh/ctl)   dm0(sh/ctl)   cm0(sh/ctl)')
    for a0, a1 in zip(edges[:-1], edges[1:]):
        i0, i1 = np.searchsorted(t, a0), min(np.searchsorted(t, a1), len(t)) - 1
        if i1 <= i0:
            continue
        d = {k: h[k][i1] - h[k][i0] for k in ['shb-dflag', 'ctl-dflag', 'shb-dm0',
                                               'ctl-dm0', 'shb-cm0', 'ctl-cm0']}
        print('   %5.0f-%-5.0f %7.0f/%-7.0f %9.3g/%-9.3g %9.3g/%-9.3g' % (
            a0, a1, d['shb-dflag'], d['ctl-dflag'], d['shb-dm0'], d['ctl-dm0'],
            d['shb-cm0'], d['ctl-cm0']))
    # extremes
    for k in ['cs_max', 'temp_max', 'vel_max']:
        if k in h:
            print('max %-10s %.4g' % (k, h[k][1:].max()))
    # mass budget (row 0 skipped: interval sums start with the first output)
    s = slice(1, None)
    out = sum(h[k][s].sum() for k in ['dm_x1i', 'dm_x1o', 'dm_x2i', 'dm_x2o', 'dm_x3i',
                                       'dm_x3o'])
    dM = h['mass'][-1] - h['mass'][0]
    terms = -out + h['dm_floor'][s].sum() + h['mass_added'][s].sum() \
        - (h['msink'][-1] - h['msink'][0]) - h['m_rw_launch'][s].sum() \
        + h['m_sn_rw'][s].sum()
    print('mass budget: dM %.6e, terms %.6e, residual %.3e (%.2e of mass)' % (
        dM, terms, dM - terms, (dM - terms)/h['mass'][0]))
    print('  floors %.4g, ceiling %.4g, outflow %.4g' % (
        h['dm_floor'][s].sum(), h['mass_added'][s].sum(), out))


runs = sys.argv[1:] or ['LGR4-short-8pc-hydro_duale', 'LGR4-short-8pc-mhd_duale']
for r in runs:
    try:
        report(r)
    except (OSError, KeyError) as e:
        print(f'=== {r}: not readable yet ({e})')
