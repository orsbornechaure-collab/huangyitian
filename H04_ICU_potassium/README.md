# H04: blood gas versus central laboratory potassium in the ICU (MIMIC-IV, SICdb)

Analysis code, study protocol / statistical analysis plan (SAP) and processing specifications for the study comparing
blood gas (whole-blood) potassium with central laboratory potassium and threshold reclassification in intensive care
(MIMIC-IV 3.1, primary; SICdb 1.0.8, supplementary).

**This folder contains no data of any kind** (no patient-level, pair-level or aggregate data files).

## Data access

- MIMIC-IV 3.1 and SICdb 1.0.8 are distributed by PhysioNet (https://physionet.org/) under credentialed-access data use
  agreements. Researchers must complete the required credentialing and sign the data use agreements themselves; the
  authors are not permitted to share the data or any derived row-level files.
- The scripts read the original PhysioNet zip archives unchanged and check their SHA-256 before use:
  - `mimic-iv-3.1.zip`: 0dd448e341f489483194daafd884607d6f194648c6bf54eed56d1e2cd2af9e09
  - `salzburg-intensive-care-database-sicdb-a-freely-accessible-intensive-care-database-1.0.8.zip`:
    5332178a99dc2cf2a23c1cf7de13daaac5c488903114676a1002847f53781739

## Contents

| Path | What it is |
|---|---|
| `protocol/H04_Protocol_SAP_v1.2_FROZEN_public_copy.md` | Study protocol and SAP v1.2 as frozen before any outcome analysis (in Chinese). Public copy: local paths and four unpublished exact subset counts withheld and some internal process notes removed (see `RELEASE_CHANGES.md`). |
| `protocol/BUILD_r1_spec.md`, `protocol/FIG_r1_spec.md` | Specifications for the dataset-building and figure steps (in Chinese). |
| `code/01_build/build_01_mimic_v1.py`, `build_02_sicdb_v1.py` | Build the pair-level analysis files (5-, 10- and 30-minute windows) from the PhysioNet archives. |
| `code/02_analysis/an_01_main_v5.R`, `an_01_functions_v3.R` | Formal analysis as specified in the frozen SAP (agreement, limits of agreement, threshold reclassification, kappa, cluster bootstrap, Passing-Bablok, association models). |
| `code/02_analysis/config_AN_r1_historical.json` | Configuration used for the formal run (historical record), paths made relative to the project folder. |
| `code/03_figures/fig_01_figures_v3.py` | Publication figures (binned Bland-Altman plot; no individual points). |
| `code/04_posthoc/phx_01_posthoc_v1.R`, `config_PHX_r1_historical.json` | Post hoc exploratory analyses run after the analysis was locked (order of result storage, extreme differences); specification in `protocol/PHX_r1_spec.md` (in Chinese). |
| `RELEASE_CHANGES.md` | Every difference between these files and the versions used for the reported results. |
| `MANIFEST_SHA256.txt` | SHA-256 of every file in this folder. |

## Status of this release: historical code, local adaptation required

These are the scripts and the configuration as used for the reported results (only local paths, comment wording and
one placeholder in an approval pre-check replaced; every change is listed in `RELEASE_CHANGES.md`). **They are not a ready-to-run reproduction package.** They document what was run; re-use on
another computer requires local adaptation and your own PhysioNet data access.

How the scripts were run by the authors (in this order):

1. Build the pair files (row-level output stays on the local machine and must never be shared):
   `python -I build_01_mimic_v1.py <run_dir> <BUILD_r1 spec> <sha256 of the spec>` and the same for `build_02_sicdb_v1.py`.
   Paths are now read from the environment variables `H04_MIMIC_ZIP`, `H04_SICDB_ZIP` and `H04_DERIVED_DIR`.
   Each build checks the archive SHA-256 and that the pair, stay/case and patient counts equal the values printed in
   Figure 1.
2. Formal analysis: `Rscript an_01_main_v5.R <config.json>`; the configuration used is
   `code/02_analysis/config_AN_r1_historical.json`. Its relative paths are resolved by R against the current working
   directory, so R must be started in the project root (the formal run used absolute paths). `H04_PROJECT_DIR` is used only by the internal guard paths and
   does not change the working directory, so it must point to the same folder (or use explicit paths when adapting).
3. Figures: `python -I fig_01_figures_v3.py <out_dir> <FIG_r1 spec> <sha256 of the spec>`.
4. Post hoc exploratory analyses (labelled post hoc in the manuscript): `Rscript phx_01_posthoc_v1.R <config.json>`
   (configuration used: `code/04_posthoc/config_PHX_r1_historical.json`). The script reads the 10-minute MIMIC-IV pair
   file, the locked analysis output (`results.json`) and the disclosure-controlled summary of the main analysis, first
   reproduces three locked primary estimates and their 95% confidence intervals within the prespecified absolute tolerance
   of 1e-12 (largest observed difference 5e-16; storage-time quartiles identical) and stops otherwise, and writes only
   aggregate output. It uses the
   Windows `certutil` command for SHA-256 and the R package jsonlite (the specification `protocol/PHX_r1_spec.md`, kept as
   run, says "base R only"; that statement omits jsonlite). The locked output and the summary are not included,
   so the script cannot run elsewhere without adaptation.

What has to be adapted before the analysis script can run elsewhere (each of these stops the script by design):

- **SAP check.** `an_01_main_v5.R` stops unless the configured SAP file exists with the configured SHA-256. The historical
  configuration points to the internal SAP file; the public copy in `protocol/` has a different SHA-256 because local
  paths, four counts and internal process notes were removed. A local configuration must name an existing file and its own hash.
- **Approval pre-checks (real mode).** Before any computation, real mode reads the internal approval record
  (`00_governance/G4_运行授权.json`) and an independent countersignature, and checks the script, SAP and input hashes,
  the R and package versions, run_id and output folder against them (`real_mode_problem()` and the block in
  `an_01_main_v5.R` that prepares its inputs). None of these records are released. Re-use requires removing or
  replacing this whole pre-check branch; do not create imitation approval records.
- **Synthetic mode** requires the synthetic-data generator and manifest used for testing, which are not included.
- **Inputs and outputs.** The input hashes in the configuration are those of the original pair files; files you build
  may differ (for example in compression metadata). The output folder must not exist and, in the historical guards,
  must lie under `05_results/<run_id>`.
- **Figures.** `fig_01_figures_v3.py` also reads a disclosure-controlled summary (`publish_numbers.json`) produced by
  internal steps that operate on aggregate output only; neither the summary nor those steps are included.

Other notes:
- The SAP and the scripts refer to internal file names (approval records, audit reports, earlier versions) that are
  not part of this release.
- Counts in the analysis output are rounded to 10 ("<10" for 1-9). Further disclosure control was applied before
  publication (merging or suppressing some cells; see the notes to Supplementary Material 1).
- The estimators are in `an_01_functions_v3.R`; adapting the pre-checks described above does not change them.

## Software used for the reported results

- R 4.6.1 (Windows x86_64): lme4 2.0-6, geepack 1.3.13, mcr 1.3.3.1, robslopes 1.1.4, Matrix 1.7-5, jsonlite 2.0.0,
  digest 0.6.39; base packages splines, parallel, stats. The formal run used n_boot = 2000, n_boot_paba = 1000,
  seed = 20261110.
- Python 3.11.15 (Windows x86_64): standard library for the build scripts; numpy 2.4.6 and matplotlib 3.11.2 for the
  figures.
