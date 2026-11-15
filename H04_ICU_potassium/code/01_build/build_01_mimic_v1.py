"""H04 BUILD_r1 (MIMIC-IV 3.1): pair-level analysis datasets for 5/10/30-minute windows.
Spec: 01_protocol/BUILD_r1_规格.md. Writes row-level data ONLY to 04_derived (local only).
Never computes any between-source potassium contrast; summary = rounded counts only (whitelist checked).
Usage: python -I build_01_mimic_v1.py <run_dir> <spec_path> <expected_spec_sha256>
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
from array import array
from datetime import datetime
from pathlib import Path

ARCHIVE = Path(os.environ.get("H04_MIMIC_ZIP", "mimic-iv-3.1.zip"))  # public release: local path removed
ARCHIVE_SHA = "0dd448e341f489483194daafd884607d6f194648c6bf54eed56d1e2cd2af9e09"
PREFIX = "mimic-iv-3.1/"
OUT_DIR = Path(os.environ.get("H04_DERIVED_DIR", "04_derived/H04_20261111_BUILD_r1"))  # public release: local path removed
LAB_K, GAS_K, SPEC_TYPE, PH = "50971", "50822", "52033", "50820"
COV = {"wbc_51301": "51301", "wbc_51300": "51300", "platelet": "51265", "creatinine": "50912", "glucose": "50931"}
COV_ITEM = {v: k for k, v in COV.items()}
ALLOWED_UNIT = {"wbc_51301": "K/uL", "wbc_51300": "K/uL", "platelet": "K/uL", "creatinine": "mg/dL", "glucose": "mg/dL"}
EXPECTED = {5: (14147, 5171, 4883), 10: (23357, 9385, 8797), 30: (44328, 15320, 14017)}
WIN = 86400
ART = {"ART."}
NONART = {"VEN.", "CENTRAL VENOUS.", "MIX."}

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
        (RUN_DIR / "summary.json").write_text(json.dumps({"run_id": "H04_20261111_BUILD_r1_mimic", "STOP": reason}),
                                              encoding="utf-8")
        if not LOG.closed:
            log(f"STOP: {reason}")
            LOG.close()
        finish_provenance()
    finally:
        sys.exit(2)


def sec(v):
    d = datetime.fromisoformat(v)
    return d.toordinal() * 86400 + d.hour * 3600 + d.minute * 60 + d.second


def table(z, m):
    f = io.TextIOWrapper(gzip.GzipFile(fileobj=z.open(PREFIX + m)), encoding="utf-8", newline="")
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


def dedupe(evs):
    grp = collections.defaultdict(list)
    for e in evs:
        grp[e[0]].append(e)
    return sorted(g[0] for g in grp.values() if len(g) == 1)


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


def iso(s):
    d = datetime.fromordinal(s // 86400)
    r = s % 86400
    return f"{d:%Y-%m-%d} {r // 3600:02d}:{r % 3600 // 60:02d}:{r % 60:02d}"


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
    if OUT_DIR.exists() and any(OUT_DIR.glob("mimic_*")):
        fail("output data files already exist")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    log("verified")
    z = zipfile.ZipFile(ARCHIVE)

    c, rows = table(z, "hosp/patients.csv.gz")
    anchor = {}
    for r in rows:
        try:
            anchor[r[c["subject_id"]]] = (int(r[c["anchor_age"]]), int(r[c["anchor_year"]]), r[c["anchor_year_group"]])
        except ValueError:
            pass
    c, rows = table(z, "icu/icustays.csv.gz")
    stays = collections.defaultdict(list)
    stay_info = {}
    for r in rows:
        s, h, sid = r[c["subject_id"]], r[c["hadm_id"]], r[c["stay_id"]]
        a = anchor.get(s)
        if a is None:
            continue
        try:
            b, e = sec(r[c["intime"]]), sec(r[c["outtime"]])
        except ValueError:
            continue
        if e < b:
            continue
        age = a[0] + int(r[c["intime"]][:4]) - a[1]
        if age < 18:
            continue
        stays[s].append((b, e, h, sid))
        stay_info[sid] = (s, h, age, a[0] == 91, a[2], r[c["first_careunit"]])
    for iv in stays.values():
        iv.sort()

    def locate(s, t):
        hit = [x for x in stays.get(s, ()) if x[0] <= t <= x[1]]
        return hit[0] if len(hit) == 1 else None

    c, rows = table(z, "hosp/labevents.csv.gz")
    I = {k: c[k] for k in ("subject_id", "hadm_id", "specimen_id", "itemid", "charttime", "storetime", "value",
                           "valuenum", "valueuom", "comments")}
    events = collections.defaultdict(lambda: {LAB_K: [], GAS_K: []})
    spec_vals = collections.defaultdict(set)
    spec_subj = collections.defaultdict(set)
    spec_hadm = collections.defaultdict(set)
    ph_vals = collections.defaultdict(set)
    cov_raw = {k: collections.defaultdict(lambda: (array("q"), array("d"))) for k in COV}
    unit_bad = collections.Counter()
    target = {LAB_K, GAS_K, SPEC_TYPE, PH, *COV_ITEM}
    hadm_subject = {v[1]: v[0] for v in stay_info.values()}
    for r in rows:
        item = r[I["itemid"]]
        if item not in target:
            continue
        sp, s, h, ct = r[I["specimen_id"]], r[I["subject_id"]], r[I["hadm_id"]], r[I["charttime"]]
        if item == SPEC_TYPE:
            if sp:
                spec_vals[sp].add(r[I["value"]].strip())
                spec_subj[sp].add(s)
                spec_hadm[sp].add(h)
            continue
        vn = r[I["valuenum"]]
        try:
            v = float(vn) if vn else float("nan")
        except ValueError:
            v = float("nan")
        if item == PH:
            if sp:
                spec_subj[sp].add(s)
                spec_hadm[sp].add(h)
                if math.isfinite(v):
                    ph_vals[sp].add(v)
            continue
        if s not in stays or not ct:
            continue
        try:
            t = sec(ct)
        except ValueError:
            continue
        if item in COV_ITEM:
            k = COV_ITEM[item]
            if h and math.isfinite(v) and hadm_subject.get(h) == s:
                if r[I["valueuom"]] != ALLOWED_UNIT[k]:
                    unit_bad[k] += 1
                    continue
                tt, vv = cov_raw[k][h]
                tt.append(t)
                vv.append(v)
            continue
        hit = locate(s, t)
        if hit is None or (h and h != hit[2]):
            continue
        if not vn or not math.isfinite(v) or v <= 0 or r[I["valueuom"]] not in ("mEq/L", "mmol/L"):
            continue
        stt = r[I["storetime"]]
        hem = int("HEMOLY" in r[I["comments"]].upper())
        events[hit[3]][item].append((t, sp, v, stt, int(not h), hem))
    log("labevents done")

    # covariate lookup tables: per hadm sorted (time, value) with same-time conflicts removed
    cov_clean = {}
    for k in COV:
        per = {}
        for h, (tt, vv) in cov_raw[k].items():
            bt = collections.defaultdict(set)
            for t, v in zip(tt, vv):
                bt[t].add(v)
            lst = sorted((t, next(iter(vs))) for t, vs in bt.items() if len(vs) == 1)
            if lst:
                per[h] = ([x[0] for x in lst], [x[1] for x in lst])
        cov_clean[k] = per
        cov_raw[k] = None

    def nearest(k, h, t0):
        d = cov_clean[k].get(h)
        if not d:
            return None
        ts, vs = d
        i = bisect.bisect_left(ts, t0 - WIN)
        best = None
        while i < len(ts) and ts[i] <= t0 + WIN:
            dist = abs(ts[i] - t0)
            if best is None or dist < best[0]:
                best = (dist, ts[i], vs[i])
            i += 1
        return None if best is None else (best[2], (best[1] - t0) / 60)

    def spec_ok(sp, stay):
        if not sp:
            return False
        ss = spec_subj.get(sp)
        if ss and ss != {stay_info[stay][0]}:
            return False
        if not spec_hadm.get(sp, set()) <= {stay_info[stay][1], ""}:
            return False
        return True

    summary = {"run_id": "H04_20261111_BUILD_r1_mimic", "input_sha256_verified": True, "spec_sha256_verified": True,
               "covariate_unit_nonconforming_rows": dict(unit_bad), "windows": {}, "data_files": {}}
    header = ["pair_id", "subject_id", "hadm_id", "stay_id", "window_min", "lab_charttime", "gas_charttime",
              "signed_minutes", "lab_k", "gas_k", "lab_storetime", "gas_storetime", "lab_hadm_missing",
              "gas_hadm_missing", "gas_specimen_id", "specimen_type_raw", "specimen_class", "ph", "wbc", "wbc_source",
              "wbc_minutes", "platelet", "platelet_minutes", "creatinine", "creatinine_minutes", "glucose",
              "glucose_minutes", "icu_type", "age", "anchor_age_is_91", "anchor_year_group", "hemolysis_lab",
              "hemolysis_gas"]
    clean_events = {stay: (dedupe(src[LAB_K]), dedupe(src[GAS_K])) for stay, src in events.items()}
    for w in (5, 10, 30):
        rows_out = []
        for stay, (L, G) in clean_events.items():
            if L and G:
                for li, gi in pair_greedy(L, G, w * 60):
                    rows_out.append((stay, L[li], G[gi]))
        n_pairs = len(rows_out)
        n_stays = len({x[0] for x in rows_out})
        n_pts = len({stay_info[x[0]][0] for x in rows_out})
        if (n_pairs, n_stays, n_pts) != EXPECTED[w]:
            fail(f"window {w}: counts do not match FEAS")
        miss = collections.Counter()
        path = OUT_DIR / f"mimic_pairs_w{w}.csv.gz"
        with gzip.open(path, "wt", encoding="utf-8", newline="") as f:
            wr = csv.writer(f)
            wr.writerow(header)
            for n, (stay, l, g) in enumerate(sorted(rows_out, key=lambda x: (x[0], x[1][0], x[2][0])), 1):
                s, h, age, a91, ayg, cu = stay_info[stay]
                gsp = g[1]
                ok = spec_ok(gsp, stay)
                vs = spec_vals.get(gsp) if ok else None
                raw = "" if not vs else ("CONFLICT" if len(vs) > 1 else next(iter(vs)))
                cls = "ART" if raw in ART else ("NONART" if raw in NONART else "UNKNOWN")
                phv = ""
                if ok and len(ph_vals.get(gsp, ())) == 1:
                    phv = next(iter(ph_vals[gsp]))
                wb = nearest("wbc_51301", h, g[0])
                src = "51301"
                if wb is None:
                    wb = nearest("wbc_51300", h, g[0])
                    src = "51300" if wb is not None else "none"
                cov = {k: nearest(k, h, g[0]) for k in ("platelet", "creatinine", "glucose")}
                rec = [n, s, h, stay, w, iso(l[0]), iso(g[0]), (g[0] - l[0]) / 60, l[2], g[2], l[3], g[3], l[4], g[4],
                       gsp, raw, cls, phv,
                       "" if wb is None else wb[0], src, "" if wb is None else wb[1]]
                for k in ("platelet", "creatinine", "glucose"):
                    rec += ["", ""] if cov[k] is None else [cov[k][0], cov[k][1]]
                rec += [cu, age, int(a91), ayg, l[5], g[5]]
                wr.writerow(rec)
                for name, val in zip(header, rec):
                    if val == "" or val is None:
                        miss[name] += 1
        summary["windows"][str(w)] = {"matches_FEAS_exact_counts": True, "missing_by_column": dict(miss)}
        summary["data_files"][path.name] = sha(path)
        log(f"window {w} written")
    final = r10(summary)
    (RUN_DIR / "summary.json").write_text(json.dumps(final, ensure_ascii=False, indent=2), encoding="utf-8")
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
