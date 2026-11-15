"""H04 FIG_r3 (layout revision; reads SHARE_r3): publication figures (spec 01_protocol/FIG_r1_规格.md). Figure 2 reads the two 10-minute pair files only
to build 2-D bin counts; bins with <10 pairs are not drawn; no individual points or values are written.
Usage: python -I fig_01_figures_v1.py <out_dir> <spec_path> <spec_sha256>
"""
from __future__ import annotations

import csv
import gzip
import hashlib
import json
import os
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.colors import LogNorm

ROOT = Path(os.environ.get("H04_PROJECT_DIR", "."))  # public release: local path removed
DATA = {"mimic": (ROOT / "04_derived/H04_20261111_BUILD_r1/mimic_pairs_w10.csv.gz", "24ad13a48afa15a276388a1e6707ac3e61d5cc7584dbb3eb93888d47438bf62f"),
        "sicdb": (ROOT / "04_derived/H04_20261111_BUILD_r1/sicdb_pairs_w10.csv.gz", "19c39916fb701571339bb6de523882189e457b74488490267c14564117100a83")}
PUB = ROOT / "05_results/H04_20261111_SHARE_r3/publish_numbers.json"
FEAS = {"mimic": {5: (14147, 5171, 4883), 10: (23357, 9385, 8797), 30: (44328, 15320, 14017)},
        "sicdb": {5: (4879, 3857, 3602), 10: (11211, 7231, 6428), 30: (22921, 9840, 8482)}}
LABEL = {"mimic": "MIMIC-IV", "sicdb": "SICdb"}
OUT, SPEC, SPEC_SHA = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3].lower()
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
r10 = lambda n: 0 if n == 0 else ("<10" if n < 10 else (n + 5) // 10 * 10)
plt.rcParams.update({"font.family": "Arial", "font.size": 9})


def stop(m):
    print("STOP:", m); sys.exit(2)


def save(fig, name):
    fig.savefig(OUT / f"{name}.png", dpi=300, bbox_inches="tight")
    fig.savefig(OUT / f"{name}.tiff", dpi=600, bbox_inches="tight", pil_kwargs={"compression": "tiff_lzw"})
    plt.close(fig)


def main():
    if OUT.exists():
        stop("out_dir exists")
    if sha(SPEC) != SPEC_SHA:
        stop("spec hash mismatch")
    for db, (p, h) in DATA.items():
        if sha(p) != h:
            stop(f"data hash mismatch {db}")
    pub = json.loads(PUB.read_text(encoding="utf-8"))
    # ---- figure 2 bins (computed before anything is written) ----
    xe = np.round(np.arange(1.5, 8.5001, 0.1), 2); ye = np.round(np.arange(-2.0, 2.0001, 0.1), 2)
    bins, info = {}, {}
    for db, (p, _) in DATA.items():
        M, D = [], []
        with gzip.open(p, "rt", encoding="utf-8", newline="") as f:
            for r in csv.DictReader(f):
                g, l = float(r["gas_k"]), float(r["lab_k"])
                M.append((g + l) / 2); D.append(g - l)
        M, D = np.array(M), np.array(D)
        # shift edges by half the measurement resolution so discrete values do not sit on bin edges
        H, _, _ = np.histogram2d(M, D, bins=[xe - 0.025, ye - 0.025])
        inside = int(H.sum()); masked = int(H[(H > 0) & (H < 10)].sum())
        bins[db] = H; info[db] = {"n": len(M), "outside_range_R": r10(len(M) - inside), "in_masked_bins_R": r10(masked)}
        del M, D
    OUT.mkdir(parents=True)
    # ---- figure 1 flow ----
    fig, axes = plt.subplots(2, 1, figsize=(5.5, 6.0))
    for ax, db in zip(axes, ("mimic", "sicdb")):
        ax.axis("off"); ax.set_xlim(0, 1); ax.set_ylim(0, 1)
        src = ("MIMIC-IV 3.1: adults in ICU\nlaboratory K (itemid 50971) and blood gas K (itemid 50822)\nvalid values, same-time duplicates removed" if db == "mimic"
               else "SICdb 1.0.8: cases with recorded age ≥20, within the case period\nlaboratory K (463) and blood gas K (685)\nvalid values, same-time duplicates removed")
        ax.text(0.5, 0.97, LABEL[db], ha="center", va="top", fontsize=9, fontweight="bold")
        ax.text(0.5, 0.84, src, ha="center", va="top", fontsize=7.5, bbox=dict(boxstyle="round", fc="white", ec="black"))
        ax.annotate("", xy=(0.5, 0.36), xytext=(0.5, 0.56), arrowprops=dict(arrowstyle="->"))
        ax.text(0.53, 0.46, "greedy one-to-one pairing by time difference\nwithin the same ICU stay (MIMIC) / case (SICdb)", ha="left", va="center", fontsize=7)
        lines = []
        for w in (10, 5, 30):
            n, s, pt = FEAS[db][w]
            lines.append(f"{w}-min window{' (primary)' if w == 10 else ''}: {n:,} pairs; {s:,} {'stays' if db == 'mimic' else 'cases'}; {pt:,} patients")
        ax.text(0.5, 0.32, "\n".join(lines), ha="center", va="top", fontsize=7.5, bbox=dict(boxstyle="round", fc="#f2f2f2", ec="black"))
    fig.tight_layout()
    save(fig, "fig1_flow")
    # ---- figure 2 Bland-Altman (binned) ----
    fig, axes = plt.subplots(1, 2, figsize=(7.2, 3.4), sharey=True)
    for ax, db in zip(axes, ("mimic", "sicdb")):
        H = bins[db].copy(); H[H < 10] = np.nan
        im = ax.pcolormesh(xe - 0.025, ye - 0.025, H.T, norm=LogNorm(vmin=10, vmax=np.nanmax(H)), cmap="Greys", shading="flat")
        P = pub[db]["P"]
        for v, ls in ((P["mean_diff"]["est"], "-"), (P["loa_emp_lo"]["est"], "--"), (P["loa_emp_hi"]["est"], "--")):
            ax.axhline(v, color="#b2182b", ls=ls, lw=1)
        ax.set_xlim(2.0, 7.5); ax.set_ylim(-2, 2)
        ax.set_title(LABEL[db], fontsize=9, fontweight="bold")
    axes[0].set_ylabel("Blood gas K − laboratory K (mmol/L)")
    fig.supxlabel("Mean of blood gas and laboratory K (mmol/L)", fontsize=9, y=-0.04)
    cb = fig.colorbar(im, ax=axes, shrink=0.85); cb.set_label("Pairs per 0.1 × 0.1 mmol/L cell (cells <10 not shown)")
    save(fig, "fig2_bland_altman")
    # ---- figure 3 forest ----
    labels = {"3.0": "<3.0", "3.5": "<3.5", "5.0": ">5.0", "5.5": "≥5.5", "6.0": "≥6.0"}
    fig, axes = plt.subplots(1, 2, figsize=(7.2, 3.4), sharey=True)
    for ax, (k, title) in zip(axes, (("gas_only", "Blood gas abnormal, laboratory not"), ("lab_only", "Laboratory abnormal, blood gas not"))):
        y = 0; yt, yl = [], []
        for c in ("3.0", "3.5", "5.0", "5.5", "6.0"):
            for j, db in enumerate(("mimic", "sicdb")):
                e = pub[db]["P"]["thresholds"][c][k]["pct"]
                yy = y + (0.18 if j == 0 else -0.18)
                if e is not None:
                    ax.errorbar(e["pct"], yy, xerr=[[e["pct"] - e["lo"]], [e["hi"] - e["pct"]]], fmt="o" if j == 0 else "s",
                                color="black" if j == 0 else "#7f7f7f", ms=4, capsize=2, lw=1)
                else:
                    ax.text(0.05, yy, "<10 pairs (not shown)", fontsize=6, va="center", color="#7f7f7f")
            yt.append(y); yl.append(labels[c]); y -= 1
        ax.set_yticks(yt); ax.set_yticklabels(yl); ax.set_xlabel("Pairs (%), 95% CI"); ax.set_title(title, fontsize=8.5)
        ax.set_xlim(left=0)
    axes[0].set_ylabel("Threshold (mmol/L)")
    axes[1].plot([], [], "o", color="black", label="MIMIC-IV"); axes[1].plot([], [], "s", color="#7f7f7f", label="SICdb")
    axes[1].legend(fontsize=7, loc="lower right", frameon=False)
    save(fig, "fig3_forest")
    (OUT / "bins_internal.json").write_text(json.dumps({"note": "internal only, not for sharing", "x_edges": (xe - 0.025).tolist(),
        "y_edges": (ye - 0.025).tolist(), "counts": {db: bins[db].astype(int).tolist() for db in bins}, "info": info}), encoding="utf-8")
    (OUT / "figure_notes.json").write_text(json.dumps(info, indent=1), encoding="utf-8")
    lines = [f"{sha(p)}  {p.name}" for p in sorted(OUT.iterdir()) if p.name != "SHA256SUMS.txt"]
    (OUT / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps(info))


if __name__ == "__main__":
    main()
