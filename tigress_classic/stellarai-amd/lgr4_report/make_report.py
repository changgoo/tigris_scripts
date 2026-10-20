"""Rebuild the LGR4 CRMHD restart progress report (status, segment table, summary movie, history data).

    python make_report.py [--publish-dir DIR]

Reads the run directories and Slurm logs, fills base.html, and writes into WORK:
  report_body.html  page body as published on claude.ai (no <html>/<head> skeleton)
  index.html        standalone page (same content with the skeleton)
  lgr4_summary.webm, poster.jpg, series.json, frames/
With --if-changed, exits early unless a segment or snapshot frame was added (state.json).
With --publish-dir, copies index.html, the movie and the poster there (e.g. public_html).
Needs numpy and PIL (the pyathena conda env) and ffmpeg with libvpx-vp9. Run it on a login node:
/projects (the original run's history, public_html) is not mounted on the compute nodes.
"""
import argparse, datetime as dt, glob, html, json, os, re, shutil, subprocess
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SLURMDIR = os.path.dirname(HERE)
WORK = "/scratch/gpfs/EOST/changgoo/tigress_classic/lgr4_report"
TC = "/scratch/gpfs/EOST/changgoo/tigress_classic"
ORIG = ("/projects/EOSTRIKE/TIGRESSPP-CR/6kpc_LGR4_crmhd_duale-8pc-b1-mhdbc_diode-crbc_lngrad_out-"
        "fgas_0.90-r200-t2.5-icpx/TIGRESS.hst")
RUNS = {  # label: (run dir, slurm log prefix, cells, grid text, nodes)
    "8pc": (f"{TC}/LGR4-crmhd-8pc-t450", "LGR4-cr8pc", 128 * 128 * 1536,
            "128×128×1536, 768 blocks of 32³, 8 nodes", "1.2e-4 (CR limited)"),
    "4pc": (f"{TC}/LGR4-crmhd-4pc-t450", "LGR4-cr4pc", 256 * 256 * 3072,
            "256×256×3072, 1536 blocks of 64×64×32, 16 nodes", "6.0e-5 (CR limited)"),
}
T0, TLIM = 450.0, 550.0
MU, TU, AREA = 50 / 2021.69, 0.9778, 1024.0 ** 2  # Msun per code mass, Myr per code time, pc^2


# ---------------------------------------------------------------- history series
def read_hst(fname):
    names, rows = None, []
    for line in open(fname):
        if line.startswith("# ["):
            names = re.findall(r"\[\d+\]=(\S+)", line)
        elif not line.startswith("#") and line.strip():
            rows.append(line.split())
    n = len(names)
    d = np.array([[float(x) for x in r[:n]] for r in rows if len(r) >= n])
    t = d[:, 0]
    keep = np.zeros(len(t), bool)
    tmin = np.inf
    for i in range(len(t) - 1, -1, -1):  # keep the last-written row for each time (restarts overwrite)
        if t[i] < tmin:
            keep[i] = True
            tmin = t[i]
    return {k: d[keep, i] for i, k in enumerate(names)}


def series():
    # the original run is finished: compute its series once and cache it
    cache = f"{WORK}/series_orig.json"
    srcs = {} if os.path.exists(cache) else {"orig": (ORIG, 128 * 128 * 1536, 300.0)}
    srcs.update({k: (f"{v[0]}/TIGRESS.hst", v[2], T0) for k, v in RUNS.items()})
    keys = ["t", "Sgas", "Ssfr", "outflow", "Ec", "ME", "KE", "Eth", "ceil_cool", "floor_cool", "mceil",
            "nbad_d", "nbad_p", "nfofc", "dm_floor", "dec_floor"]
    out = {}
    for lab, (fn, nc, tstart) in srcs.items():
        h = read_hst(fn)
        m0 = h["time"] > tstart
        h = {k: v[m0] for k, v in h.items()}
        t = h["time"]
        dtc = np.diff(np.r_[tstart, t])
        cum = h["mass_loss_upper"] - h["mass_loss_lower"]
        S = {k: [] for k in keys}
        for a in np.arange(tstart, np.floor(t[-1]) - 1 + 1e-6, 1.0):
            b = a + 1
            m = (t > a) & (t <= b + 1e-9)
            if m.sum() < 5:
                continue
            idx = np.where(m)[0]
            sp = dtc[m].sum()
            upd = (dtc[m] / h["dt"][m]).sum() * nc
            s = lambda k: h[k][m].sum()
            mean = lambda k: h[k][m].mean()
            M = mean("mass")
            ke = mean("1-KE") + mean("2-KE") + mean("3-KE")
            me = mean("1-ME") + mean("2-ME") + mean("3-ME")
            i0 = idx[0] - 1 if idx[0] > 0 else idx[0]
            S["t"].append(0.5 * (a + b))
            S["Sgas"].append(M * MU / AREA)
            S["Ssfr"].append(mean("mstar10") * MU / 1e7 / (AREA / 1e6))
            S["outflow"].append((cum[idx[-1]] - cum[i0]) / (t[idx[-1]] - t[i0]) * MU / (TU * 1e6) / (AREA / 1e6))
            S["Ec"].append(mean("0-Ec"))
            S["ME"].append(me)
            S["KE"].append(ke)
            S["Eth"].append(mean("tot-E") - ke - me)
            new = "de_ceil" in h  # columns only the new runs have
            S["ceil_cool"].append(s("de_ceil") / s("e_cool") if new else None)
            S["floor_cool"].append(-s("e_floor_ctop") / s("e_cool") if new else None)  # orig column differs
            S["mceil"].append(s("mass_added") / sp / M)
            S["nbad_d"].append(s("nbad_d") / upd)
            S["nbad_p"].append(s("nbad_p") / upd)
            S["nfofc"].append(s("nfofc") / upd)
            S["dm_floor"].append(s("dm_floor") / sp / M if new else None)
            S["dec_floor"].append(s("dec0_floor") / sp / mean("0-Ec") if new else None)
        out[lab] = {k: [None if x is None else float(f"{x:.4g}") for x in v] for k, v in S.items()}
    if "orig" in out:
        json.dump(out["orig"], open(cache, "w"), separators=(",", ":"))
    out = {"orig": json.load(open(cache)), **{k: v for k, v in out.items() if k != "orig"}}
    return out


# ---------------------------------------------------------------- segments
def last_time(fname):
    with open(fname, "rb") as f:
        f.seek(0, 2)
        f.seek(max(0, f.tell() - 20000))
        txt = f.read().decode(errors="ignore")
    m = re.findall(r"\btime=([0-9.eE+-]+)", txt)
    return float(m[-1]) if m else None


def sacct(jobid):
    r = subprocess.run(["sacct", "-X", "-n", "-P", "-j", str(jobid), "-o", "State,Elapsed,End"],
                       capture_output=True, text=True).stdout.strip().split("\n")[0].split("|")
    return (r + ["", "", ""])[:3]


def segments(lab):
    rundir, prefix = RUNS[lab][0], RUNS[lab][1]
    jobs = sorted(int(re.search(r"-(\d+)\.out$", f).group(1))
                  for f in glob.glob(f"{SLURMDIR}/{prefix}-*.out"))
    outs = [f"{rundir}/out.txt"] + sorted(glob.glob(f"{rundir}/out.r*.txt"),
                                          key=lambda f: int(re.search(r"out\.r(\d+)", f).group(1)))
    segs = []
    for i, f in enumerate(outs):
        job = jobs[i] if i < len(jobs) else None
        state, elapsed, end = sacct(job) if job else ("", "", "")
        segs.append(dict(seg=i + 1, job=job, state=state, elapsed=elapsed, end=end, t=last_time(f),
                         mtime=os.path.getmtime(f)))
    return segs


def hours(el):
    p = el.split("-")
    d = int(p[0]) if len(p) == 2 else 0
    hh, mm, ss = (int(x) for x in p[-1].split(":"))
    return 24 * d + hh + mm / 60 + ss / 3600


def status_cards(allsegs, now):
    cards, rows = [], []
    for lab, segs in allsegs.items():
        rundir, _, _, grid, dtxt = RUNS[lab]
        cur = segs[-1]
        t = cur["t"] or T0
        done = t >= TLIM - 1e-6
        frac = min(1.0, (t - T0) / (TLIM - T0))
        full = [s for s in segs if s["state"] == "COMPLETED" and s["elapsed"] and hours(s["elapsed"]) > 23]
        prev_t = [T0] + [s["t"] for s in segs[:-1]]
        rates = [s["t"] - pt for s, pt in zip(segs, prev_t) if s in full]
        rate = np.mean(rates) if rates else None
        res = lab.replace("pc", " pc")
        color = "--c-8" if lab == "8pc" else "--c-4"
        if done:
            pill = '<span class="pill ok">finished</span>'
            end = segs[-1]["end"][:10] if segs[-1]["end"] else ""
            prog = f"t = 450 → 550 (done{', ' + end if end else ''})"
            extra = ""
        else:
            pill = '<span class="pill run">running</span>' if cur["state"] == "RUNNING" else \
                   f'<span class="pill run">{html.escape(cur["state"].lower() or "queued")}</span>'
            prog = f"t ≈ {t:.1f} of 550 (segment {cur['seg']}, job {cur['job']})"
            extra = ""
            if rate:
                nleft = (TLIM - t) / rate
                eta = now + dt.timedelta(hours=24 * nleft)
                extra = (f"<dt>Rate</dt><dd>≈ {rate:.1f} time units per 24 h segment</dd>"
                         f"<dt>Finish</dt><dd>≈ {nleft:.1f} more segments, around {eta:%b %-d}"
                         f" (plus queue waits)</dd>")
        jobs = ", ".join(f"{s['job']} ({hours(s['elapsed']):.1f} h)" if s["elapsed"] else str(s["job"])
                         for s in segs)
        cards.append(
            f'<div class="run">\n<h3>{res} run {pill}</h3>\n<div class="meter" aria-hidden="true">'
            f'<i style="width:{100 * frac:.1f}%;background:var({color})"></i></div>\n<dl class="kv">'
            f"<dt>Progress</dt><dd>{prog}</dd>{extra}<dt>Jobs</dt><dd>{jobs}</dd>"
            f"<dt>Grid</dt><dd>{grid}</dd><dt>dt</dt><dd>{dtxt}</dd>"
            f"<dt>Run dir</dt><dd><code>{rundir}</code></dd></dl>\n</div>")
        for s in segs:
            if s["state"] == "RUNNING":
                el, tt = "running", f"≈ {s['t']:.1f} at {dt.datetime.fromtimestamp(s['mtime']):%H:%M %b %-d}"
            else:
                el = s["elapsed"][:-3] if s["elapsed"] else "—"
                tt = "550 (tlim)" if s["t"] and s["t"] >= TLIM - 1e-6 else (f"{s['t']:.2f}" if s["t"] else "—")
            rows.append(f'<tr><td>{res}</td><td>{s["job"]}</td><td>{s["seg"]}</td>'
                        f'<td class="n">{el}</td><td class="n">{tt}</td></tr>')
    status = '<section class="status" aria-label="Run status">\n' + "\n".join(cards) + "\n</section>"
    return status, "\n".join(rows)


# ---------------------------------------------------------------- movie
def movie():
    from PIL import Image, ImageDraw, ImageFont
    fdir = f"{WORK}/frames"
    os.makedirs(fdir, exist_ok=True)
    W = 960
    H = int(3403 * W / 4452) // 2 * 2
    try:
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", 22)
    except Exception:
        font = ImageFont.load_default()
    stamp_f = f"{fdir}/stamps.json"
    stamps = json.load(open(stamp_f)) if os.path.exists(stamp_f) else {}
    last4 = None
    for n in range(451, 551):
        srcs = [f"{RUNS[r][0]}/snapshot/snapshot_{n:05d}.png" for r in ("8pc", "4pc")]
        key = [os.path.getmtime(f) if os.path.exists(f) else 0 for f in srcs]
        if key[1]:
            last4 = n
        out = f"{fdir}/f{n:04d}.png"
        if stamps.get(str(n)) == key and os.path.exists(out):
            continue
        canvas = Image.new("RGB", (2 * W, H + 36), "white")
        d = ImageDraw.Draw(canvas)
        for k, (res, f) in enumerate(zip(("8 pc", "4 pc"), srcs)):
            x0 = k * W
            if os.path.exists(f):
                canvas.paste(Image.open(f).convert("RGB").resize((W, H), Image.LANCZOS), (x0, 36))
            else:
                d.rectangle([x0, 36, x0 + W, 36 + H], fill=(235, 235, 240))
                d.text((x0 + W // 2 - 150, 36 + H // 2), f"{res} run still in progress", fill=(90, 90, 110), font=font)
            d.text((x0 + 12, 6), res, fill=(20, 20, 30), font=font)
        canvas.save(out)
        stamps[str(n)] = key
    json.dump(stamps, open(stamp_f, "w"))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", "6", "-start_number", "451", "-i",
                    f"{fdir}/f%04d.png", "-c:v", "libvpx-vp9", "-crf", "34", "-b:v", "0", "-row-mt", "1",
                    "-pix_fmt", "yuv420p", f"{WORK}/lgr4_summary.webm"], check=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", f"{fdir}/f0490.png", "-vf", "scale=1280:-2",
                    "-q:v", "4", f"{WORK}/poster.jpg"], check=True)
    size = os.path.getsize(f"{WORK}/lgr4_summary.webm") / 1e6
    if last4 is None or last4 >= 550:
        note = ""
    else:
        note = f"The 4 pc panel is blank after t = {last4}, its last post-processed snapshot."
    return note, size


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--publish-dir")
    ap.add_argument("--no-movie", action="store_true")
    ap.add_argument("--if-changed", action="store_true",
                    help="do nothing unless a segment or a post-processed snapshot was added since the last build")
    a = ap.parse_args()
    os.makedirs(WORK, exist_ok=True)
    now = dt.datetime.now()
    allsegs = {lab: segments(lab) for lab in RUNS}
    state = {lab: [[s["job"], s["state"]] for s in segs] for lab, segs in allsegs.items()}
    state["frames"] = {lab: len(glob.glob(f"{RUNS[lab][0]}/snapshot/snapshot_*.png")) for lab in RUNS}
    state_f = f"{WORK}/state.json"
    if a.if_changed and os.path.exists(state_f) and json.load(open(state_f)) == json.loads(json.dumps(state)):
        print("no change since the last report")
        return
    status, rows = status_cards(allsegs, now)
    data = series()
    json.dump(data, open(f"{WORK}/series.json", "w"), separators=(",", ":"))
    if a.no_movie and os.path.exists(f"{WORK}/lgr4_summary.webm"):
        note, size = json.load(open(f"{WORK}/movie_note.json"))
    else:
        note, size = movie()
        json.dump([note, size], open(f"{WORK}/movie_note.json", "w"))
    T = open(f"{HERE}/base.html").read()
    T = T.replace("__DATE__", f"{now:%Y-%m-%d %H:%M}").replace("__STATUS__", status)
    T = T.replace("__SEGMENTS__", rows).replace("VP9 WebM, 6 MB", f"VP9 WebM, {size:.0f} MB")
    T = T.replace("__MOVIENOTE__", note)
    T = T.replace("__GENSRC__", html.escape(open(os.path.abspath(__file__)).read().rstrip("\n")))
    T = T.replace("__DATA__", json.dumps(data, separators=(",", ":")).replace("</", "<\\/"))
    open(f"{WORK}/report_body.html", "w").write(T)
    head, body = T.split("</style>", 1)
    page = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" '
            'content="width=device-width, initial-scale=1, viewport-fit=cover">\n' + head + "</style>\n</head>\n<body>"
            + body + "\n</body>\n</html>\n")
    open(f"{WORK}/index.html", "w").write(page)
    if a.publish_dir:
        os.makedirs(a.publish_dir, exist_ok=True)
        for f in ("index.html", "lgr4_summary.webm", "poster.jpg"):
            shutil.copy(f"{WORK}/{f}", f"{a.publish_dir}/{f}")
            os.chmod(f"{a.publish_dir}/{f}", 0o644)
    json.dump(state, open(state_f, "w"))
    t4 = allsegs["4pc"][-1]["t"]
    print(f"report updated {now:%Y-%m-%d %H:%M}: 4 pc t = {t4:.2f}, segment {allsegs['4pc'][-1]['seg']}; {note}")


if __name__ == "__main__":
    main()
