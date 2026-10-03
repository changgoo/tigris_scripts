#!/usr/bin/env python3
"""Compare the last line of TIGRESS_NCR.hst across benchmark run directories.

  compare_hst.py RUNDIR [RUNDIR ...] [--ref=<name substring>] [--ncol=N]

Every run of one physics restarts the same checkpoint for the same number of cycles, so
the final history rows must agree. Builds with identical floating-point semantics agree to
the printed precision; flag variants that change the math mode (fast-math, fp-model,
vector width, FMA contraction) differ at round-off level, amplified by the turbulent
flow over 200 cycles. Reports, per run, the maximum relative difference over the first
N history columns (default: all) against the reference run (first match of --ref, else
the first directory).
"""
import os
import sys

args = [a for a in sys.argv[1:] if not a.startswith('--')]
opts = dict(a[2:].split('=', 1) for a in sys.argv[1:] if a.startswith('--') and '=' in a)
ncol = int(opts['ncol']) if 'ncol' in opts else None


def last_row(d):
    with open(os.path.join(d, 'TIGRESS_NCR.hst')) as f:
        rows = [ln for ln in f if ln.strip() and not ln.startswith('#')]
    return [float(x) for x in rows[-1].split()][:ncol]


rows = {}
for d in args:
    try:
        rows[d] = last_row(d)
    except (OSError, IndexError, ValueError) as e:
        print(f"{os.path.basename(d.rstrip('/')):40s} unreadable: {e}")
if not rows:
    sys.exit(1)
ref = next((d for d in rows if opts.get('ref', '\0') in d), next(iter(rows)))
r0 = rows[ref]
print(f"reference: {os.path.basename(ref.rstrip('/'))} (time={r0[0]:.6g})")
for d, r in rows.items():
    if len(r) != len(r0) or r[0] != r0[0]:
        print(f"{os.path.basename(d.rstrip('/')):40s} different time/columns (not comparable)")
        continue
    rel = max(abs(a - b) / max(abs(a), abs(b), 1e-300) for a, b in zip(r, r0))
    print(f"{os.path.basename(d.rstrip('/')):40s} max rel diff = {rel:.2e}")
