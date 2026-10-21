#!/usr/bin/env python3
"""Basic history plots of TIGRESS-NCR runs from <problem_id>.hst and .hst.phase*.

    plot_history_ncr.py RUNDIR [RUNDIR ...] [--out history.png] [--labels a b ...]

Code units are read from the run's athinput.runtime and out*.txt unit table (pc, Msun,
Myr in code units). Panels: gas surface density, star formation rate surface density
(young-star mass within 10 and 40 Myr), kinetic and magnetic energy per area, mass and
volume fractions of the gas phases, the escaped LyC fraction and the FUV fraction handed
to the plane-parallel approximation.
Several run directories are overlaid on one time axis.
"""
import argparse
import glob
import os.path as osp
import re

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


def read_hst(fname):
    """Return (column names, data array) of an Athena++ history file."""
    names = None
    with open(fname) as f:
        for line in f:
            if line.startswith("#") and "[1]=" in line:
                names = [re.sub(r"\[\d+\]=", "", tok) for tok in line[1:].split() if "]=" in tok]
                break
    if names is None:
        raise ValueError(f"{fname}: no column header (restart into a new directory?)")
    data = np.loadtxt(fname, comments="#", ndmin=2)
    # keep the last occurrence of each time (a restart repeats rows), sorted by time
    _, first_in_reversed = np.unique(data[::-1, 0], return_index=True)
    return names, data[len(data) - 1 - first_in_reversed]


def safe_ratio(num, den):
    return np.divide(num, den, out=np.full_like(den, np.nan), where=den > 0)


def code_constants(rundir):
    """Msun and Myr in code units, and the box area in pc^2."""
    consts = {}
    for out in sorted(glob.glob(osp.join(rundir, "out*.txt"))):
        with open(out) as f:
            for line in f:
                m = re.match(r"\s*(Msun|Myr)\s*=\s*([0-9.eE+-]+)", line)
                if m:
                    consts[m.group(1)] = float(m.group(2))
        if len(consts) == 2:
            break
    mesh = {}
    block = None
    with open(osp.join(rundir, "athinput.runtime")) as f:
        for line in f:
            line = line.split("#")[0].strip()
            if line.startswith("<"):
                block = line.strip("<>")
            elif block == "mesh" and "=" in line:
                key, val = (s.strip() for s in line.split("=", 1))
                mesh[key] = val
    area = (float(mesh["x1max"]) - float(mesh["x1min"])) * (
        float(mesh["x2max"]) - float(mesh["x2min"]))
    res = (float(mesh["x1max"]) - float(mesh["x1min"])) / float(mesh["nx1"])
    return consts["Msun"], consts["Myr"], area, res


def phase_fractions(rundir, basename):
    """time and {phase name: (mass fraction, volume fraction)} from the phase histories."""
    out = {}
    tphase = None
    tot_m = tot_v = None
    files = sorted(glob.glob(osp.join(rundir, f"{basename}.hst.phase*")))
    for fname in files:
        with open(fname) as f:
            first = f.readline()
        m = re.search(r"phase\d+=(\S+)", first)
        label = m.group(1) if m else osp.basename(fname).split(".")[-1]
        names, data = read_hst(fname)
        t, vol, mass = data[:, 0], data[:, names.index("vol")], data[:, names.index("mass")]
        if tphase is None:
            tphase, tot_m, tot_v = t, np.zeros_like(t), np.zeros_like(t)
        n = min(len(t), len(tphase))
        tphase, tot_m, tot_v = tphase[:n], tot_m[:n], tot_v[:n]
        out = {k: (v[0][:n], v[1][:n]) for k, v in out.items()}
        out[label] = (mass[:n], vol[:n])
        tot_m += mass[:n]
        tot_v += vol[:n]
    return tphase, {k: (m / tot_m, v / tot_v) for k, (m, v) in out.items()}


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("rundirs", nargs="+")
    p.add_argument("--out", default="history.png")
    p.add_argument("--labels", nargs="*")
    p.add_argument("--basename", default="TIGRESS_NCR")
    args = p.parse_args()
    labels = args.labels or [osp.basename(osp.normpath(d)) for d in args.rundirs]

    fig, axes = plt.subplots(3, 2, figsize=(11, 10), sharex=True, constrained_layout=True)
    ax = axes.ravel()
    phase_colors = {}
    for i, (rundir, label) in enumerate(zip(args.rundirs, labels)):
        msun, myr, area, res = code_constants(rundir)
        names, h = read_hst(osp.join(rundir, f"{args.basename}.hst"))
        col = {n: h[:, k] for k, n in enumerate(names)}
        t = col["time"] / myr
        ls = ["-", "--", ":", "-."][i % 4]
        c = f"C{i}"
        ax[0].plot(t, col["mass"] / msun / area, ls=ls, c=c, label=f"{label} ({res:g} pc)")
        for key, alpha in (("mstar10", 1.0), ("mstar40", 0.5)):
            age = float(key[5:])
            ax[1].plot(t, col[key] / msun / (age * myr) / area, ls=ls, c=c, alpha=alpha,
                       label=f"{label}, {key[5:]} Myr")
        ke = sum(col[f"{d}-KE"] for d in (1, 2, 3)) / area
        me = sum(col[f"{d}-ME"] for d in (1, 2, 3)) / area
        ax[2].semilogy(t, ke, ls=ls, c="C0", label=f"{label} kinetic")
        ax[2].semilogy(t, me, ls=ls, c="C3", label=f"{label} magnetic")
        tp, frac = phase_fractions(rundir, args.basename)
        if tp is not None:
            for ph, (fm, fv) in frac.items():
                pc = phase_colors.setdefault(ph, f"C{len(phase_colors)}")
                lab = ph if i == 0 else None
                ax[3].plot(tp / myr, fm, ls=ls, c=pc, label=lab)
                ax[4].semilogy(tp / myr, fv, ls=ls, c=pc, label=lab)
        # LyC escapes through the box faces; FUV (LW, PE) rays beyond dist_xy_max are handed
        # to the plane-parallel approximation instead (Lpp), so their Lesc stays zero
        if "Ltot0" in col and "Lesc0" in col:
            ax[5].semilogy(t, safe_ratio(col["Lesc0"], col["Ltot0"]), ls=ls, c="C0",
                           label=f"{label} LyC escaped")
        if all(f"{k}{b}" in col for k in ("Ltot", "Lpp") for b in (1, 2)):
            ax[5].semilogy(t, safe_ratio(col["Lpp1"] + col["Lpp2"], col["Ltot1"] + col["Ltot2"]),
                           ls=ls, c="C1", label=f"{label} FUV to plane-parallel")

    ax[0].set_ylabel(r"$\Sigma_{\rm gas}\ [M_\odot\,{\rm pc}^{-2}]$")
    ax[1].set_ylabel(r"$\Sigma_{\rm SFR}\ [M_\odot\,{\rm kpc}^{-2}\,{\rm yr}^{-1}]$")
    ax[2].set_ylabel(r"energy / area [code]")
    ax[3].set_ylabel("mass fraction")
    ax[4].set_ylabel("volume fraction")
    ax[5].set_ylabel("fraction of emitted luminosity")
    for a in ax:
        a.legend(fontsize=7, ncol=2)
        a.grid(alpha=0.3)
    for a in axes[-1]:
        a.set_xlabel("time [Myr]")
    fig.savefig(args.out, dpi=150)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
