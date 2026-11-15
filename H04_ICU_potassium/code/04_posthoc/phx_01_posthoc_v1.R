# H04 post hoc exploratory analysis PHX_r1 (MIMIC-IV only). Spec: 01_protocol/PHX_r1_规格.md (written before the run).
# Reads the locked BUILD_r1 10-minute pair file (read-only) and the locked AN_r1 / SHARE_r5 summaries.
# Writes only aggregate outputs: results_r10.json (internal, counts rounded), publish_numbers.json, verification.md.
# Usage: Rscript phx_01_posthoc_v1.R <config.json>
options(warn = 1, stringsAsFactors = FALSE)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) stop("usage: Rscript phx_01_posthoc_v1.R <config.json>")
CFG_PATH <- normalizePath(args[1], winslash = "/", mustWork = TRUE)
SCRIPT <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]), winslash = "/")

sha_file <- function(p) {
  out <- system2("certutil", c("-hashfile", shQuote(normalizePath(p, winslash = "\\")), "SHA256"), stdout = TRUE)
  tolower(gsub("[^0-9a-fA-F]", "", out[2]))
}
# minimal JSON reader/writer via base R is impractical; use jsonlite if present, else stop.
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite required")
readj <- function(p) jsonlite::fromJSON(p, simplifyVector = FALSE)
cfg <- readj(CFG_PATH)
OUT <- cfg$out_dir
if (dir.exists(OUT)) stop("output directory already exists; never overwrite")
if (sha_file(cfg$spec$path) != tolower(cfg$spec$sha256)) stop("spec sha256 mismatch")
TEST <- isTRUE(cfg$test_mode)  # synthetic-data test only: skips input hash, size and reproduction/anchor assertions
if (TEST) cat("TEST MODE (synthetic data)
")
if (!TEST && sha_file(cfg$input$mimic_w10$path) != tolower(cfg$input$mimic_w10$sha256)) stop("input sha256 mismatch")
if (sha_file(cfg$locked$results$path) != tolower(cfg$locked$results$sha256)) stop("locked results sha256 mismatch")
if (sha_file(cfg$locked$share_r5$path) != tolower(cfg$locked$share_r5$sha256)) stop("SHARE_r5 sha256 mismatch")
if (!identical(as.numeric(cfg$seed), 20261110) || !identical(as.numeric(cfg$B), 2000)) stop("seed/B must be 20261110/2000")
LOCK <- readj(cfg$locked$results$path); PUB <- readj(cfg$locked$share_r5$path)

# ---------------- read pairs (same validity rules as an_01_main_v5.R read_pairs, MIMIC 10 min) ----------------
HEADER <- c("pair_id", "subject_id", "hadm_id", "stay_id", "window_min", "lab_charttime", "gas_charttime",
            "signed_minutes", "lab_k", "gas_k", "lab_storetime", "gas_storetime", "lab_hadm_missing",
            "gas_hadm_missing", "gas_specimen_id", "specimen_type_raw", "specimen_class", "ph", "wbc", "wbc_source",
            "wbc_minutes", "platelet", "platelet_minutes", "creatinine", "creatinine_minutes", "glucose",
            "glucose_minutes", "icu_type", "age", "anchor_age_is_91", "anchor_year_group", "hemolysis_lab",
            "hemolysis_gas")
x <- read.csv(gzfile(cfg$input$mimic_w10$path), colClasses = "character", na.strings = character(0), check.names = FALSE)
if (!identical(names(x), HEADER)) stop("header mismatch")
num <- function(v) { v[v == ""] <- NA; suppressWarnings(as.numeric(v)) }
tsx <- function(v) { v[v == ""] <- NA; as.numeric(as.POSIXct(v, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")) }
D <- data.frame(pair_id = suppressWarnings(as.integer(x$pair_id)), lab = num(x$lab_k), gas = num(x$gas_k),
                smin = num(x$signed_minutes), spec = x$specimen_class, pid = x$subject_id,
                st_gas = tsx(x$gas_storetime), st_lab = tsx(x$lab_storetime),
                hadm_miss = x$lab_hadm_missing == "1" | x$gas_hadm_missing == "1",
                hemo = x$hemolysis_lab == "1" | x$hemolysis_gas == "1")
bad <- !grepl("^[0-9]{1,9}$", x$pair_id) | !is.finite(D$lab) | !is.finite(D$gas) | D$lab <= 0 | D$gas <= 0 |
  !nzchar(D$pid) | x$window_min != "10" | !is.finite(D$smin) | abs(D$smin) > 10 + 1e-9 |
  !(D$spec %in% c("ART", "NONART", "UNKNOWN"))
if (any(bad) || anyDuplicated(D$pair_id)) stop("invalid key fields")
if (!all(c(x$lab_hadm_missing, x$gas_hadm_missing, x$hemolysis_lab, x$hemolysis_gas) %in% c("0", "1"))) stop("flag not 0/1")
rm(x)
NP <- nrow(D); NPAT <- length(unique(D$pid))
if (!TEST && (NP != 23357 || NPAT != 8797)) stop("primary set size differs from AN_r1")

dir.create(OUT, recursive = TRUE); dir.create(file.path(OUT, "code"))
invisible(file.copy(SCRIPT, file.path(OUT, "code", basename(SCRIPT)))); invisible(file.copy(CFG_PATH, file.path(OUT, "code", basename(CFG_PATH))))
invisible(file.copy(cfg$spec$path, file.path(OUT, "code", basename(cfg$spec$path))))
LOGF <- file(file.path(OUT, "run.log"), open = "wt", encoding = "UTF-8")
logm <- function(...) { s <- paste0(format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), " ", paste0(..., collapse = "")); cat(s, "\n"); writeLines(s, LOGF); flush(LOGF) }
logm("start; inputs verified; n pairs and patients match AN_r1")
writeLines(capture.output(sessionInfo()), file.path(OUT, "session_info.txt"))

# ---------------- helpers ----------------
r10 <- function(n) if (n == 0) 0L else if (n < 10) "<10" else as.integer(((n + 5) %/% 10) * 10)
q7 <- function(v, p) unname(quantile(v, p, type = 7, names = FALSE))
cat3 <- function(v) ifelse(v < 3.5, 1L, ifelse(v > 5.0, 3L, 2L))
D$d <- D$gas - D$lab
D$lead <- (D$st_lab - D$st_gas) / 60
D$disc3 <- cat3(D$gas) != cat3(D$lab)
D$lab6 <- D$lab >= 6.0; D$gas6 <- D$gas >= 6.0
D$lab_only6 <- D$lab6 & !D$gas6; D$gas_only6 <- D$gas6 & !D$lab6

# Patient-level sufficient statistics; resampling order identical to AN_r1 cluster_boot (split on as.character(pid)).
# cols: named list of numeric row vectors; ests: list of list(num=, den=) (ratio of sums); den = "n" means row count.
boot_ratio <- function(dd, cols, ests, B, seed) {
  f <- factor(as.character(dd$pid)); lv <- names(split(seq_len(nrow(dd)), as.character(dd$pid)))
  if (!identical(levels(f), lv)) stop("patient order differs from cluster_boot")
  M <- cbind(n = 1, do.call(cbind, lapply(cols, as.numeric)))
  S <- rowsum(M, f, reorder = TRUE)
  if (!identical(rownames(S), levels(f))) stop("rowsum order")
  P <- nrow(S)
  est_of <- function(tot) vapply(ests, function(e) { dn <- tot[[e$den]]; if (dn == 0) NA_real_ else tot[[e$num]] / dn }, 0)
  point <- est_of(colSums(M))
  RNGkind("Mersenne-Twister", "Inversion", "Rejection"); set.seed(seed)
  res <- matrix(NA_real_, B, length(ests), dimnames = list(NULL, names(ests)))
  for (b in seq_len(B)) { s <- sample.int(P, P, replace = TRUE); res[b, ] <- est_of(colSums(S[s, , drop = FALSE])) }
  out <- list()
  for (k in names(ests)) {
    bc <- res[, k]; ok <- is.finite(bc); nf <- sum(!ok)
    tot <- colSums(M); nu <- tot[[ests[[k]]$num]]; de <- tot[[ests[[k]]$den]]
    out[[k]] <- if (!is.finite(point[[k]])) list(est = NA, lo = NA, hi = NA, n_fail = nf, num = nu, den = de)
      else if (nf > 0.01 * B) list(est = point[[k]], lo = NA, hi = NA, n_fail = nf, num = nu, den = de)
      else list(est = point[[k]], lo = q7(bc[ok], 0.025), hi = q7(bc[ok], 0.975), n_fail = nf, num = nu, den = de)
  }
  out
}
B <- as.integer(cfg$B); SEED <- as.numeric(cfg$seed)

# ---------------- reproduction gate (spec 0.4) ----------------
rep <- boot_ratio(D, list(disc3 = D$disc3, lab_only6 = D$lab_only6, d = D$d),
                  list(disc3 = list(num = "disc3", den = "n"), cut6.0_lab_only = list(num = "lab_only6", den = "n"),
                       mean_diff = list(num = "d", den = "n")), B, SEED)
gate <- list()
for (k in names(rep)) { L <- LOCK$mimic$P$estimates[[k]]
  gate[[k]] <- max(abs(c(rep[[k]]$est - L$est, rep[[k]]$lo - L$lo, rep[[k]]$hi - L$hi))) }
leadP <- q7(D$lead[is.finite(D$lead)], c(0.25, 0.5, 0.75))
gate$lead_quartiles <- max(abs(leadP - unlist(LOCK$storetime_order_mimic$lead_minutes_q25_q50_q75)))
logm("reproduction gate max abs diffs: ", paste(names(gate), signif(unlist(gate), 3), collapse = "; "))
if (!TEST && (any(unlist(gate[c("disc3", "cut6.0_lab_only", "mean_diff")]) > 1e-12) || gate$lead_quartiles > 1e-9)) {
  logm("STOP: reproduction gate failed"); close(LOGF); stop("reproduction gate failed") }

small <- function(nu, de) (nu >= 1 && nu <= 9) || ((de - nu) >= 1 && (de - nu) <= 9)
mi <- function(est, nu, de) if (small(nu, de)) "<10" else est
R <- list(run_id = cfg$run_id, label = "post hoc exploratory", reproduction_gate = lapply(gate, function(v) signif(v, 3)))
EX <- list()   # exact values kept in memory only (verification); never written

# ---------------- C1 ----------------
C1 <- D[is.finite(D$lead) & D$lead > 0, ]
bins <- list(B1 = C1$gas < 5.0, B2 = C1$gas >= 5.0 & C1$gas < 5.5, B3 = C1$gas >= 5.5 & C1$gas < 6.0, B123 = C1$gas < 6.0)
cols <- list(); ests <- list()
for (b in names(bins)) { cols[[paste0(b, "_in")]] <- bins[[b]]; cols[[paste0(b, "_lab6")]] <- bins[[b]] & C1$lab6
  ests[[b]] <- list(num = paste0(b, "_lab6"), den = paste0(b, "_in")) }
logm("C1 bootstrap")
c1 <- boot_ratio(C1, cols, ests, B, SEED)
R$C1 <- list(n_pairs_R = r10(nrow(C1)), n_patients_R = r10(length(unique(C1$pid))),
             lead_q25_q50_q75 = q7(C1$lead, c(0.25, 0.5, 0.75)), bins = list())
EX$C1 <- list(n = nrow(C1))
for (b in names(bins)) { e <- c1[[b]]; inb <- bins[[b]]
  R$C1$bins[[b]] <- list(den_R = r10(e$den), patients_R = r10(length(unique(C1$pid[inb]))), num_R = r10(e$num),
    est = mi(e$est, e$num, e$den), lo = mi(e$lo, e$num, e$den), hi = mi(e$hi, e$num, e$den), n_fail = e$n_fail,
    lead_q25_q50_q75 = if (sum(inb) >= 100) q7(C1$lead[inb], c(0.25, 0.5, 0.75)) else "n_below_100")
  EX$C1[[b]] <- list(num = e$num, den = e$den) }
EX$A <- sum(D$lab_only6); EX$lab6 <- sum(D$lab6); EX$gas_only6 <- sum(D$gas_only6); EX$disc3 <- sum(D$disc3)

# ---------------- C3a / C3b ----------------
R$C3 <- list(); EX$C3 <- list()
feat <- list(gas_lower = D$d < 0, same_charttime = D$smin == 0, arterial = D$spec == "ART", hemolysis_comment = D$hemo,
             hadm_time_linked = D$hadm_miss, value_outside_1.5_10 = D$lab < 1.5 | D$lab > 10 | D$gas < 1.5 | D$gas > 10)
for (E in c("E2", "E1")) {
  thr <- if (E == "E2") 2.0 else 1.0; ext <- abs(D$d) >= thr - 1e-9
  per <- tapply(ext, D$pid, sum); per <- per[per > 0]; ne <- sum(ext)
  srt <- sort(as.integer(per), decreasing = TRUE); k50 <- which(cumsum(srt) >= 0.5 * ne)[1]
  ge2 <- sum(per[per >= 2])
  R$C3[[E]] <- list(threshold = thr, n_ext_R = r10(ne), patients_with_ext_R = r10(length(per)), patients_for_50pct_R = r10(k50),
                    share_from_patients_ge2 = list(num_R = r10(ge2), den_R = r10(ne), est = mi(ge2 / ne, ge2, ne)), features = list())
  EX$C3[[E]] <- list(ne = ne, npat = length(per), k50 = k50, ge2 = ge2, feat = list())
  for (fn in names(feat)) { fv <- feat[[fn]]
    R$C3[[E]]$features[[fn]] <- list(ext = list(num_R = r10(sum(fv & ext)), den_R = r10(ne), est = mi(sum(fv & ext) / ne, sum(fv & ext), ne)),
                                     nonext = list(num_R = r10(sum(fv & !ext)), den_R = r10(sum(!ext)), est = mi(sum(fv & !ext) / sum(!ext), sum(fv & !ext), sum(!ext))))
    EX$C3[[E]]$feat[[fn]] <- c(ext = sum(fv & ext), nonext = sum(fv & !ext), total = sum(fv)) }
}

# ---------------- C3c ----------------
xest <- list(mean_diff = list(num = "d", den = "n"), disc3 = list(num = "disc3", den = "n"),
             cut6.0_lab_only = list(num = "lab_only6", den = "n"), cut6.0_gas_only = list(num = "gas_only6", den = "n"),
             cut6.0_gas_not_given_lab = list(num = "lab_only6", den = "lab6"))
R$C3c <- list(); EX$C3c <- list(); XB <- list()
for (X in c("X2", "X1")) {
  thr <- if (X == "X2") 2.0 else 1.0; dd <- D[abs(D$d) < thr - 1e-9, ]
  logm("C3c bootstrap ", X)
  e <- XB[[X]] <- boot_ratio(dd, list(d = dd$d, disc3 = dd$disc3, lab_only6 = dd$lab_only6, gas_only6 = dd$gas_only6, lab6 = dd$lab6), xest, B, SEED)
  R$C3c[[X]] <- list(threshold_removed = thr, n_pairs_R = r10(nrow(dd)), n_patients_R = r10(length(unique(dd$pid))),
                     estimates = lapply(e, function(z) { sm <- !is.na(z$num) && z$num == round(z$num) && small(z$num, z$den)
                                                     list(est = if (sm) "<10" else z$est, lo = if (sm) "<10" else z$lo, hi = if (sm) "<10" else z$hi, n_fail = z$n_fail,
                                                           num_R = if (is.na(z$num) || z$num != round(z$num)) NA else r10(z$num),
                                                           den_R = r10(z$den)) }))
  EX$C3c[[X]] <- list(n = nrow(dd), npat = length(unique(dd$pid)), disc3 = sum(dd$disc3), A = sum(dd$lab_only6),
                      g = sum(dd$gas_only6), lab6 = sum(dd$lab6))
}

# ---------------- publication rules (spec 0.5) and verification (spec 5) ----------------
fmt <- function(p, dp) as.numeric(sprintf(paste0("%.", dp, "f"), 100 * p))
pubprop <- function(nu, de, est, lo, hi, dp) if (small(nu, de)) "<10" else
  list(pct = fmt(est, dp), lo = if (is.na(lo)) "not estimable" else fmt(lo, dp), hi = if (is.na(hi)) "not estimable" else fmt(hi, dp))
rng_r10 <- function(Rv) if (identical(Rv, "<10")) 1:9 else if (Rv == 0) 0L else (Rv - 5):(Rv + 4)
pct_feasible <- function(cands, dens, pct, dp) cands[vapply(cands, function(v) any(fmt(v / dens, dp) == pct), TRUE)]

LV <- list(C1 = 0, X2 = 0, X1 = 0); DROPF <- list(E2 = character(0), E1 = character(0)); FIRST <- TRUE
ladder_log <- character(0)
for (iter in 1:12) {
PUBN <- list(run_id = cfg$run_id, label = "post hoc exploratory", source_spec_sha256 = cfg$spec$sha256)
# C1
PUBN$C1 <- list(n_pairs_R = R$C1$n_pairs_R, n_patients_R = R$C1$n_patients_R,
                lead_minutes_q25_q50_q75 = round(R$C1$lead_q25_q50_q75), lead_all_pairs_locked = unlist(LOCK$storetime_order_mimic$lead_minutes_q25_q50_q75), bins = list())
for (b in names(bins)) { z <- R$C1$bins[[b]]; ex <- EX$C1[[b]]; cb <- c1[[b]]
  PUBN$C1$bins[[b]] <- list(den_R = z$den_R, patients_R = z$patients_R, num_R = if (LV$C1 >= 2) "not shown" else z$num_R,
    pct = if (LV$C1 >= 4 || (LV$C1 >= 3 && b != "B123")) "not shown (small numbers)" else pubprop(ex$num, ex$den, cb$est, cb$lo, cb$hi, if (LV$C1 >= 1) 0 else 1),
    lead_minutes_q25_q50_q75 = if (is.character(z$lead_q25_q50_q75)) z$lead_q25_q50_q75 else round(z$lead_q25_q50_q75)) }
# C2 (read only from SHARE_r5, no recomputation)
m <- PUB$mimic
PUBN$C2_check <- list(P = list(n = m$P$n_pairs, disc3_pct = m$P$disc3$pct, lab_only6_pct = m$P$thresholds[["6.0"]]$lab_only$pct$pct),
                      S9 = list(n = m$S9$n_pairs, disc3_pct = m$S9$disc3$pct, lab_only6_pct = m$S9$thresholds_5_6[["6.0"]]$lab_only$pct$pct))
# C3
PUBN$C3 <- list()
for (E in names(R$C3)) { z <- R$C3[[E]]; ex <- EX$C3[[E]]
  ff <- list()
  for (fn in names(z$features)) { f <- z$features[[fn]]; fe <- ex$feat[[fn]]
    ff[[fn]] <- list(ext = pubprop(fe[["ext"]], ex$ne, fe[["ext"]] / ex$ne, NA, NA, 0), nonext = pubprop(fe[["nonext"]], NP - ex$ne, fe[["nonext"]] / (NP - ex$ne), NA, NA, 0)) }
  for (fn in names(ff)) for (s in c("ext", "nonext")) if (is.list(ff[[fn]][[s]])) ff[[fn]][[s]] <- ff[[fn]][[s]]$pct
  for (fn in intersect(names(ff), DROPF[[E]])) ff[[fn]] <- list(ext = "not shown (small numbers)", nonext = "not shown (small numbers)")
  PUBN$C3[[E]] <- list(threshold = z$threshold, n_ext = if (ex$ne >= 10) ex$ne else "<10",
                       patients_with_ext_R = if ("patients_with_ext_R" %in% DROPF[[E]]) "not shown" else z$patients_with_ext_R,
                       patients_for_50pct_R = if ("patients_for_50pct_R" %in% DROPF[[E]]) "not shown" else z$patients_for_50pct_R,
                       share_from_patients_ge2 = { p <- pubprop(ex$ge2, ex$ne, ex$ge2 / ex$ne, NA, NA, 0); if (is.list(p)) p$pct else p },
                       features_pct = ff) }
PUBN$C3c <- list()
for (X in names(R$C3c)) { z <- R$C3c[[X]]; ex <- EX$C3c[[X]]
  rm_pairs <- NP - ex$n; rm_pat <- NPAT - ex$npat
  es <- XB[[X]]
  numx <- c(disc3 = ex$disc3, cut6.0_lab_only = ex$A, cut6.0_gas_only = ex$g, cut6.0_gas_not_given_lab = ex$A)
  denx <- c(disc3 = ex$n, cut6.0_lab_only = ex$n, cut6.0_gas_only = ex$n, cut6.0_gas_not_given_lab = ex$lab6)
  dpx <- c(disc3 = 1, cut6.0_lab_only = 1, cut6.0_gas_only = 1, cut6.0_gas_not_given_lab = 0); if (LV[[X]] >= 1) dpx[] <- 0
  pe <- list(mean_diff = list(est = round(es$mean_diff$est, 3), lo = round(es$mean_diff$lo, 3), hi = round(es$mean_diff$hi, 3)))
  for (k in names(numx)) pe[[k]] <- if (LV[[X]] >= 2) "not shown (small numbers)" else pubprop(numx[[k]], denx[[k]], es[[k]]$est, es[[k]]$lo, es[[k]]$hi, dpx[[k]])
  PUBN$C3c[[X]] <- list(threshold_removed = z$threshold_removed,
                        n_pairs = if (rm_pairs >= 10) ex$n else z$n_pairs_R, n_pairs_exact = rm_pairs >= 10,
                        n_patients = if (rm_pat >= 10) ex$npat else z$n_patients_R, n_patients_exact = rm_pat >= 10,
                        estimates = pe) }

# --- verification: enumerate feasible values of every protected quantity (true value 1-9) ---
V <- list(); TARGET <- 4
addv <- function(name, true, feas) { if (true >= 1 && true <= 9) {
  w <- if (length(feas) == 0) NA else max(feas) - min(feas)
  V[[name]] <<- list(width = w, pass = !is.na(w) && w >= TARGET && (true %in% feas), n_feasible = length(feas), true_in_feasible = true %in% feas) } }
# published anchors (SHARE_r5): A = #(lab>=6 & gas<6) in P; lab6 = #(lab>=6); disc3; gas_only6
A_set <- pct_feasible(rng_r10(m$P$thresholds[["6.0"]]$lab_only$num_R), NP, m$P$thresholds[["6.0"]]$lab_only$pct$pct, 1)
lab6_set <- rng_r10(m$P$thresholds[["6.0"]]$gas_not_given_lab$den_R)
lab6_set <- lab6_set[vapply(lab6_set, function(dv) any(fmt(A_set / dv, 0) == m$P$thresholds[["6.0"]]$gas_not_given_lab$pct$pct), TRUE)]
disc_set <- pct_feasible(rng_r10(m$P$disc3_num_R), NP, m$P$disc3$pct, 1)
g_set <- pct_feasible(rng_r10(m$P$thresholds[["6.0"]]$gas_only$num_R), NP, m$P$thresholds[["6.0"]]$gas_only$pct$pct, 1)
if (!(EX$A %in% A_set) || !(EX$lab6 %in% lab6_set) || !(EX$disc3 %in% disc_set) || !(EX$gas_only6 %in% g_set)) { if (TEST) { logm("TEST: anchors replaced by synthetic neighbourhoods"); A_set <- EX$A + (-4:4); lab6_set <- EX$lab6 + (-4:4); disc_set <- EX$disc3 + (-4:4); g_set <- pmax(0, EX$gas_only6 + (-4:4)) } else stop("anchor sets do not contain true values") }
# C1 bins
pubC1 <- PUBN$C1$bins; nC1_set <- rng_r10(PUBN$C1$n_pairs_R); M_max <- NP - min(nC1_set)
binset <- list()
for (b in names(pubC1)) { pb <- pubC1[[b]]; dens <- rng_r10(pb$den_R); cand <- if (is.character(pb$num_R) && pb$num_R != "<10") 0:max(c(A_set, 1000)) else rng_r10(pb$num_R)
  if (b != "B123" && is.character(pb$num_R) && pb$num_R != "<10" && !is.list(pb$pct)) cand <- 0:dens[length(dens)]
  if (is.list(pb$pct)) cand <- pct_feasible(cand, dens, pb$pct$pct, 1)
  binset[[b]] <- cand; addv(paste0("C1_", b, "_num"), EX$C1[[b]]$num, cand) }
# combined must equal the sum of B1..B3; L = A - combined (pairs outside C1)
grid <- expand.grid(b1 = binset$B1, b2 = binset$B2, b3 = binset$B3); grid$s <- grid$b1 + grid$b2 + grid$b3
grid <- grid[grid$s %in% binset$B123, ]
for (b in c("B1", "B2", "B3")) addv(paste0("C1_", b, "_num_joint"), EX$C1[[b]]$num, unique(grid[[tolower(sub("B", "b", b))]]))
Lf <- unique(as.vector(outer(A_set, unique(grid$s), "-"))); Lf <- Lf[Lf >= 0 & Lf <= M_max]
addv("C1_outside_L", EX$A - EX$C1$B123$num, Lf)
# C3c: removed-pair numerator differences between P and X sets
for (X in names(PUBN$C3c)) { px <- PUBN$C3c[[X]]; ex <- EX$C3c[[X]]
  nX <- if (isTRUE(px$n_pairs_exact)) px$n_pairs else rng_r10(px$n_pairs)
  setX <- function(k, Pset, true_x, dp) { pp <- px$estimates[[k]]
    if (!is.list(pp)) return(NULL)
    cand <- 0:max(Pset); cand[vapply(cand, function(v) any(fmt(v / nX, dp) == pp$pct), TRUE)] }
  dX <- setX("disc3", disc_set, ex$disc3, 1); if (!is.null(dX)) addv(paste0(X, "_removed_disc3"), EX$disc3 - ex$disc3, { v <- as.vector(outer(disc_set, dX, "-")); unique(v[v >= 0]) })
  aX <- setX("cut6.0_lab_only", A_set, ex$A, 1); if (!is.null(aX)) addv(paste0(X, "_removed_lab_only6"), EX$A - ex$A, { v <- as.vector(outer(A_set, aX, "-")); unique(v[v >= 0]) })
  gX <- setX("cut6.0_gas_only", g_set, ex$g, 1); if (!is.null(gX)) addv(paste0(X, "_removed_gas_only6"), EX$gas_only6 - ex$g, { v <- as.vector(outer(g_set, gX, "-")); unique(v[v >= 0]) })
  pp <- px$estimates$cut6.0_gas_not_given_lab
  if (is.list(pp)) { aXs <- if (is.null(aX)) 0:max(A_set) else aX
    l6 <- unique(unlist(lapply(aXs, function(a) { dv <- a:max(lab6_set); dv[fmt(a / pmax(dv, 1), 0) == pp$pct] })))
    v <- as.vector(outer(lab6_set, l6, "-")); addv(paste0(X, "_removed_lab6"), EX$lab6 - ex$lab6, unique(v[v >= 0])) }
  if (!isTRUE(px$n_patients_exact)) {
    v <- NPAT - rng_r10(px$n_patients); addv(paste0(X, "_removed_patients"), NPAT - ex$npat, v[v >= 0]) } }
# C3a/C3b suppressed cells: cell_ext = total - cell_nonext, nonext shown as integer pct of an exact denominator
totals_known <- list(hemolysis_comment = NP - m$S9$n_pairs, hadm_time_linked = NP - m$S5$n_pairs, arterial = m$S1$n_pairs)
if (!TEST && (sum(D$hemo) != totals_known$hemolysis_comment || sum(D$hadm_miss) != totals_known$hadm_time_linked || sum(D$spec == "ART") != totals_known$arterial)) stop("published totals do not match data")
if (TEST) totals_known <- list(hemolysis_comment = sum(D$hemo), hadm_time_linked = sum(D$hadm_miss), arterial = sum(D$spec == "ART"))
for (E in names(PUBN$C3)) { pe <- PUBN$C3[[E]]; ex <- EX$C3[[E]]; ne <- ex$ne
  for (fn in names(pe$features_pct)) { fe <- ex$feat[[fn]]; f <- pe$features_pct[[fn]]
    for (s in c("ext", "nonext")) { true_v <- fe[[s]]; den <- if (s == "ext") ne else NP - ne
      for (cell in c("num", "complement")) { tv <- if (cell == "num") true_v else den - true_v
        if (tv < 1 || tv > 9) next
        other <- if (s == "ext") "nonext" else "ext"; oden <- if (s == "ext") NP - ne else ne
        if (identical(f[[s]], "not shown (small numbers)")) { addv(paste0("C3_", E, "_", fn, "_", s, "_", cell), tv, 0:den); next }
        ocand <- 0:oden; if (is.numeric(f[[other]])) ocand <- ocand[fmt(ocand / oden, 0) == f[[other]]]
        tot <- if (!is.null(totals_known[[fn]])) totals_known[[fn]] else NA
        feas <- if (is.na(tot)) 0:den else { v <- tot - ocand; v[v >= 0 & v <= den] }
        if (cell == "complement") feas <- den - feas
        if (identical(f[[s]], "<10")) feas <- feas[vapply(feas, function(v) { nu <- if (cell == "num") v else den - v; small(nu, den) }, TRUE)] else feas <- feas[fmt((if (cell == "num") feas else den - feas) / den, 0) == f[[s]]]
        addv(paste0("C3_", E, "_", fn, "_", s, "_", cell), tv, unique(feas)) } } }
  for (q in c("patients_with_ext_R", "patients_for_50pct_R")) { tv <- if (q == "patients_with_ext_R") ex$npat else ex$k50
    addv(paste0("C3_", E, "_", q), tv, if (identical(pe[[q]], "not shown")) 0:NPAT else rng_r10(pe[[q]])) }
  if (ne >= 1 && ne <= 9) addv(paste0("C3_", E, "_n_ext"), ne, 1:9) }


  FIRST <- FALSE
  bad <- names(V)[!vapply(V, function(v) isTRUE(v$pass), TRUE)]
  if (any(!vapply(V, function(v) isTRUE(v$true_in_feasible), TRUE)) && !TEST) stop("verification constraint error: true value outside feasible set")
  if (length(bad) == 0) break
  ladder_log <- c(ladder_log, paste0("iteration ", iter, ": failing ", paste(bad, collapse = ", ")))
  if (any(startsWith(bad, "C1_"))) LV$C1 <- LV$C1 + 1
  for (X in c("X2", "X1")) if (any(startsWith(bad, paste0(X, "_")))) LV[[X]] <- LV[[X]] + 1
  for (E in c("E2", "E1")) { bb <- bad[startsWith(bad, paste0("C3_", E, "_"))]
    for (q in bb) { fn <- names(feat)[vapply(names(feat), function(f) grepl(paste0("_", f, "_"), q, fixed = TRUE), TRUE)]
      if (length(fn)) DROPF[[E]] <- union(DROPF[[E]], fn)
      for (pq in c("patients_with_ext_R", "patients_for_50pct_R")) if (endsWith(q, pq)) DROPF[[E]] <- union(DROPF[[E]], pq) } }
  if (LV$C1 > 4 || LV$X2 > 2 || LV$X1 > 2) break
}
PUBN$masking <- list(levels = LV, dropped_features = DROPF, ladder = ladder_log)
all_pass <- length(V) == 0 || all(vapply(V, function(v) isTRUE(v$pass), TRUE))
vm <- c("# PHX_r1 发表前防反推核验（SAP §17.1；规格第 5 节）", "",
        "- 标准：每个受保护量（真实值 1–9）的可行范围 max − min ≥ 4。只列宽度，不列真实值。",
        "- 覆盖边界：非线性量（中位数、CI）未纳入；各量按所列约束分别枚举，未做全部量的联合整数规划。", "",
        paste0("- 受保护量个数：", length(V), "；全部通过：", all_pass), "",
        paste0("- 遮蔽阶梯（规格第 5 节，按组逐级）：C1 级别 ", LV$C1, "；X2 级别 ", LV$X2, "；X1 级别 ", LV$X1, "；C3 不发表的特征：", paste(unlist(DROPF), collapse = ", ")),
        if (length(ladder_log)) paste0("- ", ladder_log) else "- 第一次即全部通过", "",
        "| 量 | 可行值个数 | 宽度 | 真实值在可行集内（约束自检） | 通过 |", "|---|---:|---:|---|---|")
for (k in names(V)) vm <- c(vm, sprintf("| %s | %d | %s | %s | %s |", k, V[[k]]$n_feasible, format(V[[k]]$width), V[[k]]$true_in_feasible, V[[k]]$pass))
writeLines(vm, file.path(OUT, "verification.md"), useBytes = FALSE)
jsonlite::write_json(R, file.path(OUT, "results_r10.json"), auto_unbox = TRUE, digits = NA, pretty = TRUE, na = "null")
if (all_pass) { jsonlite::write_json(PUBN, file.path(OUT, "publish_numbers.json"), auto_unbox = TRUE, digits = NA, pretty = TRUE, na = "null"); logm("verification passed; publish_numbers.json written")
} else logm("verification FAILED; publish_numbers.json not written")
logm("done")
close(LOGF)
fs <- list.files(OUT, recursive = TRUE, full.names = TRUE); fs <- fs[basename(fs) != "SHA256SUMS.txt"]
writeLines(vapply(fs, function(p) paste0(sha_file(p), "  ", substring(p, nchar(OUT) + 2)), ""), file.path(OUT, "SHA256SUMS.txt"))
if (!all_pass) quit(status = 1)
