# =============================================================================
#  12_Factorial7_report.R
#  ---------------------------------------------------------------------------
#  Reads factorial7_results.csv and prints everything the paper needs. Reads
#  only -- it never trains, never writes to the results file, and does not care
#  whether a run is still going. Safe to call from a second terminal while the
#  grid is running.
#
#      Rscript 12_Factorial7_report.R           # everything finished so far
#      Rscript 12_Factorial7_report.R XGB       # one family
#      Rscript 12_Factorial7_report.R --short   # just the AUC matrix
#
#  run.R sources this file at the end, so there is one implementation of the
#  summary and the two can never drift apart.
# =============================================================================

# data.table is loaded UNCONDITIONALLY. It used to sit inside the
# `if (!exists("CFG"))` block below, which meant that sourcing this file in a
# session where CFG already existed -- but the package was not attached -- got
# the helpers without fread/rbindlist/dcast, and failed at the first read with
# "could not find function rbindlist". Whether a config object happens to be in
# the environment says nothing about whether the package is loaded.
suppressPackageStartupMessages(library(data.table))
if (!exists("CFG")) source("12_Factorial7_config.R")
if (!exists("RES_FILE"))
  RES_FILE <- file.path(CFG$out_dir, "factorial7_results.csv")

# ---------------------------------------------------------------------------
#  The AUC matrix, rendered as text so the three kinds of "no number" are
#  distinguishable. A bare NA hides the difference between a cell that has not
#  run, one that failed, and one that does not exist -- and the reader cannot
#  tell whether to wait, to fix something, or to stop looking.
# ---------------------------------------------------------------------------
NOT_RUN <- "."          # queued, nothing wrong
FAILED_ <- "FAIL"       # attempted and errored; see factorial7_errors.log
NOT_DEF <- "-"          # not defined for this family (ST-CRAAN without EO)

auc_matrix <- function(res, families = CFG$families, arms = names(CFG$arms)) {
  m <- matrix(NOT_RUN, nrow = length(arms), ncol = length(families),
              dimnames = list(arms, families))
  for (f in families) {
    ok_arms <- if (f == "STCRAAN") intersect(arms, CFG$stcraan_arms) else arms
    m[setdiff(arms, ok_arms), f] <- NOT_DEF
  }
  if (!is.null(res) && nrow(res)) for (i in seq_len(nrow(res))) {
    a <- as.character(res$arm[i]); f <- as.character(res$family[i])
    if (!a %in% arms || !f %in% families) next
    v <- res$auc_test[i]
    m[a, f] <- if (!is.na(v)) sprintf("%.5f", v) else FAILED_
  }
  data.table(arm = arms, as.data.table(m))
}

auc_matrix_legend <- function()
  cat(sprintf("\n  %s = not run yet   %s = attempted and errored   %s = not defined for that family\n",
              NOT_RUN, FAILED_, NOT_DEF))

# exists() first: running this file standalone (Rscript 12_Factorial7_report.R)
# leaves .defs_only undefined, and isTRUE() on an undefined name is an error,
# not FALSE.
if (exists(".defs_only") && isTRUE(.defs_only)) {
  # run.R sources this early just for the helpers above; everything below is
  # output and must not fire yet.
} else {

rep_args <- if (exists(".report_sourced")) character(0) else commandArgs(trailingOnly = TRUE)
short    <- any(rep_args %in% c("--short", "-s"))
fam_filt <- setdiff(rep_args, c("--short", "-s"))

# A locked results file (Excel on Windows) makes the runner park rows in
# pending shards. They are part of the results, so read them here too.
.shards <- list.files(CFG$out_dir,
                      pattern = "^factorial7_results\\.pending-.*\\.csv$",
                      full.names = TRUE)
.files  <- c(if (file.exists(RES_FILE)) RES_FILE, .shards)

if (!length(.files)) {
  cat("\nno results yet at", RES_FILE, "\n")
  cat("Nothing has finished. Start the grid with:  Rscript 12_Factorial7_run.R XGB\n\n")
} else {

if (length(.shards))
  cat(sprintf("\n(reading %d pending shard(s) alongside the main file -- close\n Excel and rerun the grid once to fold them in)\n", length(.shards)))
# colClasses matters here: one arm is named "F", and fread auto-detects a
# column of "T"/"F" as logical, which would turn that arm into FALSE.
res <- rbindlist(lapply(.files, function(f)
         fread(f, colClasses = list(character = c("family", "arm", "note")))),
       use.names = TRUE, fill = TRUE)
res[, family := as.character(family)][, arm := as.character(arm)]
res <- res[!duplicated(paste(family, arm), fromLast = TRUE)]
if (length(fam_filt)) res <- res[family %in% fam_filt]

# ---------------------------------------------------------------- progress --
all_cells <- unlist(lapply(CFG$families, function(f) {
  a <- names(CFG$arms)
  if (f == "STCRAAN") a <- intersect(a, CFG$stcraan_arms)
  paste(f, a, sep = "|")
}))
have   <- paste(res$family, res$arm, sep = "|")
is_fail <- (!is.na(res$note) & grepl("^FAILED", res$note)) | is.na(res$auc_test)
failed  <- paste(res$family, res$arm, sep = "|")[is_fail]
cat(sprintf("\n%d of %d cells finished", length(setdiff(have, failed)), length(all_cells)))
if (length(failed)) cat(sprintf(", %d FAILED", length(failed)))
if (nrow(res)) cat(sprintf(" | total fit time %.1f h", sum(res$secs, na.rm = TRUE) / 3600))
cat("\n")

# Every cell failing prints a matrix of NA and explains nothing, so surface the
# reasons first. They are the actual answer whenever the matrix is all NA.
if (any(is_fail)) {
  cat("\n================ FAILURES -- READ THESE FIRST ================\n")
  ff <- res[is_fail, .(family, arm, why = substr(note, 1, 160))]
  print(ff, right = FALSE)
  elog <- file.path(CFG$out_dir, "factorial7_errors.log")
  if (file.exists(elog)) cat("\n  full messages:", elog, "\n")
  if (all(is_fail)) {
    cat("\n  EVERY cell failed, so this is one shared cause, not 28 separate\n")
    cat("  ones. Check first that 12_Factorial7_config.R is the version that\n")
    cat("  goes with 12_Factorial7_run.R: the fit functions read CFG$hp, and an\n")
    cat("  older config without it makes every hyper-parameter NULL, which each\n")
    cat("  library rejects at fit time. Then check the library is installed at\n")
    cat("  all -- h2o for LR/RF, xgboost for XGB, keras for MLP/ST-CRAAN.\n")
  }
}

if (!nrow(res)) {
  cat("\nno rows match", if (length(fam_filt)) paste(fam_filt, collapse = ", ") else "",
      "-- nothing to report.\n\n")
} else {

# ---------------------------------------------------------------- matrix ----
cat("\n================ TEST AUC BY ARM AND FAMILY ================\n")
print(auc_matrix(res), row.names = FALSE)
auc_matrix_legend()
wide <- dcast(res, arm ~ family, value.var = "auc_test")   # numeric, for the CSV
setcolorder(wide, c("arm", intersect(CFG$families, names(wide))))
wide <- wide[match(intersect(names(CFG$arms), wide$arm), arm)]

if (!short) {

# ------------------------------------------------------- dev vs test gap ----
cat("\n================ DEV vs TEST (how much survives the year change) ========\n")
g <- res[!is.na(auc_test), .(family, arm, dev = auc_dev, test = auc_test,
                             drop = auc_dev - auc_test,
                             min = round(secs / 60, 1))]
setorder(g, family, -test)
print(g, digits = 5)

# ---------------------------------------------------------------- deltas ----
cat("\n================ WHAT EACH BLOCK IS WORTH (test AUC delta) ================\n")
pairs <- list(c("F", "F+SP"), c("F", "F+EO"), c("F+SP", "F+SP+EO"),
              c("SPA", "EO+SPA"), c("SPA", "SP"))
# NB: not called "note" -- that is a column in res, and inside a data.table
# expression the column would win.
delta_note <- c("what location adds", "what EO adds to FIN alone",
                "what EO adds once location is held",
                "what EO adds to areal history", "what sub-ADM3 location adds")
for (fam in intersect(CFG$families, unique(res$family))) {
  shown <- FALSE
  for (i in seq_along(pairs)) {
    p <- pairs[[i]]
    a <- res[family == fam & arm == p[1], auc_test]
    b <- res[family == fam & arm == p[2], auc_test]
    if (length(a) && length(b) && !is.na(a) && !is.na(b)) {
      cat(sprintf("  %-8s %-9s -> %-9s  %+.5f   %s\n",
                  fam, p[1], p[2], b - a, delta_note[i])); shown <- TRUE
    }
  }
  if (shown) cat("\n")
}
cat("  The third line is the one Section 5.2 turns on.\n")

# ---------------------------------------------------------------- alerts ----
{
  rc <- grep("^(recall_a|fn_a)", names(res), value = TRUE)
  if (length(rc)) {
    cat("\n================ AT MATCHED ALERT VOLUME ================\n")
    print(res[!is.na(auc_test), c("family", "arm", rc), with = FALSE], digits = 4)
  }
}

# ---------------------------------------------------------------- anchors ---
cat("\n================ CONSISTENCY WITH THE ESTABLISHED ANCHORS ================\n")
best <- function(a) {
  v <- res[arm == a & !is.na(auc_test), auc_test]
  if (length(v)) max(v) else NA_real_
}
chk <- function(label, got, want, tol) {
  if (is.na(got)) { cat(sprintf("  %-34s  not run yet\n", label)); return(invisible()) }
  cat(sprintf("  %-34s got %.5f  anchor %.5f  %s\n", label, got, want,
              if (abs(got - want) <= tol) "PASS" else "CHECK"))
}
chk("EO-only vs prior EO forecaster",   best("EO"),      CFG$anchor$eo_only_test,    0.02)
chk("SPA-only vs sub-district history", best("SPA"),     CFG$anchor$sp_history_test, 0.02)
if (!is.na(best("F")))
  cat(sprintf("  %-34s got %.5f  prior %.5f  (the prior run included the\n",
              "F-only vs old static-only run", best("F"), CFG$anchor$fin_only_test))
cat("                                     spatial encodings, so a LOWER value\n")
cat("                                     here is the expected result)\n")
chk("F+SP+EO vs strongest benchmark",   best("F+SP+EO"), CFG$anchor$xgb_full_test,   0.02)

cat("\n  --- falsification test of the areal ceiling ---\n")
eosp <- best("EO+SPA")
if (is.na(eosp)) {
  cat("  EO+SPA has not run yet. This is the one result that can invalidate\n")
  cat("  both papers, so run it before drawing any conclusion from the rest.\n")
} else if (eosp <= CFG$anchor$areal_ceiling_test + 0.005) {
  cat(sprintf("  EO+SPA = %.5f  <=  ceiling %.5f   PASS: the bound holds\n",
              eosp, CFG$anchor$areal_ceiling_test))
} else {
  cat(sprintf("  EO+SPA = %.5f  >   ceiling %.5f   *** FAILS ***\n",
              eosp, CFG$anchor$areal_ceiling_test))
  cat("  A predictor built only from (ADM3, Year) information cannot beat the\n")
  cat("  leave-one-out oracle. Either a borrower-level feature leaked into the\n")
  cat("  EO or SPA block, or the ceiling in 11_ is wrong. Resolve before writing.\n")
}

if (any(res$family == "STCRAAN" & !is.na(res$auc_test))) {
  cat("\n  --- ST-CRAAN branch health (a dead branch is not evidence about EO) ---\n")
  print(res[family == "STCRAAN", .(arm, auc_test, note)])
}

}  # !short

.mx <- file.path(CFG$out_dir, "factorial7_matrix_testAUC.csv")
if (isTRUE(tryCatch({ fwrite(wide, .mx); TRUE }, error = function(e) FALSE)))
  cat(sprintf("\nmatrix written to %s\n\n", .mx))
else
  cat(sprintf("\ncould not write %s (open in Excel?) -- the table above is\nthe same content.\n\n", .mx))
}  # nrow(res)
}  # file.exists

}  # .defs_only
