#!/usr/bin/env python3
"""Reduce <problem_id>.fft_gravity_time.txt to per-phase seconds per cycle.

The file is written when <gravity>/profile_gravity=true (FFTGravityDriver::Solve, i.e.
--grav=fft). It has one line per solve, with, per phase, <Phase>Sum (summed over ranks)
and <Phase>Max (slowest rank). Phases:
  Load        density -> remap buffer (transpose)
  ShearSource roll to shearing coordinates (ShearingRemapper) + load into the FFT brick
  Forward     fftMPI remaps block->x->y->z pencils, xy FFTs, even/odd z FFTs
  Kernel      disk-BC kernel
  Backward    inverse of Forward
  Retrieve    FFT brick -> buffer, unroll, transpose into phi
  TaskList    gravity boundary task list (phi ghost zones)
The first SKIP cycles (default 10, the partial window after a restart) are dropped.

Usage: parse_grav_profile.py FILE [FILE ...] [--skip=N]
Prints one row per file: rank-mean / slowest-rank seconds per cycle for each phase.
"""
import sys

PHASES = ['Total', 'Load', 'ShearSource', 'Forward', 'Kernel', 'Backward', 'Retrieve',
          'TaskList']

skip = 10
files = []
for a in sys.argv[1:]:
    if a.startswith('--skip='):
        skip = int(a.split('=', 1)[1])
    else:
        files.append(a)
if not files:
    sys.exit(__doc__)

print('file solves/cycle ' + ' '.join(PHASES) + '   (s/cycle, rank-mean/slowest)')
for fname in files:
    rows = []
    with open(fname) as f:
        for line in f:
            d = dict(item.split('=', 1) for item in line.strip().split(','))
            rows.append(d)
    c0 = int(rows[0]['ncycle']) + skip
    rows = [r for r in rows if int(r['ncycle']) >= c0]
    if not rows:
        print(f'{fname}: no solves after skipping {skip} cycles')
        continue
    ncyc = len({r['ncycle'] for r in rows})
    nr = int(rows[0]['Nblocks'])   # one meshblock per rank
    cols = []
    for p in PHASES:
        mean = sum(float(r[p + 'Sum']) for r in rows) / nr / ncyc
        slow = sum(float(r[p + 'Max']) for r in rows) / ncyc
        cols.append(f'{mean:.4f}/{slow:.4f}')
    print(f'{fname} {len(rows) / ncyc:.1f} ' + ' '.join(cols))
