# H04 formal analysis, main script v5 (SAP v1.2 FROZEN; freeze record erratum R1). Functions: an_01_functions_v3.R (same folder).
# v5 = v4 + jsonlite/digest load failure exits 2 (review round 4 A-01). v4 changes vs v3 (pre-checks only; estimators
# and guards unchanged): scalar type checks for every config key;
# pair_id must be 1-9 digits and convert to a non-NA integer; package loading / version reading errors exit 2.
# Usage: Rscript an_01_main_v5.R <config.json>
# config keys (all required): run_id, mode ("real"|"synthetic"), out_dir, sap{path,sha256},
#   data{mimic|sicdb{"5","10","30"}{path,sha256}}, n_boot, n_boot_paba, seed.
# REAL mode requires (checked by real_mode_problem() in the functions file, all before any write):
#   - 00_governance/G4_运行授权.json with all fields (project H04, gate G4, decision APPROVED, owner_words,
#     owner_message_time, approval_record{path,sha256} inside 00_governance whose text contains owner_words verbatim,
#     sap_frozen{path,sha256} equal to the config, scripts{main,functions} hashes, run_id, n_boot/n_boot_paba/seed);
#   - an independent countersignature 06_audit/G4_运行授权_独立核对/核对结果.json written by a reviewer other than
#     the drafter, result VERIFIED, binding the exact hashes of the authorization file and the approval record;
#   - frozen inputs, parameters 2000/1000/20261110, out_dir = 05_results/<run_id>, pinned R and package versions.
# SYNTHETIC mode (tests only): all inputs in one h04_syn_* directory listed in its synthetic_manifest.json from the
#   generator an_test_04_synthetic_v3.py; out_dir inside that directory; run_id starts with SYNTHETIC.
# Every input is read and validated before the first write. Any failure exits 2 with "STOP: <reason>".
# Outputs (aggregate only): results.json, qq_<db>_*.png (local diagnostics only, never for sharing), run.log,
#   session_info.txt, code/, SHA256SUMS.txt. Counts rounded to 10 ("<10" for 1-9); proportions with numerator 1-9 suppressed.

boot_ok <- tryCatch({ suppressPackageStartupMessages({ library(jsonlite); library(digest) }); TRUE }, error = function(e) FALSE)
if (!boot_ok) { cat("STOP: required package jsonlite or digest failed to load 
"); quit(status = 2) }
PROJ <- Sys.getenv("H04_PROJECT_DIR", ".")  # public release: local path removed
early_stop <- function(r) { cat("STOP:", r, "\n"); quit(status = 2) }
sha_file <- function(p) digest(file = p, algo = "sha256")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) early_stop("usage: an_01_main_v5.R <config.json>")
cfg <- tryCatch(fromJSON(args[1], simplifyVector = FALSE), error = function(e) NULL)
if (!is.list(cfg)) early_stop("config is not valid JSON")
need <- c("run_id", "mode", "out_dir", "sap", "data", "n_boot", "n_boot_paba", "seed")
if (!all(need %in% names(cfg))) early_stop(paste("config missing:", paste(setdiff(need, names(cfg)), collapse = ",")))
str1 <- function(x) is.character(x) && length(x) == 1 && !is.na(x) && nzchar(x)
for (k in c("run_id", "mode", "out_dir")) if (!str1(cfg[[k]])) early_stop(paste("config key must be a non-empty string:", k))
if (!is.list(cfg$sap) || !str1(cfg$sap$path) || !str1(cfg$sap$sha256)) early_stop("config sap must have string path and sha256")
if (!is.list(cfg$data)) early_stop("config data must be an object")
for (db in names(cfg$data)) { if (!is.list(cfg$data[[db]])) early_stop(paste("config data entry must be an object:", db))
  for (w in names(cfg$data[[db]])) { d <- cfg$data[[db]][[w]]
    if (!is.list(d) || !str1(d$path) || !str1(d$sha256)) early_stop(paste("config data item must have string path and sha256:", db, w)) } }
SCRIPT <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]), winslash = "/")
FUNS <- file.path(dirname(SCRIPT), "an_01_functions_v3.R")
if (!file.exists(FUNS)) early_stop("functions file missing")
src_ok <- tryCatch({ source(FUNS); TRUE }, error = function(e) FALSE)  # defines functions and guard constants only; writes nothing
if (!src_ok) early_stop("functions file failed to load")
OUT <- cfg$out_dir; MODE <- cfg$mode
if (dir.exists(OUT) || file.exists(OUT)) early_stop("out_dir exists")
if (!identical(sort(names(cfg$data)), c("mimic", "sicdb"))) early_stop("data must contain exactly mimic and sicdb")
for (db in c("mimic", "sicdb")) if (!identical(sort(names(cfg$data[[db]])), c("10", "30", "5"))) early_stop(paste("windows must be 5,10,30 for", db))
for (k in c("n_boot", "n_boot_paba", "seed")) if (!is.numeric(cfg[[k]]) || length(cfg[[k]]) != 1 || cfg[[k]] < 1 || cfg[[k]] != round(cfg[[k]])) early_stop(paste("bad", k))
if (!file.exists(cfg$sap$path) || sha_file(cfg$sap$path) != tolower(cfg$sap$sha256)) early_stop("SAP sha256 mismatch")
for (db in c("mimic", "sicdb")) for (w in c("5", "10", "30")) {
  d <- cfg$data[[db]][[w]]
  if (is.null(d$path) || !file.exists(d$path) || sha_file(d$path) != tolower(d$sha256)) early_stop(paste("data sha256 mismatch:", db, w))
}
readj <- function(p) if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL) else NULL
if (identical(MODE, "real")) {
  au <- readj(AUTH_PATH)
  if (!is.list(au)) early_stop("real mode: authorization file 00_governance/G4_运行授权.json missing or invalid")
  ap <- if (is.list(au$approval_record) && s1(au$approval_record$path)) file.path(PROJ, au$approval_record$path) else ""
  ev <- list(approval_sha_actual = if (nzchar(ap) && file.exists(ap)) sha_file(ap) else NA_character_,
             approval_text = if (nzchar(ap) && file.exists(ap)) paste(readLines(ap, encoding = "UTF-8", warn = FALSE), collapse = "\n") else NA_character_,
             auth_sha_actual = sha_file(AUTH_PATH), sha_main = sha_file(SCRIPT), sha_funs = sha_file(FUNS))
  pv <- lapply(setdiff(names(PKG), "R"), function(p) tryCatch(as.character(packageVersion(p)), error = function(e) "missing")); names(pv) <- setdiff(names(PKG), "R")
  pv$R <- paste(R.version$major, R.version$minor, sep = ".")
  why <- real_mode_problem(au, readj(COUNTERSIGN_PATH), cfg, ev, pv)
  if (!is.null(why)) early_stop(why)
} else if (identical(MODE, "synthetic")) {
  mf <- readj(file.path(dirname(cfg$data$mimic[["10"]]$path), "synthetic_manifest.json"))
  why <- synthetic_mode_problem(cfg, mf); if (!is.null(why)) early_stop(why)
} else early_stop("mode must be real or synthetic")

lib_ok <- tryCatch({ suppressPackageStartupMessages({ library(lme4); library(geepack); library(mcr); library(splines) }); TRUE },
                   error = function(e) FALSE)
if (!lib_ok) early_stop("required package failed to load")

HEADER <- list(
  mimic = c("pair_id", "subject_id", "hadm_id", "stay_id", "window_min", "lab_charttime", "gas_charttime",
            "signed_minutes", "lab_k", "gas_k", "lab_storetime", "gas_storetime", "lab_hadm_missing",
            "gas_hadm_missing", "gas_specimen_id", "specimen_type_raw", "specimen_class", "ph", "wbc", "wbc_source",
            "wbc_minutes", "platelet", "platelet_minutes", "creatinine", "creatinine_minutes", "glucose",
            "glucose_minutes", "icu_type", "age", "anchor_age_is_91", "anchor_year_group", "hemolysis_lab",
            "hemolysis_gas"),
  sicdb = c("pair_id", "patient_id", "case_id", "window_min", "lab_offset", "gas_offset", "signed_minutes", "lab_k",
            "gas_k", "specimen_class", "ph", "wbc", "wbc_minutes", "platelet", "platelet_minutes", "creatinine",
            "creatinine_minutes", "glucose", "glucose_source", "glucose_minutes", "hospital_unit_last", "age_recorded"))

read_pairs <- function(db, w) {  # returns a data.frame or a character error message (no writing)
  p <- cfg$data[[db]][[w]]$path
  x <- read.csv(gzfile(p), colClasses = "character", na.strings = character(0), check.names = FALSE)
  if (!identical(names(x), HEADER[[db]])) return(paste("header mismatch", db, w))
  num <- function(v) { v[v == ""] <- NA; suppressWarnings(as.numeric(v)) }
  out <- data.frame(pair_id = suppressWarnings(as.integer(x$pair_id)), lab = num(x$lab_k), gas = num(x$gas_k),
                    smin = num(x$signed_minutes), spec = x$specimen_class, ph = num(x$ph), wbc = num(x$wbc),
                    plt = num(x$platelet), cre = num(x$creatinine), glu = num(x$glucose), stringsAsFactors = FALSE)
  if (db == "mimic") {
    tsx <- function(v) { v[v == ""] <- NA; as.numeric(as.POSIXct(v, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")) }
    out$pid <- x$subject_id; out$cid <- x$stay_id; out$icu <- x$icu_type
    out$t_gas <- tsx(x$gas_charttime); out$t_lab <- tsx(x$lab_charttime)
    out$st_gas <- tsx(x$gas_storetime); out$st_lab <- tsx(x$lab_storetime)
    out$hadm_miss <- x$lab_hadm_missing == "1" | x$gas_hadm_missing == "1"
    out$hemo <- x$hemolysis_lab == "1" | x$hemolysis_gas == "1"
  } else {
    out$pid <- x$patient_id; out$cid <- x$case_id; out$icu <- NA_character_
    out$t_gas <- num(x$gas_offset); out$t_lab <- num(x$lab_offset); out$case_num <- num(x$case_id)
  }
  if (nrow(out) == 0) return(paste("empty input", db, w))
  flags01 <- if (db == "mimic") c(x$lab_hadm_missing, x$gas_hadm_missing, x$hemolysis_lab, x$hemolysis_gas) else character(0)
  spec_ok <- if (db == "mimic") c("ART", "NONART", "UNKNOWN") else c("ART", "UNKNOWN")
  bad <- !grepl("^[0-9]{1,9}$", x$pair_id) | is.na(out$pair_id) | !is.finite(out$lab) | !is.finite(out$gas) | out$lab <= 0 | out$gas <= 0 |
    !nzchar(out$pid) | !nzchar(out$cid) | !is.finite(out$t_gas) | !is.finite(out$t_lab) | x$window_min != w |
    !is.finite(out$smin) | abs(out$smin) > as.numeric(w) + 1e-9 | !(out$spec %in% spec_ok)
  if (any(bad)) return(paste("invalid key fields", db, w))
  if (anyDuplicated(out$pair_id)) return(paste("duplicate pair_id", db, w))
  if (length(flags01) && !all(flags01 %in% c("0", "1"))) return(paste("flag not 0/1", db, w))
  if (db == "mimic" && !all(x$icu_type != "")) return(paste("icu_type empty", db, w))
  out
}
DATA <- list()
for (db in c("mimic", "sicdb")) { DATA[[db]] <- list(); for (w in c("5", "10", "30")) {
  r <- tryCatch(read_pairs(db, w), error = function(e) paste("input read error", db, w, conditionMessage(e)))
  if (is.character(r)) early_stop(r); DATA[[db]][[w]] <- r } }

# ---------------- all checks passed: first write ----------------
dir.create(OUT, recursive = TRUE)
LOGF <- file(file.path(OUT, "run.log"), open = "wt", encoding = "UTF-8")
logm <- function(...) { s <- paste0(format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), " ", paste0(..., collapse = ""))
  cat(s, "\n"); writeLines(s, LOGF); flush(LOGF) }
write_sums <- function() {
  fs <- list.files(OUT, recursive = TRUE, full.names = TRUE); fs <- fs[basename(fs) != "SHA256SUMS.txt"]
  rel <- substring(normalizePath(fs, winslash = "/"), nchar(normalizePath(OUT, winslash = "/")) + 2)
  writeLines(paste0(vapply(fs, sha_file, ""), "  ", rel), file.path(OUT, "SHA256SUMS.txt"))
}
stopx <- function(reason) {
  logm("STOP: ", reason)
  writeLines(toJSON(list(run_id = cfg$run_id, STOP = reason), auto_unbox = TRUE), file.path(OUT, "STOP.json"))
  close(LOGF); write_sums(); quit(status = 2)
}
dir.create(file.path(OUT, "code"))
invisible(file.copy(c(SCRIPT, FUNS), file.path(OUT, "code")))
invisible(file.copy(args[1], file.path(OUT, "code", "config.json")))
B <- as.integer(cfg$n_boot); BP <- as.integer(cfg$n_boot_paba); SEED <- as.integer(cfg$seed)
RNGkind("Mersenne-Twister", "Inversion", "Rejection")
logm("start run_id=", cfg$run_id, " mode=", MODE, "; all pre-checks passed")

run_set <- function(name, dat, models = FALSE, s6 = FALSE, paba = FALSE) {
  logm("set ", name, " start")
  out <- list(n_pairs = r10(nrow(dat)), n_patients = r10(length(unique(dat$pid))))
  if (nrow(dat) == 0 || length(unique(dat$pid)) < 2) { out$status <- "not_estimable_empty_or_single_patient"; return(out) }
  out$crosstab3 <- crosstab3(dat$lab, dat$gas)
  pt <- core_est(dat$lab, dat$gas, "sample"); ptv <- sapply(pt, `[`, 1)
  eval_pts <- numeric(0)
  if (models) {
    m <- (dat$gas + dat$lab) / 2; lo <- q7(m, 0.01); hi <- q7(m, 0.99)
    eval_pts <- c(3.0, 3.5, 4.0, 5.0, 5.5, 6.0); eval_pts <- eval_pts[eval_pts >= lo & eval_pts <= hi]
    out$loa_reg_points_in_range <- eval_pts
    me <- model_est(dat$lab, dat$gas, dat$pid, eval_pts); out$model_status_sample <- attr(me, "status"); ptv <- c(ptv, unlist(me))
  }
  if (s6) ptv <- c(ptv, unlist(s6_est(dat$lab, dat$gas, dat$pid)))
  bf <- function(dd, np) {
    v <- sapply(core_est(dd$lab, dd$gas, "boot"), `[`, 1)
    if (models) v <- c(v, unlist(model_est(dd$lab, dd$gas, np, eval_pts)))
    if (s6) v <- c(v, unlist(s6_est(dd$lab, dd$gas, np)))
    v
  }
  bm <- cluster_boot(dat, bf, B, SEED)
  est <- list()
  for (k in names(ptv)) {
    e <- ci_from(unname(ptv[k]), bm[, k])
    if (!is.null(pt[[k]]) && !is.na(pt[[k]][2])) {
      e$numerator <- r10(pt[[k]][2]); e$denominator <- r10(pt[[k]][3])
      if (pt[[k]][2] >= 1 && pt[[k]][2] <= 9) { e$est <- NA; e$lo <- NA; e$hi <- NA; e$ci <- "suppressed_numerator_lt10" }
    }
    est[[k]] <- e
  }
  out$estimates <- est
  if (paba) out$passing_bablok <- run_paba(dat$lab, dat$gas, BP, SEED)
  logm("set ", name, " done")
  out
}

results <- list(run_id = cfg$run_id, mode = MODE, n_boot = B, n_boot_paba = BP, seed = SEED,
                packages = list(R = R.version.string, lme4 = as.character(packageVersion("lme4")),
                                geepack = as.character(packageVersion("geepack")), mcr = as.character(packageVersion("mcr"))))
main <- function() {
  for (db in c("mimic", "sicdb")) {
    d10 <- DATA[[db]][["10"]]; sets <- list()
    sets$P <- run_set("P", d10, models = TRUE, s6 = TRUE)
    sets$S1 <- run_set("S1", d10[d10$spec == "ART", ])
    o <- if (db == "mimic") order(d10$pid, d10$t_gas, d10$t_lab, d10$pair_id) else order(d10$pid, d10$case_num, d10$t_gas, d10$t_lab, d10$pair_id)
    sets$S2 <- run_set("S2", d10[o, ][!duplicated(d10$pid[o]), ], paba = TRUE)
    sets$S3_w5 <- run_set("S3_w5", DATA[[db]][["5"]]); sets$S3_w30 <- run_set("S3_w30", DATA[[db]][["30"]])
    if (db == "mimic") {
      sets$S5 <- run_set("S5", d10[!d10$hadm_miss, ]); sets$S9 <- run_set("S9", d10[!d10$hemo, ])
      lead <- (d10$st_lab - d10$st_gas) / 60; ok <- is.finite(lead)
      results$storetime_order_mimic <<- list(gas_first = r10(sum(lead[ok] > 0)), lab_first = r10(sum(lead[ok] < 0)),
        same = r10(sum(lead[ok] == 0)), missing = r10(sum(!ok)),
        lead_minutes_q25_q50_q75 = if (sum(ok) >= 100) q7(lead[ok], c(0.25, 0.5, 0.75)) else "n_below_100")
    }
    logm("associations ", db); sets$associations <- assoc(d10, db)
    dd <- data.frame(d = d10$gas - d10$lab, m = (d10$gas + d10$lab) / 2, pid = factor(d10$pid))
    png(file.path(OUT, paste0("qq_", db, "_diff.png")), 800, 800); qqnorm(dd$d); qqline(dd$d); dev.off()
    fa <- fit_mixed(d ~ 1 + (1 | pid), dd); fc <- fit_mixed(d ~ m + (1 | pid), dd)
    if (!is.null(fa$fit)) { png(file.path(OUT, paste0("qq_", db, "_resid_a.png")), 800, 800); qqnorm(resid(fa$fit)); qqline(resid(fa$fit)); dev.off() }
    if (!is.null(fc$fit)) { png(file.path(OUT, paste0("qq_", db, "_resid_c.png")), 800, 800); qqnorm(resid(fc$fit)); qqline(resid(fc$fit)); dev.off() }
    results[[db]] <<- sets; logm(db, " done")
  }
}
tryCatch(main(), error = function(e) stopx(paste("unhandled error:", conditionMessage(e))))
writeLines(toJSON(results, auto_unbox = TRUE, digits = NA, na = "null", pretty = TRUE), file.path(OUT, "results.json"))
writeLines(capture.output(sessionInfo()), file.path(OUT, "session_info.txt"))
logm("done"); close(LOGF); write_sums()
