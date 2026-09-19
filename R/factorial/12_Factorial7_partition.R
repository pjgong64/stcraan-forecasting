# =============================================================================
#  12_Factorial7_partition.R
#  ---------------------------------------------------------------------------
#  Settles, by measurement, how each target-encoding column's partition relates
#  to the ADM3 partition. Three possible answers per column:
#
#    COARSER / EQUAL  constant within every (ADM3, Year) cell
#                     -> bounded by the 0.662 ADM3 ceiling. Belongs in SP.
#    FINER            splits ADM3 cells, and every one of its own groups sits
#                     inside a single ADM3  -> a strict refinement of ADM3.
#                     Its own ceiling is ABOVE 0.662.
#    CROSSCUTTING     splits ADM3 cells AND at least one of its groups spans
#                     more than one ADM3 -> neither finer nor coarser.
#
#  Run time: seconds.   Rscript 12_Factorial7_partition.R
# =============================================================================

suppressPackageStartupMessages(library(data.table))
source("12_Factorial7_config.R")

sep_use <- if (is.null(CFG$sep)) "|" else CFG$sep

# a sample of EO columns gets the same treatment: if ANY of them varies inside a
# cell, EO is not areal and the premise of both papers is wrong.
hdr    <- names(fread(CFG$data_file, sep = sep_use, nrows = 1L))
eo_all <- unlist(lapply(c(CFG$eo_prefix, CFG$eo_prefix_anomaly),
                        function(b) hdr[startsWith(hdr, b)]))
eo_all <- eo_all[grepl("[0-9]$", eo_all)]
eo_chk <- if (length(eo_all) > 12) eo_all[round(seq(1, length(eo_all), length.out = 12))] else eo_all

cols <- unique(c(CFG$col_id, CFG$col_adm3, CFG$col_year, CFG$col_target,
                 CFG$sp_cols, eo_chk))
cols <- cols[cols %in% hdr]
d <- fread(CFG$data_file, sep = sep_use, select = cols)

cat("\nrows:", nrow(d), "  distinct ADM3:", uniqueN(d[[CFG$col_adm3]]), "\n")

# ---- do the configured years actually exist in the file? --------------------
yv <- sort(unique(d[[CFG$col_year]]))
cat("distinct", CFG$col_year, "values in the file:", paste(yv, collapse = ", "), "\n")
n_dev <- sum(d[[CFG$col_year]] %in% CFG$dev_years)
n_tst <- sum(d[[CFG$col_year]] %in% CFG$test_years)
cat(sprintf("CFG$dev_years  = %s  -> %d rows\n", paste(CFG$dev_years, collapse=","), n_dev))
cat(sprintf("CFG$test_years = %s  -> %d rows\n", paste(CFG$test_years, collapse=","), n_tst))
if (n_dev == 0L || n_tst == 0L) {
  cat("\n*** CFG$dev_years / CFG$test_years DO NOT MATCH THE FILE ***\n")
  cat("    The year values in this file are listed above. Set CFG$dev_years and\n")
  cat("    CFG$test_years to the values that are actually there before running\n")
  cat("    anything else -- the factorial splits dev/test on exactly this test,\n")
  cat("    so every arm would be built on the wrong rows.\n")
}
cat("\n")
cat(sprintf("%-16s %10s %10s %10s   %s\n",
            "column", "n_groups", "max/cell", "max_ADM3", "verdict"))
cat(strrep("-", 74), "\n")

for (v in c(CFG$sp_cols, eo_chk)) {
  if (!v %in% names(d)) { cat(sprintf("%-16s  *** not in file ***\n", v)); next }

  # how many distinct values of v coexist inside one (ADM3, Year) cell?
  per_cell <- d[, .(k = uniqueN(get(v))), by = c(CFG$col_adm3, CFG$col_year)]
  max_cell <- max(per_cell$k)

  # how many distinct ADM3 does one value of v span?
  per_val <- d[, .(k = uniqueN(get(CFG$col_adm3))), by = v]
  max_adm3 <- max(per_val$k)

  verdict <-
    if (max_cell == 1L)                     "COARSER/EQUAL  -> SP, bounded by 0.662"
    else if (max_adm3 == 1L)                "FINER          -> refines ADM3, ceiling > 0.662"
    else                                    "CROSSCUTTING   -> neither finer nor coarser"

  cat(sprintf("%-16s %10d %10d %10d   %s\n",
              v, nrow(per_val), max_cell, max_adm3, verdict))
}

# =============================================================================
#  Was any target encoding refitted per year?
#  ---------------------------------------------------------------------------
#  Section 2.3 states every parameter was estimated on 2020-2021 alone. If a
#  column was refitted per year instead, its 2022 values carry 2022 outcomes and
#  the arm containing it is contaminated.
#
#  Counting distinct values per ADM3 across years ONLY works for a column that
#  is constant within ADM3 to begin with. For TE_ADM3RL / TE_IDProv_RL /
#  TE_IDDT it does not: those vary between borrowers inside one sub-district
#  anyway, so borrower variation and year variation are indistinguishable that
#  way. Two tests that do separate them, neither needing the raw category:
#
#    (a) value-set reuse. A single dev-fitted map means the values seen in 2022
#        are the SAME numbers seen in 2020-21. A per-year refit produces a fresh
#        set of numbers, so reuse collapses toward zero.
#    (b) per-borrower stability. A borrower's sub-district, residence and land
#        document rarely change. Under one map their encoded value is identical
#        in every year they appear; under a refit it moves almost every time.
# =============================================================================
cat("\n=================== TE FITTING WINDOW ===================\n")

dev_y <- CFG$dev_years; tst_y <- CFG$test_years
yr <- d[[CFG$col_year]]
cat(sprintf("dev years %s   test years %s\n",
            paste(dev_y, collapse = ","), paste(tst_y, collapse = ",")))
cat(sprintf("%-16s %12s %12s %10s   %s\n",
            "column", "val reuse", "row reuse", "ID stable", "verdict"))
cat(strrep("-", 78), "\n")

for (v in intersect(CFG$sp_cols, names(d))) {
  x <- signif(as.numeric(d[[v]]), 12)

  set_dev <- unique(x[yr %in% dev_y])
  x_tst   <- x[yr %in% tst_y]
  set_tst <- unique(x_tst)

  val_reuse <- if (length(set_tst)) mean(set_tst %in% set_dev) else NA_real_
  row_reuse <- if (length(x_tst))   mean(x_tst   %in% set_dev) else NA_real_

  # (b) borrowers seen in more than one year
  id_stable <- NA_real_
  if (CFG$col_id %in% names(d)) {
    # uniqueN() by 1.5M groups takes ~2 min; sorting once and comparing
    # neighbours does the same job in seconds.
    idt <- data.table(.id = d[[CFG$col_id]], .v = x, .y = yr)
    setorder(idt, .id, .v)
    per <- idt[, .(ny = uniqueN(.y), nv = sum(c(TRUE, .v[-1] != .v[-.N]))), by = .id]
    per <- per[ny > 1L]
    if (nrow(per)) id_stable <- mean(per$nv == 1L)
  }

  # The verdict rests on row reuse ALONE. id_stable is reported as supporting
  # evidence only: it also drops when borrowers genuinely change sub-district,
  # residence or land document between years, so a low value is not by itself
  # evidence of a refit. Verified on synthetic data where the answer is known:
  # a single map gives row reuse 100.0%, a per-year refit gives 0.0%.
  verdict <-
    if (is.na(row_reuse))         "no test rows"
    else if (row_reuse >= 0.99)   "OK    one dev-fitted map"
    else if (row_reuse <= 0.20)   "*** REFIT PER YEAR -- contaminated ***"
    else                          "CHECK partial reuse, inspect by hand"

  fmt <- function(z) if (is.na(z)) "     n/a" else sprintf("%7.1f%%", 100 * z)
  cat(sprintf("%-16s %12s %12s %10s   %s\n",
              v, fmt(val_reuse), fmt(row_reuse), fmt(id_stable), verdict))
}

lab <- function(z) {
  if (!is.null(CFG$year_labels)) {
    k <- CFG$year_labels[as.character(z)]
    if (!anyNA(k)) return(paste(k, collapse = "/"))
  }
  paste(z, collapse = "/")
}
cat(sprintf("\n  val reuse  share of DISTINCT %s values that also occur in %s\n",
            lab(tst_y), lab(dev_y)))
cat(sprintf("  row reuse  share of %s ROWS whose value occurs in %s. This is the\n",
            lab(tst_y), lab(dev_y)))
cat("             one that decides: a single map reuses every value, so it sits\n")
cat("             at 100%. A per-year refit mints new numbers and it collapses.\n")
cat("  ID stable  among borrowers appearing in more than one year, the share\n")
cat("             whose value never changes. SUPPORTING EVIDENCE ONLY -- it also\n")
cat("             falls when borrowers genuinely change sub-district, residence\n")
cat("             or land document, so a low value here with row reuse at 100%\n")
cat("             means people moved, not that the encoding was refitted.\n")
cat("\n  Only TE_ADM3 and TE_IDProv_rice feed SPA, and SPA is what the 0.662\n")
cat("  falsification test rests on. The other three sit in SP and FIN, where a\n")
cat("  refit would inflate F+SP and F without touching the ceiling test.\n\n")

cat("\nReading the table:\n")
cat("  max/cell = 1  the column cannot distinguish two borrowers in the same\n")
cat("                sub-district and season. That is what 'areal at ADM3' means.\n")
cat("  max_ADM3 = 1  every group of this column lies inside one sub-district, so\n")
cat("                the column is ADM3 subdivided -- a strictly finer grid.\n")
cat("  both > 1      the column's groups cut across sub-district boundaries. It\n")
cat("                is a different partition, not a finer or coarser one, and\n")
cat("                the 0.662 figure says nothing about it either way.\n\n")
cat("NOTE on collisions -- read this before trusting the verdict column.\n")
cat("These are target ENCODINGS, so two distinct categories can land on one\n")
cat("numeric value. That merges groups, and merging affects the two counts in\n")
cat("OPPOSITE directions:\n")
cat("  max/cell  can only go DOWN. So max/cell > 1 is solid evidence: the column\n")
cat("            really is not areal at ADM3, whatever the collisions.\n")
cat("  max_ADM3  can only go UP, because a merged value now spans every\n")
cat("            sub-district its constituents came from. So a large max_ADM3\n")
cat("            is NOT evidence of crosscutting -- a genuinely FINER column\n")
cat("            with heavy collision reports CROSSCUTTING here.\n")
cat("Compare n_groups against the number of categories you expect. Far fewer\n")
cat("distinct values than categories means heavy collision, and then FINER vs\n")
cat("CROSSCUTTING cannot be settled from the encoded column at all -- only from\n")
cat("the raw categorical column, if it still exists.\n\n")
