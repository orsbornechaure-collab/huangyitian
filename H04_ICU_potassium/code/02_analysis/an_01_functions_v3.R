# H04 analysis functions v3 (sourced by an_01_main_v3.R and by the unit tests an_test_05_units_v3.R).
# Implements SAP v1.2 sections 7-13. No file I/O here; no row-level output.

# ---- run guards (pure functions; evaluated by an_01_main_v3.R before anything is written; unit-tested) ----
PROJ <- Sys.getenv("H04_PROJECT_DIR", ".")  # public release: local path removed
REAL <- list(
  mimic = list(`5` = "c8fde1033ae1728aa1272d836fb5c49d8ceaa5b51c4e3e9245ce67c8d876e190",
               `10` = "24ad13a48afa15a276388a1e6707ac3e61d5cc7584dbb3eb93888d47438bf62f",
               `30` = "413e839aa11c124f6b58944d0f62f2f4bc47bf240e530a7beb1916e3320891a1"),
  sicdb = list(`5` = "af55a91540c4e00aad6fa87b5c683a1927ffe238054e09c56547e98b99ae51b3",
               `10` = "19c39916fb701571339bb6de523882189e457b74488490267c14564117100a83",
               `30` = "2032971c369a61e57eebba0d441309e3ae38fa6e54fcb7858fc5744c47e62dc4"))
REAL_DIR <- file.path(PROJ, "04_derived", "H04_20261111_BUILD_r1")
AUTH_PATH <- file.path(PROJ, "00_governance", "G4_运行授权.json")
COUNTERSIGN_PATH <- file.path(PROJ, "06_audit", "G4_运行授权_独立核对", "核对结果.json")
PKG <- c(R = "4.6.1", lme4 = "2.0.6", geepack = "1.3.13", mcr = "1.3.3.1", jsonlite = "2.0.0", digest = "0.6.39")
AUTH_FIELDS <- c("project", "gate", "decision", "owner_words", "owner_message_time", "approval_record", "sap_frozen",
                 "scripts", "run_id", "n_boot", "n_boot_paba", "seed")
npath <- function(p) tolower(normalizePath(p, winslash = "/", mustWork = FALSE))
parts <- function(p) strsplit(npath(p), "/", fixed = TRUE)[[1]]
under <- function(p, root) { a <- parts(p); b <- parts(root); length(a) > length(b) && identical(a[seq_along(b)], b) }
s1 <- function(x) is.character(x) && length(x) == 1 && nzchar(x)

# owner_words must name H04, G4 and approval, and contain no refusal/deferral word; the approval record file
# must contain owner_words verbatim. This is a consistency check of the drafter's transcription, NOT proof of approval;
# proof rests on the independent countersignature (below) and the owner's own thread message.
owner_words_problem <- function(words, record_text) {
  if (!s1(words)) return("authorization: owner_words missing")
  if (!grepl("H04", words, fixed = TRUE) || !grepl("G4", words, fixed = TRUE) || !grepl("批准", words, fixed = TRUE))
    return("authorization: owner_words do not name H04, G4 and 批准")
  if (grepl("不批准|未批准|不同意|暂缓|撤回|否决", words)) return("authorization: owner_words contain a refusal or deferral")
  if (!s1(record_text) || !grepl(words, record_text, fixed = TRUE)) return("authorization: approval record does not contain owner_words verbatim")
  NULL
}

# au: parsed G4_运行授权.json; cs: parsed independent countersignature (or NULL); ev: list(approval_sha_actual,
# approval_text, auth_sha_actual, sha_main, sha_funs); pkg_versions: named list of installed versions.
real_mode_problem <- function(au, cs, cfg, ev, pkg_versions) {
  if (!is.list(au) || !all(AUTH_FIELDS %in% names(au))) return("authorization: required fields missing")
  if (!identical(au$project, "H04") || !identical(au$gate, "G4") || !identical(au$decision, "APPROVED")) return("authorization: project/gate/decision mismatch")
  if (!s1(au$owner_message_time)) return("authorization: owner_message_time missing")
  ap <- au$approval_record$path
  if (!s1(ap) || !under(file.path(PROJ, ap), file.path(PROJ, "00_governance")) || !s1(ev$approval_sha_actual) ||
      !identical(tolower(as.character(au$approval_record$sha256)), ev$approval_sha_actual))
    return("authorization: approval record missing, outside 00_governance, or hash mismatch")
  w <- owner_words_problem(au$owner_words, ev$approval_text); if (!is.null(w)) return(w)
  if (!s1(au$sap_frozen$path) || !identical(npath(file.path(PROJ, au$sap_frozen$path)), npath(cfg$sap$path)) ||
      !under(cfg$sap$path, file.path(PROJ, "01_protocol")) || !identical(tolower(as.character(au$sap_frozen$sha256)), tolower(cfg$sap$sha256)))
    return("authorization: frozen SAP path/hash differs from config")
  if (!identical(tolower(as.character(au$scripts$main)), ev$sha_main) || !identical(tolower(as.character(au$scripts$functions)), ev$sha_funs))
    return("authorization: script hash mismatch")
  if (!identical(au$run_id, cfg$run_id) || !grepl("^H04_[0-9]{8}_AN_r[0-9]+$", cfg$run_id)) return("authorization: run_id mismatch or malformed")
  if (!identical(parts(dirname(cfg$out_dir)), parts(file.path(PROJ, "05_results"))) || !identical(basename(npath(cfg$out_dir)), tolower(cfg$run_id)))
    return("real mode: out_dir must be 05_results/<run_id>")
  if (!identical(as.numeric(cfg$n_boot), 2000) || !identical(as.numeric(cfg$n_boot_paba), 1000) || !identical(as.numeric(cfg$seed), 20261110) ||
      !identical(as.numeric(au$n_boot), 2000) || !identical(as.numeric(au$n_boot_paba), 1000) || !identical(as.numeric(au$seed), 20261110))
    return("real mode: bootstrap settings must be 2000/1000/20261110")
  for (db in c("mimic", "sicdb")) for (wn in c("5", "10", "30")) {
    d <- cfg$data[[db]][[wn]]
    if (!identical(npath(d$path), npath(file.path(REAL_DIR, sprintf("%s_pairs_w%s.csv.gz", db, wn)))) || !identical(tolower(d$sha256), REAL[[db]][[wn]]))
      return(paste("real mode: input is not the frozen BUILD_r1 file:", db, wn))
  }
  for (p in names(PKG)) if (!identical(pkg_versions[[p]], PKG[[p]])) return(paste("real mode: version differs:", p))
  # independent countersignature: written by a reviewer other than the drafter after comparing the owner's approval
  # record with this authorization file; it must bind the exact authorization and approval-record hashes.
  if (!is.list(cs)) return("authorization: independent countersignature missing")
  if (!identical(cs$result, "VERIFIED") || !s1(cs$verifier) || grepl("<drafter>", tolower(cs$verifier), fixed = TRUE))
    return("authorization: countersignature not VERIFIED or not independent")
  if (!identical(tolower(as.character(cs$auth_json_sha256)), ev$auth_sha_actual) ||
      !identical(tolower(as.character(cs$approval_record_sha256)), ev$approval_sha_actual))
    return("authorization: countersignature does not bind this authorization/approval record")
  NULL
}

# synthetic inputs must come from the controlled generator: all six files in one directory named h04_syn_*,
# listed with their hashes in synthetic_manifest.json (generator an_test_04_synthetic_v3.py); out_dir inside it.
# This prevents accidental misuse; it cannot detect deliberately disguised real data.
synthetic_mode_problem <- function(cfg, manifest) {
  if (!grepl("^SYNTHETIC", cfg$run_id)) return("synthetic mode: run_id must start with SYNTHETIC")
  dirs <- unique(as.vector(vapply(c("mimic", "sicdb"), function(db) vapply(c("5", "10", "30"), function(wn) npath(dirname(cfg$data[[db]][[wn]]$path)), ""), character(3))))
  if (length(dirs) != 1 || !grepl("^h04_syn_", basename(dirs))) return("synthetic mode: inputs must all lie in one h04_syn_* test directory")
  if (!is.list(manifest) || !identical(manifest$generator, "an_test_04_synthetic_v3.py")) return("synthetic mode: generator manifest missing or wrong")
  for (db in c("mimic", "sicdb")) for (wn in c("5", "10", "30")) {
    d <- cfg$data[[db]][[wn]]; key <- sprintf("%s_pairs_w%s.csv.gz", db, wn)
    if (tolower(d$sha256) %in% unlist(REAL) || under(d$path, file.path(PROJ, "04_derived")) || under(d$path, Sys.getenv("H04_RAW_DATA_DIR", "raw_data")))
      return("synthetic mode: real data detected as input")
    if (!identical(basename(npath(d$path)), key) || !identical(tolower(as.character(manifest$files[[key]])), tolower(d$sha256)))
      return("synthetic mode: input not listed in generator manifest")
  }
  if (!under(cfg$out_dir, dirs)) return("synthetic mode: out_dir must lie inside the h04_syn_* test directory")
  NULL
}

CUTS <- c(3.0, 3.5, 5.0, 5.5, 6.0)
abn <- function(x, c) if (c < 5) x < c else if (c == 5.0) x > 5.0 else x >= c
cat3 <- function(x) ifelse(x < 3.5, 1L, ifelse(x > 5.0, 3L, 2L))
q7 <- function(x, p) unname(quantile(x, p, type = 7, names = FALSE))
q1 <- function(x, p) unname(quantile(x, p, type = 1, names = FALSE))
# weighted inverse-ECDF quantile: first sorted value whose cumulative weight share >= p (tolerance 1e-12)
wq1 <- function(x, w, p) { o <- order(x); cw <- cumsum(w[o]) / sum(w); x[o][which(cw >= p - 1e-12)[1]] }
fin <- function(x) !is.null(x) && length(x) == 1 && is.finite(x)
r10 <- function(n) if (is.na(n)) NA else if (n == 0) 0L else if (n < 10) "<10" else as.integer(((n + 5) %/% 10) * 10)

# a proportion carries c(estimate, numerator, denominator); non-proportions carry c(value, NA, NA)
prop <- function(num, den) c(if (den == 0) NA_real_ else num / den, num, den)
val <- function(v) c(if (fin(v)) v else NA_real_, NA, NA)

# grouped empirical LoA: mode "sample" -> all three NA if any group <10 or cut points equal (SAP 9.5);
# mode "boot" -> equal cut points make all NA; otherwise only a group with <10 pairs is NA (SAP 10, v0.7 table)
grouped_loa <- function(d, m, mode) {
  out <- list(); c1 <- q7(m, 1/3); c2 <- q7(m, 2/3)
  g <- ifelse(m <= c1, 1L, ifelse(m <= c2, 2L, 3L)); ng <- tabulate(g, 3)
  all_bad <- (c1 == c2) || (mode == "sample" && any(ng < 10))
  for (s in 1:3) {
    ok <- !all_bad && ng[s] >= 10
    out[[paste0("loa_grp", s, "_lo")]] <- val(if (ok) q7(d[g == s], 0.025) else NA)
    out[[paste0("loa_grp", s, "_hi")]] <- val(if (ok) q7(d[g == s], 0.975) else NA)
  }
  out
}

core_est <- function(lab, gas, mode = "sample") {
  n <- length(lab); r <- list()
  if (n == 0) return(r)
  d <- gas - lab; m <- (gas + lab) / 2; cg <- cat3(gas); cl <- cat3(lab)
  r$disc3 <- prop(sum(cg != cl), n)
  for (c in CUTS) {
    ag <- abn(gas, c); al <- abn(lab, c); k <- format(c, nsmall = 1)
    r[[paste0("cut", k, "_gas_only")]] <- prop(sum(ag & !al), n)
    r[[paste0("cut", k, "_lab_only")]] <- prop(sum(al & !ag), n)
    r[[paste0("cut", k, "_gas_not_given_lab")]] <- prop(sum(al & !ag), sum(al))
    r[[paste0("cut", k, "_lab_not_given_gas")]] <- prop(sum(ag & !al), sum(ag))
  }
  tab <- table(factor(cg, 1:3), factor(cl, 1:3))
  po <- sum(diag(tab)) / n; pe <- sum(rowSums(tab) * colSums(tab)) / n^2
  r$kappa3 <- val(if (abs(1 - pe) < 1e-15) NA else (po - pe) / (1 - pe))
  r$mean_diff <- val(mean(d))
  r$loa_emp_lo <- val(q7(d, 0.025)); r$loa_emp_hi <- val(q7(d, 0.975))
  r$loa_emp_t1_lo <- val(q1(d, 0.025)); r$loa_emp_t1_hi <- val(q1(d, 0.975))
  cm <- cat3(m)  # descriptive only; mathematically coupled with the outcome (SAP 8.5)
  for (s in 1:3) r[[paste0("disc3_by_mean_stratum", s)]] <- prop(sum((cg != cl)[cm == s]), sum(cm == s))
  c(r, grouped_loa(d, m, mode))
}

crosstab3 <- function(lab, gas) {  # 3x3 counts, rows = gas category, cols = lab category (rounded)
  t <- table(factor(cat3(gas), 1:3, c("gas_lt3.5", "gas_3.5to5.0", "gas_gt5.0")),
             factor(cat3(lab), 1:3, c("lab_lt3.5", "lab_3.5to5.0", "lab_gt5.0")))
  out <- list(); for (i in rownames(t)) { out[[i]] <- list(); for (j in colnames(t)) out[[i]][[j]] <- r10(t[i, j]) }
  out
}

# ---- mixed models with full status checks (SAP 9.6, 11.9) ----
fit_mixed <- function(formula, dat, family = NULL) {
  msgs <- character(0)
  fit <- tryCatch(withCallingHandlers(
    if (is.null(family)) lme4::lmer(formula, data = dat, REML = TRUE) else lme4::glmer(formula, data = dat, family = family),
    warning = function(w) { msgs <<- c(msgs, conditionMessage(w)); invokeRestart("muffleWarning") },
    message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") }),
    error = function(e) { msgs <<- c(msgs, paste("error:", conditionMessage(e))); NULL })
  if (is.null(fit)) return(list(fit = NULL, reason = paste(msgs, collapse = " | ")))
  all_msgs <- c(msgs, fit@optinfo$conv$lme4$messages)
  bad <- all_msgs[!grepl("^boundary \\(singular\\) fit", all_msgs)]
  opt_code <- fit@optinfo$conv$opt
  if (length(bad) > 0) return(list(fit = NULL, reason = paste(bad, collapse = " | ")))
  if (!is.null(opt_code) && opt_code != 0) return(list(fit = NULL, reason = paste("optimizer code", opt_code)))
  co <- summary(fit)$coefficients
  if (any(!is.finite(co[, 1])) || any(!is.finite(co[, 2]))) return(list(fit = NULL, reason = "non-finite coefficient or SE"))
  list(fit = fit, reason = if (lme4::isSingular(fit)) "singular (retained)" else "ok")
}

model_est <- function(lab, gas, pid, eval_pts) {
  dat <- data.frame(d = gas - lab, m = (gas + lab) / 2, pid = factor(pid))
  r <- list(); st <- list()
  fa <- fit_mixed(d ~ 1 + (1 | pid), dat); st$model_a <- fa$reason
  if (is.null(fa$fit)) { for (k in c("loa_model_center", "loa_model_lo", "loa_model_hi", "sigma2_b", "sigma2_w")) r[[k]] <- NA_real_ } else {
    vc <- as.data.frame(lme4::VarCorr(fa$fit)); sb <- vc$vcov[vc$grp == "pid"]; sw <- vc$vcov[vc$grp == "Residual"]
    ctr <- unname(lme4::fixef(fa$fit)[1]); h <- 1.96 * sqrt(sb + sw)
    r$loa_model_center <- ctr; r$loa_model_lo <- ctr - h; r$loa_model_hi <- ctr + h; r$sigma2_b <- sb; r$sigma2_w <- sw
  }
  fc <- fit_mixed(d ~ m + (1 | pid), dat); st$model_c <- fc$reason
  for (p in eval_pts) {
    k <- format(p, nsmall = 1)
    if (is.null(fc$fit)) { r[[paste0("loa_reg_", k, "_lo")]] <- NA_real_; r[[paste0("loa_reg_", k, "_hi")]] <- NA_real_ } else {
      vc <- as.data.frame(lme4::VarCorr(fc$fit)); h <- 1.96 * sqrt(sum(vc$vcov))
      mu <- unname(lme4::fixef(fc$fit)[1] + lme4::fixef(fc$fit)[2] * p)
      r[[paste0("loa_reg_", k, "_lo")]] <- mu - h; r[[paste0("loa_reg_", k, "_hi")]] <- mu + h
    }
  }
  r <- lapply(r, function(v) if (fin(v)) v else NA_real_)
  attr(r, "status") <- st
  r
}

s6_est <- function(lab, gas, pid) {
  d <- gas - lab; w <- 1 / as.numeric(table(pid)[as.character(pid)])
  r <- list(s6_center = mean(tapply(d, pid, mean)), s6_loa_lo = wq1(d, w, 0.025), s6_loa_hi = wq1(d, w, 0.975))
  lapply(r, function(v) if (fin(v)) v else NA_real_)
}

# ---- cluster bootstrap ----
cluster_boot <- function(dat, fun, B, seed) {
  rows <- split(seq_len(nrow(dat)), as.character(dat$pid)); P <- length(rows)
  set.seed(seed); res <- NULL
  for (b in seq_len(B)) {
    s <- sample.int(P, P, replace = TRUE); idx <- unlist(rows[s], use.names = FALSE)
    newpid <- rep(seq_len(P), lengths(rows[s]))
    v <- unlist(fun(dat[idx, , drop = FALSE], newpid))
    if (is.null(res)) res <- matrix(NA_real_, B, length(v), dimnames = list(NULL, names(v)))
    res[b, names(v)] <- v
  }
  res
}

# "computable" = finite; failures = NA/NaN/Inf; CI not estimable when failures > 1% of B (strictly greater)
ci_from <- function(est, bootcol) {
  ok <- is.finite(bootcol); nf <- sum(!ok)
  if (!fin(est)) return(list(est = NA, lo = NA, hi = NA, n_fail = nf, ci = "not_estimable_in_sample"))
  if (nf > 0.01 * length(bootcol)) return(list(est = est, lo = NA, hi = NA, n_fail = nf, ci = "not_estimable_gt1pct_fail"))
  v <- bootcol[ok]
  list(est = est, lo = q7(v, 0.025), hi = q7(v, 0.975), n_fail = nf, ci = "percentile")
}

# ---- Passing-Bablok (S2) ----
paba_point <- function(x, y) tryCatch({
  f <- mcr::mcreg(x, y, method.reg = "PaBa", method.ci = "analytical", alpha = 0.05)
  v <- c(f@para["Intercept", "EST"], f@para["Slope", "EST"]); if (all(is.finite(v))) v else c(NA_real_, NA_real_)
}, error = function(e) c(NA_real_, NA_real_))

run_paba <- function(x, y, BP, seed) {
  if (length(x) < 3) return(list(status = "not_estimable_in_sample", reason = "fewer than 3 pairs"))
  full <- tryCatch(mcr::mcreg(x, y, method.reg = "PaBa", method.ci = "analytical", alpha = 0.05), error = function(e) NULL)
  est <- if (is.null(full)) c(NA_real_, NA_real_) else c(full@para["Intercept", "EST"], full@para["Slope", "EST"])
  if (!all(is.finite(est))) return(list(status = "not_estimable_in_sample", reason = "point estimate failed or non-finite"))
  set.seed(seed); n <- length(x); bm <- matrix(NA_real_, BP, 2)
  for (b in seq_len(BP)) { i <- sample.int(n, n, replace = TRUE); bm[b, ] <- paba_point(x[i], y[i]) }
  cu <- tryCatch(mcr::calcCUSUM(full), error = function(e) NULL)
  cus <- if (is.null(cu) || !fin(cu$max.cusum)) list(status = "failed") else
    list(status = "ok", max_cusum = cu$max.cusum, nPos = r10(cu$nPos), nNeg = r10(cu$nNeg))
  list(status = "ok", intercept = ci_from(est[1], bm[, 1]), slope = ci_from(est[2], bm[, 2]), cusum = cus,
       note = "Cusum statistic only; no linearity judgement (criterion source unavailable; SAP J2)")
}

# ---- association models (SAP 11) ----
COV_ORDER_DROP <- c("icu", "smin", "spec", "glu", "cre", "plt", "wbc", "ph")

build_design <- function(dat, cov, spline, merge_icu) {
  cc <- dat[stats::complete.cases(dat[, cov, drop = FALSE]), , drop = FALSE]
  if (nrow(cc) == 0) stop("no complete cases")
  if (merge_icu && "icu" %in% cov) { tb <- table(cc$icu); cc$icu[cc$icu %in% names(tb)[tb < 500]] <- "Other" }
  cc$disc <- as.integer(cat3(cc$gas) != cat3(cc$lab)); cc$d <- cc$gas - cc$lab
  cc$pidf <- factor(cc$pid); cc$cidf <- factor(cc$cid)
  terms <- character(0); npar <- 0; env <- new.env()
  for (v in cov) {
    if (v %in% c("spec", "icu")) {
      cc[[v]] <- factor(cc[[v]])
      if (nlevels(cc[[v]]) < 2) stop(paste("single-level factor", v))
      if (v == "spec" && !("ART" %in% levels(cc[[v]]))) stop("reference level ART absent for specimen type")
      ref <- if (v == "spec") "ART" else names(sort(table(cc[[v]]), decreasing = TRUE))[1]  # icu: most frequent (single-variable count)
      cc[[v]] <- stats::relevel(cc[[v]], ref = ref); terms <- c(terms, v); npar <- npar + nlevels(cc[[v]]) - 1
    } else {
      if (!all(is.finite(cc[[v]])) || stats::var(cc[[v]]) == 0) stop(paste("non-finite or zero-variance", v))
      k <- q7(cc[[v]], c(0.1, 0.5, 0.9))
      if (spline && length(unique(k)) == 3) {
        assign(paste0("k_", v), k, envir = env)  # knots passed as exact numbers, no printing/rounding
        terms <- c(terms, sprintf("splines::ns(%s, knots = k_%s[2], Boundary.knots = k_%s[c(1, 3)])", v, v, v)); npar <- npar + 2
      } else { terms <- c(terms, v); npar <- npar + 1 }
    }
  }
  list(cc = cc, rhs = if (length(terms)) paste(terms, collapse = " + ") else "1", npar = npar, env = env)
}

full_rank <- function(rhs, cc, env) {
  X <- stats::model.matrix(stats::as.formula(paste("~", rhs), env = env), cc)
  qr(X)$rank == ncol(X)
}

separated <- function(rhs, cc, env) {
  w <- character(0)
  g <- tryCatch(withCallingHandlers(stats::glm(stats::as.formula(paste("disc ~", rhs), env = env), data = cc, family = stats::binomial),
                warning = function(x) { w <<- c(w, conditionMessage(x)); invokeRestart("muffleWarning") }), error = function(e) NULL)
  if (is.null(g)) return(TRUE)
  # conservative numerical-risk rule (not a proof of separation): glm warns of fitted probabilities 0/1 or
  # non-convergence, or returns non-finite / aliased coefficients. No scale-dependent coefficient-size rule.
  any(grepl("fitted probabilities numerically 0 or 1|did not converge", w)) || !isTRUE(g$converged) ||
    any(!is.finite(stats::coef(g)))
}

coef_table <- function(co) { t <- data.frame(term = rownames(co), est = co[, 1], se = co[, 2], stringsAsFactors = FALSE)
  t$lo <- t$est - 1.96 * t$se; t$hi <- t$est + 1.96 * t$se; rownames(t) <- NULL; t }

assoc <- function(dat, db) {
  cov_all <- c("ph", "wbc", "plt", "cre", "glu", "spec", "smin", if (db == "mimic") "icu")
  isna <- function(v) is.na(dat[[v]]) | (is.character(dat[[v]]) & dat[[v]] %in% c("", NA))
  for (v in c("spec", "icu")) if (v %in% cov_all) dat[[v]][dat[[v]] == ""] <- NA
  miss_n <- sapply(cov_all, function(v) sum(isna(v)))
  cov <- cov_all[miss_n / nrow(dat) <= 0.5]
  res <- list(missing_n = lapply(as.list(miss_n), r10), excluded_gt50pct_missing = as.list(setdiff(cov_all, cov)))
  # complete vs non-complete cases on single-source variables (v0.7 11.8); no function of both potassium values.
  # Reported for the initial candidate set and, separately, for the covariate set of each final fitted main model.
  compare_cc <- function(cvars) {
    ccflag <- if (length(cvars)) stats::complete.cases(dat[, cvars, drop = FALSE]) else rep(TRUE, nrow(dat))
    cmp <- list(covariates = as.list(cvars), n_complete = r10(sum(ccflag)), n_incomplete = r10(sum(!ccflag)))
    for (v in c("lab", "gas", intersect(c("ph", "wbc", "plt", "cre", "glu", "smin"), cov_all))) {
      q <- function(x) { x <- x[is.finite(x)]; if (length(x) < 100) "n_below_100" else as.list(stats::setNames(q7(x, c(0.25, 0.5, 0.75)), c("q25", "q50", "q75"))) }
      cmp[[v]] <- list(complete = q(dat[[v]][ccflag]), incomplete = q(dat[[v]][!ccflag]))
    }
    for (v in intersect(c("spec", "icu"), cov_all)) {
      tc <- table(dat[[v]][ccflag]); ti <- table(dat[[v]][!ccflag])
      cmp[[v]] <- list(complete = lapply(as.list(tc), r10), incomplete = lapply(as.list(ti), r10))
    }
    cmp
  }
  res$complete_vs_incomplete_initial_set <- compare_cc(cov)
  steps <- list(list(sp = TRUE, mg = FALSE, k = 0), list(sp = FALSE, mg = FALSE, k = 0), list(sp = FALSE, mg = TRUE, k = 0))
  for (k in seq_along(COV_ORDER_DROP)) steps[[length(steps) + 1]] <- list(sp = FALSE, mg = TRUE, k = k)
  run_main <- function(kind) {
    trace <- list()
    for (i in seq_along(steps)) {
      st <- steps[[i]]; cv <- setdiff(cov, COV_ORDER_DROP[seq_len(st$k)])
      if (length(cv) == 0) {  # SAP 11.7 step 4: descriptive only, never an intercept-only "association" model
        trace[[i]] <- list(step = i, covariates = list(), result = "no covariates left: descriptive only")
        return(list(status = "no_inference_no_covariates", trace = trace)) }
      # complete-case size and absolute stop thresholds are checked BEFORE building the design (v0.7 11.9)
      ccf <- stats::complete.cases(dat[, cv, drop = FALSE]); sub <- dat[ccf, , drop = FALSE]
      dsub <- as.integer(cat3(sub$gas) != cat3(sub$lab)); disc_pt <- unique(sub$pid[dsub == 1])
      info <- list(step = i, covariates = as.list(cv), n_pairs = r10(nrow(sub)), n_patients = r10(length(unique(sub$pid))),
                   n_discordant_patients = r10(length(disc_pt)))
      if (nrow(sub) < 200 || length(disc_pt) < 50) {
        trace[[i]] <- c(info, result = "complete cases <200 or discordant patients <50: no inference")
        return(list(status = "no_inference_small_sample", trace = trace)) }
      des <- tryCatch(build_design(dat, cv, st$sp, st$mg), error = function(e) conditionMessage(e))
      if (is.character(des)) { trace[[i]] <- c(info, result = paste("design failed:", des)); next }
      cc <- des$cc; p <- max(des$npar, 1); npt <- length(unique(cc$pid))
      nodisc_pt <- setdiff(unique(cc$pid), disc_pt)
      info$n_params <- p
      if (kind == "lmm") { if (npt < 10 * p) { trace[[i]] <- c(info, result = "patients < 10p"); next } } else {
        ev <- min(sum(cc$disc), sum(1 - cc$disc))
        if (ev < 10 * p || length(disc_pt) < 10 * p || length(nodisc_pt) < 10 * p) { trace[[i]] <- c(info, result = "events < 10p"); next } }
      if (!full_rank(des$rhs, cc, des$env)) { trace[[i]] <- c(info, result = "rank deficient"); next }
      if (kind == "gee" && separated(des$rhs, cc, des$env)) { trace[[i]] <- c(info, result = "separation"); next }
      if (kind == "lmm") {
        f <- fit_mixed(stats::as.formula(paste("d ~", des$rhs, "+ (1 | pidf)"), env = des$env), cc)
        if (is.null(f$fit)) { trace[[i]] <- c(info, result = paste("lmm failed:", f$reason)); next }
        trace[[i]] <- c(info, result = paste("fitted", f$reason))
        return(list(status = "fitted", step = i, covariates = as.list(cv), n_pairs = r10(nrow(cc)), n_patients = r10(npt), n_params = p,
                    coefficients = coef_table(summary(f$fit)$coefficients), fit_note = f$reason, trace = trace, des = des,
                    complete_vs_incomplete = compare_cc(cv)))
      } else {
        o <- cc[order(cc$pidf), ]; fml <- stats::as.formula(paste("disc ~", des$rhs), env = des$env); g <- NULL; used <- NA
        for (cs in c("exchangeable", "independence")) {
          g <- tryCatch(geepack::geeglm(fml, id = pidf, data = o, family = stats::binomial, corstr = cs), error = function(e) NULL)
          if (!is.null(g) && g$geese$error == 0) { co <- summary(g)$coefficients; if (all(is.finite(co[, 1])) && all(is.finite(co[, 2]))) { used <- cs; break } }
          g <- NULL }
        if (is.null(g)) { trace[[i]] <- c(info, result = "gee failed (exchangeable and independence)"); next }
        trace[[i]] <- c(info, result = paste("fitted, corstr", used))
        return(list(status = "fitted", step = i, covariates = as.list(cv), corstr = used, n_pairs = r10(nrow(cc)), n_patients = r10(npt),
                    n_params = p, coefficients = coef_table(summary(g)$coefficients), trace = trace, des = des,
                    complete_vs_incomplete = compare_cc(cv)))
      }
    }
    list(status = "no_inference_all_steps_failed", trace = trace)
  }
  sens <- function(main, kind) {  # same covariate set and step as the main model; no separate simplification
    if (main$status != "fitted") return(list(status = "not_run_main_not_fitted"))
    des <- main$des; cc <- des$cc
    if (kind == "glmm" && separated(des$rhs, cc, des$env)) return(list(status = "not_estimable", reason = "separation"))
    f <- if (kind == "s8") fit_mixed(stats::as.formula(paste("d ~", des$rhs, "+ (1 | pidf) + (1 | cidf)"), env = des$env), cc) else
      fit_mixed(stats::as.formula(paste("disc ~", des$rhs, "+ (1 | pidf)"), env = des$env), cc, family = stats::binomial)
    if (is.null(f$fit)) return(list(status = "not_estimable", reason = f$reason,
                                    note = if (kind == "s8") "stay layer dropped = main LMM (v0.7 11.9)" else NULL))
    list(status = "fitted", step = main$step, coefficients = coef_table(summary(f$fit)$coefficients), fit_note = f$reason)
  }
  lmm <- run_main("lmm"); gee <- run_main("gee")
  res$lmm_s8 <- sens(lmm, "s8"); res$glmm <- sens(gee, "glmm")
  lmm$des <- NULL; gee$des <- NULL; res$lmm <- lmm; res$gee <- gee
  res
}
