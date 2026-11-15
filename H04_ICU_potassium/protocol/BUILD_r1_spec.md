# H04 分析数据集构建规格：H04_20261111_BUILD_r1

- 依据：SAP v0.7（SHA-256 28daf4157558bad8c69499dda950a0d800128cdc3320b3f0f0f6c9c4ba5ea460）第 5、6 节；G2 批准的定义（`06_audit\2026-11-10_H04_变量审计\关键变量定义建议_v0.3.md`）。
- 授权：G2 审批单“批准后我只做”第 1 项（负责人 2026-11-11 05:48 EST）。
- 性质：生成配对层面的分析数据集，只留本机 `04_derived\H04_20261111_BUILD_r1\`（不进 git，不外传）。配对表中两种钾值在同一行（这是配对表的结构），但**脚本不计算、不输出两种钾的差值、相关、交叉表或不一致率**。
- 脚本：
  - `03_code\build_01_mimic_v1.py <run_dir> <本规格路径> <本规格 SHA-256>`
  - `03_code\build_02_sicdb_v1.py <run_dir> <本规格路径> <本规格 SHA-256>`
  - 输出数据：`04_derived\H04_20261111_BUILD_r1\{mimic,sicdb}_pairs_w{5,10,30}.csv.gz`
  - 运行记录：`05_results\H04_20261111_BUILD_r1_{mimic,sicdb}\`（summary.json、run.log、environment.json、input_files.json、code、SHA256SUMS.txt，并记录各数据文件的 SHA-256）
- 输入：同 G2AUD（两库压缩包，运行前核对 SHA-256）。

## 1. 配对（与 FEAS 规则相同）

- 5、10、30 分钟窗各自独立贪心配对（60 分钟不构建）。
- 运行内断言：各窗口的配对数、ICU 住院（病例）数、患者数必须与 FEAS 的精确值一致：
  - MIMIC：5 分钟 14,147 / 5,171 / 4,883；10 分钟 23,357 / 9,385 / 8,797；30 分钟 44,328 / 15,320 / 14,017
  - SICdb：5 分钟 4,879 / 3,857 / 3,602；10 分钟 11,211 / 7,231 / 6,428；30 分钟 22,921 / 9,840 / 8,482
  - 不一致即失败退出，不写数据文件（这是 G3 的对账要求；summary 只输出“一致”）。

## 2. 列（MIMIC）

pair_id；subject_id；hadm_id；stay_id；window_min；lab_charttime；gas_charttime；signed_minutes（血气 − 实验室，分钟）；lab_k；gas_k；lab_storetime；gas_storetime；lab_hadm_missing；gas_hadm_missing；gas_specimen_id；specimen_type_raw；specimen_class（ART / NONART / UNKNOWN）；ph；wbc；wbc_source（51301 / 51300 / none）；wbc_minutes；platelet、platelet_minutes；creatinine、creatinine_minutes；glucose、glucose_minutes（协变量时间差为“协变量时间 − 血气钾时间”，分钟）；icu_type（first_careunit）；age（推算）；anchor_age_is_91；anchor_year_group；hemolysis_lab、hemolysis_gas（comments 含 HEMOLY，0/1）。

## 3. 列（SICdb）

pair_id；patient_id；case_id；window_min；lab_offset；gas_offset；signed_minutes；lab_k；gas_k；specimen_class（ART / UNKNOWN）；ph；wbc；wbc_minutes；platelet、platelet_minutes；creatinine、creatinine_minutes；glucose、glucose_source（348 / 656 / none）、glucose_minutes；hospital_unit_last；age_recorded。

## 4. 取值规则

全部按关键变量定义建议 v0.3 第 1–16 行。允许单位：
- MIMIC：白细胞、血小板 K/uL；肌酐、葡萄糖 mg/dL；pH units。
- SICdb：按字典单位，不换算。

## 5. summary（只出计数，取整到 10，白名单校验）

- 每库每窗口：断言一致（布尔值）；各列缺失计数；协变量单位不符计数。
- 不输出任何钾值分布（留给 G3 QC）。
- 输出数据文件的 SHA-256。
