"""H04 BUILD_r1 (SICdb 1.0.8): pair-level analysis datasets for 5/10/30-minute windows.
Spec: 01_protocol/BUILD_r1_规格.md. Row-level data ONLY to 04_derived (local only).
Never computes any between-source potassium contrast; summary = rounded counts only.
Usage: python -I build_02_sicdb_v1.py <run_dir> <spec_path> <expected_spec_sha256>
"""
from __future__ import annotations

import bisect
import collections
import csv
import gzip
import hashlib
import io
import json
import math
import os
import platform
import shutil
import sys
import time
import zipfile
from datetime import datetime
from pathlib import Path

ARCHIVE = Path(os.environ.get("H04_SICDB_ZIP", "salzburg-intensive-care-database-sicdb-a-freely-accessible-intensive-care-database-1.0.8.zip"))  # public release: local path removed
ARCHIVE_SHA = "5332178a99dc2cf2a23c1cf7de13daaac5c488903114676a1002847f53781739"
OUT_DIR = Path(os.environ.get("H04_DERIVED_DIR", "04_derived/H04_20261111_BUILD_r1"))  # public release: local path removed
LAB_K, GAS_K = "463", "685"
COV = {"wbc": ["301"], "platelet": ["314"], "creatinine": ["367"], "glucose": ["348", "656"], "ph": ["688"]}
COV_ITEM = {i: (k, i) for k, l in COV.items() for i in l}
EXPECTED = {5: (4879, 3857, 3602), 10: (11211, 7231, 6428), 30: (22921, 9840, 8482)}
WIN = 86400

RUN_DIR, SPEC, SPEC_SHA = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3].lower()
RUN_DIR.mkdir(parents=True, exist_ok=False)
LOG = (RUN_DIR / "run.log").open("w", encoding="utf-8")
T0 = time.monotonic()
_FAILED = False


def log(m):
    line = f"{datetime.now().astimezone().isoformat(timespec='seconds')} [{time.monotonic()-T0:8.1f}s] {m}"
    print(line, flush=True)
    LOG.write(line + "\n")
    LOG.flush()


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for ch in iter(lambda: f.read(1 << 24), b""):
            h.update(ch)
    return h.hexdigest()


def finish_provenance():
    lines = [f"{sha(p)}  {p.relative_to(RUN_DIR).as_posix()}"
             for p in sorted(RUN_DIR.rglob("*")) if p.is_file() and p.name != "SHA256SUMS.txt"]
    (RUN_DIR / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def fail(reason):
    global _FAILED
    if _FAILED:
        sys.exit(2)
    _FAILED = True
    try:
        (RUN_DIR / "summary.json").write_text(json.dumps({"run_id": "H04_20261111_BUILD_r1_sicdb", "STOP": reason}),
                                              encoding="utf-8")
        if not LOG.closed:
            log(f"STOP: {reason}")
            LOG.close()
        finish_provenance()
    finally:
        sys.exit(2)


def member(z, name):
    return next(n for n in z.namelist() if n.endswith("/" + name))


def table(z, name):
    f = io.TextIOWrapper(gzip.GzipFile(fileobj=z.open(member(z, name))), encoding="utf-8-sig", newline="")
    r = csv.reader(f)
    h = next(r)
    return {c: i for i, c in enumerate(h)}, r


def r10(o):
    if isinstance(o, bool) or o is None or isinstance(o, (float, str)):
        return o
    if isinstance(o, int):
        return 0 if o == 0 else ("<10" if o < 10 else (o + 5) // 10 * 10)
    if isinstance(o, dict):
        return {k: r10(v) for k, v in o.items()}
    return o


def pair_greedy(L, G, limit):
    gt = [g[0] for g in G]
    cand = []
    for li, l in enumerate(L):
        lo = bisect.bisect_left(gt, l[0] - limit)
        hi = bisect.bisect_right(gt, l[0] + limit)
        for gi in range(lo, hi):
            cand.append((abs(l[0] - gt[gi]), l[0], gt[gi], li, gi))
    cand.sort()
    ul, ug, out = set(), set(), []
    for _, _, _, li, gi in cand:
        if li in ul or gi in ug:
            continue
        ul.add(li)
        ug.add(gi)
        out.append((li, gi))
    return out


def main():
    log(f"start; tz {datetime.now().astimezone().tzname()} UTC{datetime.now().astimezone().strftime('%z')}")
    (RUN_DIR / "code").mkdir()
    shutil.copy2(__file__, RUN_DIR / "code" / Path(__file__).name)
    shutil.copy2(SPEC, RUN_DIR / "code" / SPEC.name)
    (RUN_DIR / "environment.json").write_text(json.dumps({"python": sys.version, "platform": platform.platform()}),
                                              encoding="utf-8")
    if sha(SPEC) != SPEC_SHA:
        fail("spec sha256 mismatch")
    if sha(ARCHIVE) != ARCHIVE_SHA:
        fail("input sha256 mismatch")
    (RUN_DIR / "input_files.json").write_text(json.dumps({"archive": str(ARCHIVE), "sha256": ARCHIVE_SHA}), encoding="utf-8")
    if OUT_DIR.exists() and any(OUT_DIR.glob("sicdb_*")):
        fail("output data files already exist")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    z = zipfile.ZipFile(ARCHIVE)
    c, rows = table(z, "d_references.csv.gz")
    refs = {r[c["ReferenceGlobalID"]]: (r[c["ReferenceValue"]], r[c["ReferenceUnit"]]) for r in rows}
    if refs.get(LAB_K, ("", ""))[1] != "mmol/L" or refs.get(GAS_K, ("", ""))[1] != "mmol/L":
        fail("potassium unit not mmol/L")
    c, rows = table(z, "cases.csv.gz")
    case, seen = {}, set()
    for r in rows:
        cid = r[c["CaseID"]]
        if cid in seen:
            fail("CaseID not unique")
        seen.add(cid)
        try:
            age = float(r[c["AgeOnAdmission"]])
            icu0, tos = int(r[c["ICUOffset"]]), int(r[c["TimeOfStay"]])
        except ValueError:
            continue
        if age < 18 or tos < icu0:
            continue
        hu = r[c["HospitalUnit"]]
        case[cid] = (r[c["PatientID"]], icu0, tos, age, refs.get(hu, (hu, ""))[0])
    c, rows = table(z, "laboratory.csv.gz")
    ci, li, oi, vi, ti = c["CaseID"], c["LaboratoryID"], c["Offset"], c["LaboratoryValue"], c["LaboratoryType"]
    events = collections.defaultdict(lambda: {LAB_K: [], GAS_K: []})
    covraw = {i: collections.defaultdict(lambda: collections.defaultdict(set)) for i in COV_ITEM}
    for r in rows:
        lid, cid = r[li], r[ci]
        info = case.get(cid)
        if info is None:
            continue
        if lid in COV_ITEM:
            try:
                off, v = int(r[oi]), float(r[vi])
            except ValueError:
                continue
            if math.isfinite(v):
                covraw[lid][cid][off].add(v)
            continue
        if lid not in (LAB_K, GAS_K):
            continue
        try:
            off = int(r[oi])
            v = float(r[vi])
        except ValueError:
            continue
        if off < 0 or not (info[1] <= off <= info[2]) or not math.isfinite(v) or v <= 0:
            continue
        lt = r[ti]
        events[cid][lid].append((off, v, "ART" if refs.get(lt, ("",))[0] == "Arterial" else "UNKNOWN"))
    log("laboratory done")
    clean = {i: {cid: sorted((t, next(iter(vs))) for t, vs in d.items() if len(vs) == 1) for cid, d in covraw[i].items()}
             for i in COV_ITEM}

    def nearest(item, cid, t0):
        lst = clean[item].get(cid)
        if not lst:
            return None
        ts = [x[0] for x in lst]
        i = bisect.bisect_left(ts, t0 - WIN)
        best = None
        while i < len(ts) and ts[i] <= t0 + WIN:
            dist = abs(ts[i] - t0)
            if best is None or dist < best[0]:
                best = (dist, lst[i][0], lst[i][1])
            i += 1
        return None if best is None else (best[2], (best[1] - t0) / 60)

    clean_events = {}
    for cid, src in events.items():
        cl = {}
        for lid in (LAB_K, GAS_K):
            grp = collections.defaultdict(list)
            for e in src[lid]:
                grp[e[0]].append(e)
            cl[lid] = sorted(g[0] for g in grp.values() if len(g) == 1)
        clean_events[cid] = cl
    summary = {"run_id": "H04_20261111_BUILD_r1_sicdb", "input_sha256_verified": True, "spec_sha256_verified": True,
               "windows": {}, "data_files": {}}
    header = ["pair_id", "patient_id", "case_id", "window_min", "lab_offset", "gas_offset", "signed_minutes", "lab_k",
              "gas_k", "specimen_class", "ph", "wbc", "wbc_minutes", "platelet", "platelet_minutes", "creatinine",
              "creatinine_minutes", "glucose", "glucose_source", "glucose_minutes", "hospital_unit_last", "age_recorded"]
    for w in (5, 10, 30):
        out = []
        for cid, cl in clean_events.items():
            if cl[LAB_K] and cl[GAS_K]:
                for a, b in pair_greedy(cl[LAB_K], cl[GAS_K], w * 60):
                    out.append((cid, cl[LAB_K][a], cl[GAS_K][b]))
        if (len(out), len({x[0] for x in out}), len({case[x[0]][0] for x in out})) != EXPECTED[w]:
            fail(f"window {w}: counts do not match FEAS")
        miss = collections.Counter()
        path = OUT_DIR / f"sicdb_pairs_w{w}.csv.gz"
        with gzip.open(path, "wt", encoding="utf-8", newline="") as f:
            wr = csv.writer(f)
            wr.writerow(header)
            for n, (cid, l, g) in enumerate(sorted(out, key=lambda x: (x[0], x[1][0], x[2][0])), 1):
                pid, _, _, age, hu = case[cid]
                ph_vals = clean["688"].get(cid)
                phv = ""
                if ph_vals:
                    m = [v for t, v in ph_vals if t == g[0]]
                    phv = m[0] if len(m) == 1 else ""
                rec = [n, pid, cid, w, l[0], g[0], (g[0] - l[0]) / 60, l[1], g[1], g[2], phv]
                for item in ("301", "314", "367"):
                    x = nearest(item, cid, g[0])
                    rec += ["", ""] if x is None else [x[0], x[1]]
                gx, gsrc = nearest("348", cid, g[0]), "348"
                if gx is None:
                    gx, gsrc = nearest("656", cid, g[0]), "656"
                    if gx is None:
                        gsrc = "none"
                rec += ["", gsrc, ""] if gx is None else [gx[0], gsrc, gx[1]]
                rec += [hu, age]
                wr.writerow(rec)
                for name, val in zip(header, rec):
                    if val == "" or val is None:
                        miss[name] += 1
        summary["windows"][str(w)] = {"matches_FEAS_exact_counts": True, "missing_by_column": dict(miss)}
        summary["data_files"][path.name] = sha(path)
        log(f"window {w} written")
    (RUN_DIR / "summary.json").write_text(json.dumps(r10(summary), ensure_ascii=False, indent=2), encoding="utf-8")
    log("done")
    finish_provenance()
    LOG.close()


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        fail(f"unhandled {type(e).__name__}")
