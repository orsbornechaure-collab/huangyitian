# Differences between the released files and the files used for the reported results

Each released file equals the internal file except for the exact substitutions below (nothing else changed). Substitutions marked "tool-participation wording removed" delete or neutralise internal notes on who drafted or reviewed a passage; they change no method, parameter or estimator.
Internal file SHA-256 values identify the versions used for the locked analysis run H04_20261111_AN_r1.

## `code/01_build/build_01_mimic_v1.py`

- internal file: `03_code/build_01_mimic_v1.py`
- internal SHA-256: a81c49be905085c8fbe90191af4d1c76244ccedc18cf3d13280067bf40b3dfca
- released SHA-256: da4a3ff53f1b85e940eec0443249a04e5a215cf9e06b54486751a37d66715de2
- substitutions (4):
  - tool-participation wording removed: (original wording not reproduced) -> `(local only)`
  - needed for the environment-variable paths below: `import math` -> `import math / import os`
  - local absolute path: (the authors' local absolute path; not reproduced) -> `ARCHIVE = Path(os.environ.get("H04_MIMIC_ZIP", "mimic-iv-3.1.zip"))  # public release: local path removed`
  - local absolute path: (the authors' local absolute path; not reproduced) -> `OUT_DIR = Path(os.environ.get("H04_DERIVED_DIR", "04_derived/H04_20261111_BUILD_r1"))  # public release: local path removed`

## `code/01_build/build_02_sicdb_v1.py`

- internal file: `03_code/build_02_sicdb_v1.py`
- internal SHA-256: e308d3358943e1c76a92ca5b05a51bb7e4d60568458910affb12e95ca06852ba
- released SHA-256: 0e8ce78015fc75a2b332b0375a2b4e0eb3776a1a500268ed0cba87d8f6c94abe
- substitutions (4):
  - tool-participation wording removed: (original wording not reproduced) -> `(local only)`
  - needed for the environment-variable paths below: `import math` -> `import math / import os`
  - local absolute path: (the authors' local absolute path; not reproduced) -> `ARCHIVE = Path(os.environ.get("H04_SICDB_ZIP", "salzburg-intensive-care-database-sicdb-a-freely-accessible-intensive-care-database-1.0.8.zip"))  # public release: local path removed`
  - local absolute path: (the authors' local absolute path; not reproduced) -> `OUT_DIR = Path(os.environ.get("H04_DERIVED_DIR", "04_derived/H04_20261111_BUILD_r1"))  # public release: local path removed`

## `code/02_analysis/an_01_main_v5.R`

- internal file: `03_code/an_01_main_v5.R`
- internal SHA-256: d2544dc2b3ac7e8d9792fa67ef62699bb494a1202e81ef952959e6b7981bcd61
- released SHA-256: ab80271147c56b3025b8864d9bb21dab206b6613824329a931091b035633f5b1
- substitutions (3):
  - tool-participation wording removed: (original wording not reproduced) -> `(review round 4 A-01)`
  - tool-participation wording removed: (original wording not reproduced) -> `written by a reviewer other than / #     the drafter, result VERIFIED`
  - local absolute path: (the authors' local absolute path; not reproduced) -> `PROJ <- Sys.getenv("H04_PROJECT_DIR", ".")  # public release: local path removed`

## `code/02_analysis/an_01_functions_v3.R`

- internal file: `03_code/an_01_functions_v3.R`
- internal SHA-256: 09bfacf28bc1923f814f47caa4f6b08de584d54139dcff0926491ace0ec7b694
- released SHA-256: 115e3f1fe2d02632e160c0f13425f698ec06f99639027d5d8486c14fd1024b81
- substitutions (5):
  - tool-participation wording removed: (original wording not reproduced) -> `consistency check of the drafter's transcription`
  - tool-participation wording removed: (original wording not reproduced) -> `written by a reviewer other than the drafter after`
  - drafting-tool name in approval pre-check guard replaced by placeholder (pre-check only; estimators unchanged): (original wording not reproduced) -> `grepl("<drafter>", tolower(cs$verifier), fixed = TRUE)`
  - local absolute path: (the authors' local absolute path; not reproduced) -> `PROJ <- Sys.getenv("H04_PROJECT_DIR", ".")  # public release: local path removed`
  - local absolute path (raw-data folder guard): (the authors' local absolute path; not reproduced) -> `under(d$path, Sys.getenv("H04_RAW_DATA_DIR", "raw_data"))`

## `code/03_figures/fig_01_figures_v3.py`

- internal file: `03_code/fig_01_figures_v3.py`
- internal SHA-256: 7f1072351b91dc2da2c6908e3cd5fa426662bce3c8c32b1afde3db87699e1211
- released SHA-256: 4791b94b55ce85b479a1baf4c461e44c7673cf88014d620e99cd609a17925d71
- substitutions (2):
  - needed for the environment-variable path below (file uses CRLF): `import json` -> `import json / import os`
  - local absolute path: (the authors' local absolute path; not reproduced) -> `ROOT = Path(os.environ.get("H04_PROJECT_DIR", "."))  # public release: local path removed`

## `protocol/H04_Protocol_SAP_v1.2_FROZEN_public_copy.md`

- internal file: `01_protocol/H04_Protocol_SAP_v1.2_冻结候选.md`
- internal SHA-256: e2be916f335acfc192f6de1b031299ab2d0101bd8b221a93792a7136267deae8
- released SHA-256: c9220b05acb56ab4fbcb394e09789e7eb98332892acfa6fff659e549186949a8
- substitutions (27):
  - tool-participation wording removed: (original wording not reproduced) -> `v1.2 按 G4 第二轮独立审核（内部审核报告，P0=1/P1=6/P2=3）修订`
  - tool-participation wording removed: (original wording not reproduced) -> `v1.1 按 G4 第一轮独立审核（内部审核报告，P0=1/P1=11/P2=2）修订，整改方案另存内部记录。`
  - tool-participation wording removed: (original wording not reproduced) -> `【G4 确认，起草者建议保留】`
  - tool-participation wording removed: (original wording not reproduced) -> `（三轮独立静态核查）`
  - tool-participation wording removed: (original wording not reproduced) -> `- **PhysioNet 2025-09-24 补充说明**：`
  - tool-participation wording removed: (original wording not reproduced) -> (line deleted)
  - tool-participation wording removed: (original wording not reproduced) -> (line deleted)
  - tool-participation wording removed: (original wording not reproduced) -> `由脚本处理。`
  - tool-participation wording removed: (original wording not reproduced) -> `## 22. 起草者意见`
  - tool-participation wording removed: (original wording not reproduced) -> `| v1.2 冻结候选 | 2026-11-11 | 按 G4 第二轮独立审核修订`
  - tool-participation wording removed: (original wording not reproduced) -> `| v1.1 冻结候选 | 2026-11-11 | 按 G4 第一轮独立审核修订`
  - tool-participation wording removed: (original wording not reproduced) -> `由起草者依直接收到的原话转录`
  - tool-participation wording removed: (original wording not reproduced) -> `由起草者以外的独立审核者在比对`
  - tool-participation wording removed: (original wording not reproduced) -> `verifier（不得为起草者）`
  - tool-participation wording removed: (original wording not reproduced) -> `(a) 只是起草者的转录`
  - tool-participation wording removed: (original wording not reproduced) -> `核对者为起草者、`
  - tool-participation wording removed: (original wording not reproduced) -> `独立复核由另一审核者在 G6 进行`
  - tool-participation wording removed: (original wording not reproduced) -> `不能由起草者默认豁免`
  - local absolute path: (the authors' local absolute path; not reproduced) -> `文件夹 `<project folder>``
  - local absolute path: (the authors' local absolute path; not reproduced) -> ``<raw data folder>\mimic-iv-3.1.zip``
  - local absolute path: (the authors' local absolute path; not reproduced) -> ``<raw data folder>\salzburg-intensive-care-database-sicdb-a-freely-accessible-intensive-care-database-1.0.8.zip``
  - local absolute path: (the authors' local absolute path; not reproduced) -> `R 包装在 <local R library>`
  - local absolute path: (the authors' local absolute path; not reproduced) -> ``<project folder>/05_results/<run_id>``
  - unpublished exact subset count (half-widths would reveal it): (table row with the original values; not reproduced) -> `| MIMIC 实验室钾 ≥6.0 | [withheld in public copy] | [withheld in public copy] | [withheld in public copy] |`
  - unpublished exact subset count (half-widths would reveal it): (table row with the original values; not reproduced) -> `| MIMIC 实验室钾 <3.0 | [withheld in public copy] | [withheld in public copy] | [withheld in public copy] |`
  - unpublished exact subset count (half-widths would reveal it): (table row with the original values; not reproduced) -> `| SICdb 中心实验室钾 ≥6.0 | [withheld in public copy] | [withheld in public copy] | [withheld in public copy] |`
  - unpublished exact subset count (half-widths would reveal it): (table row with the original values; not reproduced) -> `| SICdb 中心实验室钾 <3.0 | [withheld in public copy] | [withheld in public copy] | [withheld in public copy] |`

## `protocol/BUILD_r1_spec.md`

- internal file: `01_protocol/BUILD_r1_规格.md`
- internal SHA-256: b100288d8ca9cc346767a169a0302e65bbdf1d99e8d85a8d94498b11ef2b82e3
- released SHA-256: 7e68e15f7e71d63c99e297561c424c21122deeb63af5af771e17db3f09f43f03
- substitutions (1):
  - tool-participation wording removed: (original wording not reproduced) -> `（不进 git，不外传）`

## `protocol/FIG_r1_spec.md`

- internal file: `01_protocol/FIG_r1_规格.md`
- internal SHA-256: 39ee2156c735704c82cb1b87dda2ae7501d3194e49ecd7d0459c12ea6bdac26a
- released SHA-256: 39ee2156c735704c82cb1b87dda2ae7501d3194e49ecd7d0459c12ea6bdac26a
- substitutions: none (byte-identical)

## `code/04_posthoc/phx_01_posthoc_v1.R`

- internal file: `03_code/phx_01_posthoc_v1.R`
- internal SHA-256: bbf326008b7c381fa91d6679bb94e5c8c60b3ffcd8adab993dc6062d4252be6b
- released SHA-256: bbf326008b7c381fa91d6679bb94e5c8c60b3ffcd8adab993dc6062d4252be6b
- substitutions: none (byte-identical)

## `protocol/PHX_r1_spec.md`

- internal file: `01_protocol/PHX_r1_规格.md`
- internal SHA-256: 1579eded0c5210dbe92096d2180ba6323668660ecb1c681e86945ea646acf118
- released SHA-256: 5f499e23bd282258d619fbe7d3d2e9bb6e0eae9ef08a15379326b3f2647a6f36
- substitutions (4):
  - tool-participation wording removed: (original wording not reproduced) -> `- 依据：负责人书面授权（内部决策记录，2026-11-13）。`
  - tool-participation wording removed: (original wording not reproduced) -> `。`
  - local absolute path: (the authors' local absolute path; not reproduced) -> `（<local R installation>）`
  - tool-participation wording removed: (original wording not reproduced) -> `结果写入稿件前先过独立只读复核（与稿件一起）；`

## `code/02_analysis/config_AN_r1_historical.json`

- new file: the formal-run configuration with local absolute paths replaced by paths relative to the project folder; all hashes and parameters unchanged (historical record, not an adapted configuration).

## Note on the SAP file name

The internal file name keeps the words "冻结候选" (freeze candidate) and its header says "未冻结"; the file was frozen unchanged at gate G4 (2026-11-11) with SHA-256 e2be916f335acfc192f6de1b031299ab2d0101bd8b221a93792a7136267deae8, as recorded in the authors' freeze record. The public copy is that file with the substitutions above.

## `code/04_posthoc/config_PHX_r1_historical.json`

- new file: the configuration of the post hoc run H04_20261113_PHX_r1 with local absolute paths replaced by paths relative to the project folder; hashes and parameters unchanged.
