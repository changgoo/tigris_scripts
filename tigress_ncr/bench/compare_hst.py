#!/usr/bin/env python3
"""Correctness check: compare the final TIGRESS_NCR.hst rows of benchmark runs.

  compare_hst.py RUNDIR [RUNDIR ...] --ref=<substring>

All runs of one physics restart the same checkpoint for the same number of cycles. For each
run, this reports against the reference (the first directory whose name contains --ref):
  n>1e-3, n>1e-2 : number of history columns whose relative difference exceeds 1e-3 / 1e-2
  dt             : relative difference of the time step (column 2)
NaN/inf columns are skipped and counted; on stellarai-amd, the CRMHD history has 3 NaN
columns for every build, from the code and not from the compiler.

The runs are not bitwise reproducible, even for one executable: ray tracing and the
CR/feedback paths depend on message order. The other directories matching --ref (repeats of the
reference build) therefore define an envelope, and a run is flagged SUSPECT when its n>1e-2
exceeds the envelope by more than 5, or its dt differs by more than 1e-2.
Observed on stellarai-amd (200 cycles):
  mhd   : 0 columns > 1e-3 for every build and repeat (envelope 0)
  crmhd : 5-15 columns > 1e-3 and <= 6 > 1e-2 for every build, repeats included
  AOCC -zopt (mhd): 20 columns > 1e-3 and dt off by 36%, so it is flagged as a miscompile.
"""
import math
import os
import sys

args = [a for a in sys.argv[1:] if not a.startswith('--')]
opts = dict(a[2:].split('=', 1) for a in sys.argv[1:] if a.startswith('--') and '=' in a)
if 'ref' not in opts:
    sys.exit(__doc__)


def last_row(d):
    with open(os.path.join(d, 'TIGRESS_NCR.hst')) as f:
        rows = [ln for ln in f if ln.strip() and not ln.startswith('#')]
    return [float(x) for x in rows[-1].split()]


def compare(r, r0):
    rel, nonfinite = [], 0
    for a, b in zip(r, r0):
        if not (math.isfinite(a) and math.isfinite(b)):
            nonfinite += 1
            continue
        m = max(abs(a), abs(b))
        rel.append(abs(a - b) / m if m > 0 else 0.0)
    dt = abs(r[1] - r0[1]) / abs(r0[1]) if r0[1] else 0.0
    return sum(x > 1e-3 for x in rel), sum(x > 1e-2 for x in rel), dt, nonfinite


name = lambda d: os.path.basename(d.rstrip('/'))
rows = {}
for d in args:
    try:
        rows[d] = last_row(d)
    except (OSError, IndexError, ValueError) as e:
        print(f"{name(d):40s} unreadable ({e.__class__.__name__})")
refs = [d for d in rows if opts['ref'] in name(d)]
if not refs:
    sys.exit(f"no run directory matches --ref={opts['ref']}")
ref, r0 = refs[0], rows[refs[0]]

same = [d for d in rows if len(rows[d]) == len(r0) and rows[d][0] == r0[0]]
env = max([compare(rows[d], r0)[1] for d in refs[1:] if d in same], default=0)
print(f"reference {name(ref)}  (t={r0[0]:.6g}, {len(refs)} run(s) of the reference build; "
      f"envelope n>1e-2 = {env})")
print(f"{'run':40s} {'n>1e-3':>7s} {'n>1e-2':>7s} {'dt':>9s} {'nan':>4s}")
bad = 0
for d in rows:
    if d not in same:
        print(f"{name(d):40s} different end time/columns: not comparable")
        continue
    n3, n2, dt, nf = compare(rows[d], r0)
    flag = n2 > env + 5 or dt > 1e-2
    bad += flag
    print(f"{name(d):40s} {n3:7d} {n2:7d} {dt:9.1e} {nf:4d}{'  SUSPECT' if flag else ''}")
sys.exit(1 if bad else 0)
