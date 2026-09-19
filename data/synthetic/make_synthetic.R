# =============================================================================
#  make_synthetic.R
#  ---------------------------------------------------------------------------
#  Purpose   Build a synthetic borrower panel with the same SHAPE as the
#            restricted BAAC panel, so that every script in R/ runs end to end
#            without the real data.
#  Inputs    ../../output/diagnostics/rpb_static.csv   (published correlations,
#            used to calibrate the financial covariates)
#            ../../output/results/cluster_structure_summary.csv (published
#            cluster structure, used to calibrate cell sizes and the ICC)
#  Outputs   panel_synthetic.txt        pipe-delimited, 11 EO channels
#            panel_synthetic_9ch.txt    the same rows without the two SAI
#                                       channels, for the 9-channel scripts
#            two_records_readable.csv   two rows, transposed, for eyeballing
#            synthetic_manifest.txt     what was generated and what it matched
#  Section   Data Availability Statement; Section 2 of the manuscript
#
#  WHAT THIS FILE DOES AND DOES NOT REPRODUCE
#
#  Reproduces, by construction:
#    - the two-level structure: borrowers nested in (ADM3, Year) cells, with
#      every borrower in a cell receiving an IDENTICAL environmental sequence.
#      This is the property the whole paper turns on.
#    - the cell-size distribution, including the small cells.
#    - the intracluster correlation of default.
#    - the persistence of cell-level risk across years.
#    - the marginal point-biserial correlation of each financial covariate with
#      default, read from the published diagnostics.
#    - the column names, ordering, delimiter and rounding of the real file.
#
#  Does NOT reproduce:
#    - any real borrower, sub-district, or measurement. The ADM3 codes are
#      sequential integers and correspond to nothing.
#    - the joint dependence among financial covariates. Each is calibrated to
#      its own marginal correlation with default and is otherwise independent,
#      so a model fitted here will not reach the AUC reported in the paper.
#      The purpose is that the code RUNS and that its structural conclusions
#      (the areal ceiling, the constancy of EO within a cell) are visible, not
#      that the numbers match.
#    - the areal ceiling of 0.66223. That value depends on the real cell sizes
#      and the real outcome; at SCALE < 1 you will get a different, larger
#      number, because smaller cells are easier to separate. See the manifest.
# =============================================================================

set.seed(20260916)

# ------------------------------------------------------------------ scale ---
# 1.0 reproduces the real panel: 6,236 sub-districts, ~4.49M rows, several GB.
# 0.02 is the default and gives ~90k rows in a ~85 MB file.
#
# The generated panel is NOT committed to the repository -- .gitignore excludes
# panel_synthetic*.txt, because even at the default scale the file exceeds what
# belongs in git. Run this script once after cloning; it takes under a minute.
SCALE <- as.numeric(Sys.getenv("SYNTH_SCALE", "0.02"))

OUT_11 <- "panel_synthetic.txt"
OUT_9  <- "panel_synthetic_9ch.txt"

# ------------------------------------------------- published targets --------
# Read from the repository's own published output so the generator and the
# paper cannot drift apart. Falls back to the literals if the files are absent.
read_published <- function(path, fallback) {
  if (file.exists(path)) read.csv(path, stringsAsFactors = FALSE) else fallback
}
rpb <- read_published(
  "../../output/diagnostics/rpb_static.csv",
  data.frame(feature = character(0), r_pb = numeric(0))
)
if (nrow(rpb) == 0) stop("rpb_static.csv not found: run from data/synthetic/")

N_ADM3_FULL <- 6236
ICC_TARGET  <- 0.0517
MEAN_CELL   <- 240.8
MAX_CELL    <- 1528
P_DEV       <- 0.0570   # default rate, years 1 and 2
P_TEST      <- 0.1207   # default rate, year 3 (the withheld season)
RHO_PERSIST <- sqrt(0.922)   # 92.2 percent of areal signal is persistent

N_ADM3 <- max(60L, as.integer(round(N_ADM3_FULL * SCALE)))
YEARS  <- 1:3

cat(sprintf("SCALE %.3f -> %d sub-districts, 3 years\n", SCALE, N_ADM3))

# ------------------------------------------------------- cell sizes ---------
# A two-part mixture, not a single lognormal. A plain lognormal matched to the
# mean and median of the real panel puts its 10th percentile near 90 borrowers
# and never produces a small cell, which would quietly remove the reason the
# leave-one-out correction in R/ceiling/ exists at all. In the real panel
# 10.1 percent of cells hold fewer than ten borrowers and 2.4 percent hold
# exactly one. So: a small-cell component on 1..9, and a lognormal for the rest.
SMALL_FRAC <- 0.101
sdlog   <- sqrt(2 * log(267.5 / 215))
meanlog <- log(215)
cell_n  <- matrix(0L, nrow = N_ADM3, ncol = length(YEARS))
for (y in YEARS) {
  is_small <- runif(N_ADM3) < SMALL_FRAC
  raw <- numeric(N_ADM3)
  raw[is_small]  <- sample(1:9, sum(is_small), replace = TRUE,
                           prob = (1:9)^-0.9)
  raw[!is_small] <- pmin(pmax(round(rlnorm(sum(!is_small), meanlog, sdlog)), 10),
                         MAX_CELL)
  cell_n[, y] <- as.integer(raw)
}

# --------------------------------------------- cell default probabilities ---
# Beta marginals give the exact ANOVA ICC on the 0/1 scale:
#   ICC = Var(p_cell) / (pbar * (1 - pbar))
# A Gaussian copula ties the three years together so that most of the areal
# signal is persistent geography rather than a year-specific departure.
#
# One subtlety that is easy to get wrong. ICC_TARGET is the intracluster
# correlation of the WHOLE panel, and the three years do not share a default
# rate: 5.70 percent in the development years against 12.07 percent in the
# withheld season. That between-year spread is itself between-cell variance,
# so setting the within-year ICC to the target overshoots it. Solve for the
# within-year value that makes the pooled quantity come out at the target:
#
#   Var_total(p) = E_y[icc_w * m_y(1-m_y)] + Var_y(m_y)  =  ICC * pbar(1-pbar)
#
m_y   <- c(P_DEV, P_DEV, P_TEST)
pbar0 <- mean(m_y)
icc_w <- (ICC_TARGET * pbar0 * (1 - pbar0) - mean((m_y - pbar0)^2)) /
         mean(m_y * (1 - m_y))
if (icc_w <= 0) stop("target ICC is smaller than the between-year variance alone")
cat(sprintf("within-year ICC %.4f -> pooled ICC %.4f\n", icc_w, ICC_TARGET))

beta_ab <- function(m, icc) {
  v <- icc * m * (1 - m)
  k <- m * (1 - m) / v - 1
  c(a = m * k, b = (1 - m) * k)
}
u_geo <- rnorm(N_ADM3)
p_cell <- matrix(0, nrow = N_ADM3, ncol = length(YEARS))
for (y in YEARS) {
  m  <- if (y == 3) P_TEST else P_DEV
  ab <- beta_ab(m, icc_w)
  z  <- RHO_PERSIST * u_geo + sqrt(1 - RHO_PERSIST^2) * rnorm(N_ADM3)
  p_cell[, y] <- qbeta(pnorm(z), ab["a"], ab["b"])
}

# ------------------------------------------------------- the panel ----------
adm3_id <- seq_len(N_ADM3) + 100000L
rows_adm3 <- rep(rep(adm3_id, times = length(YEARS)), times = as.vector(cell_n))
rows_year <- rep(rep(YEARS, each = N_ADM3),           times = as.vector(cell_n))
rows_p    <- rep(as.vector(p_cell),                   times = as.vector(cell_n))
N <- length(rows_adm3)
Y <- rbinom(N, 1L, rows_p)

cat(sprintf("rows %s | cells %d | default rate %.4f\n",
            format(N, big.mark = ","), N_ADM3 * length(YEARS), mean(Y)))

# --------------------------------------- financial covariates (calibrated) --
# x = r * standardised(Y) + sqrt(1 - r^2) * noise  gives cor(x, Y) = r exactly
# in expectation, which is the quantity rpb_static.csv reports. Everything is
# then min-max scaled to [0, 1] and rounded to 4 dp, as the real pipeline does.
pbar <- mean(Y)
Ystd <- (Y - pbar) / sqrt(pbar * (1 - pbar))
minmax <- function(v) {
  rg <- range(v, na.rm = TRUE)
  if (diff(rg) == 0) return(rep(0, length(v)))
  round((v - rg[1]) / diff(rg), 4)
}

TE_COLS  <- c("TE_ADM3", "TE_IDProv_rice", "TE_ADM3RL", "TE_IDProv_RL", "TE_IDDT")
fin_rows <- rpb[!rpb$feature %in% TE_COLS, ]
cat(sprintf("financial covariates: %d\n", nrow(fin_rows)))

static <- list()
for (i in seq_len(nrow(fin_rows))) {
  r <- max(min(fin_rows$r_pb[i], 0.95), -0.95)
  x <- r * Ystd + sqrt(1 - r^2) * rnorm(N)
  static[[fin_rows$feature[i]]] <- minmax(x)
}

# Binary covariates stay binary.
for (b in c("Has_Credit_History", "Previous_Default", "IDRV_4", "IDRV_5")) {
  if (!is.null(static[[b]])) static[[b]] <- as.integer(static[[b]] > median(static[[b]]))
}

# ------------------------------------------------ target encodings ----------
# Fitted on years 1-2 ONLY and applied unchanged to year 3, exactly as
# R/prep/ does on the real panel. Additive Bayesian smoothing, prior weight 20.
dev <- rows_year %in% c(1, 2)
prior <- mean(Y[dev]); PRIOR_W <- 20

te_from <- function(key) {
  agg <- tapply(Y[dev], key[dev], function(v) (sum(v) + prior * PRIOR_W) / (length(v) + PRIOR_W))
  out <- as.numeric(agg[as.character(key)])
  out[is.na(out)] <- prior
  round(out, 6)
}
# Auxiliary categoricals. Province is coarser than ADM3; RL (residence) and DT
# (land-document type) are not geographic.
prov <- (rows_adm3 - 100000L) %% 77L + 1L
RL   <- sample.int(4L, N, replace = TRUE)
DT   <- sample.int(64L, N, replace = TRUE)

static[["TE_ADM3"]]        <- te_from(rows_adm3)
static[["TE_IDProv_rice"]] <- te_from(prov)
static[["TE_ADM3RL"]]      <- te_from(paste(rows_adm3, RL, sep = "_"))
static[["TE_IDProv_RL"]]   <- te_from(paste(prov, RL, sep = "_"))
static[["TE_IDDT"]]        <- te_from(DT)

# ------------------------------------------------ EO tensor -----------------
# THE STRUCTURAL POINT OF THIS FILE. One sequence per (ADM3, Year) cell,
# broadcast to every borrower in it. 11 channels x 8 months = 88 columns.
CH_9  <- c("norm_NDVI", "norm_NDWI", "norm_LST", "norm_Precipitation",
           "norm_SMAP", "norm_log_NTL", "norm_VHI", "norm_Rainfall_Deficit",
           "norm_Heat_Stress_Days")
CH_SAI <- c("norm_SAI_NDVI", "norm_SAI_NDWI")
MONTHS <- 5:12

cell_key  <- (rows_year - 1L) * N_ADM3 + match(rows_adm3, adm3_id)
p_flat    <- as.vector(p_cell)
p_z       <- scale(qnorm(pmin(pmax(p_flat, 1e-6), 1 - 1e-6)))[, 1]
n_cells   <- length(p_flat)

seq_cols <- list()
for (ch in c(CH_9, CH_SAI)) {
  # A weak, smooth cell-level relationship with risk, plus a seasonal profile.
  base <- 0.15 * p_z + sqrt(1 - 0.15^2) * rnorm(n_cells)
  for (m in MONTHS) {
    season <- sin(2 * pi * (m - 4) / 12)
    v <- base * 0.8 + season * 0.3 + rnorm(n_cells, 0, 0.4)
    seq_cols[[paste0(ch, m)]] <- minmax(v)[cell_key]
  }
}

# ------------------------------------------------ assemble and write --------
ID <- sprintf("SYN%08d", seq_len(N))
df <- data.frame(ID = ID, Year = rows_year, Y = Y, ADM3 = rows_adm3,
                 stringsAsFactors = FALSE)
df <- cbind(df, as.data.frame(static, check.names = FALSE))
df <- cbind(df, as.data.frame(seq_cols, check.names = FALSE))

write.table(df, OUT_11, sep = "|", row.names = FALSE, quote = FALSE, fileEncoding = "UTF-8")
sai_cols <- grep("^norm_SAI_", names(df))
write.table(df[, -sai_cols], OUT_9, sep = "|", row.names = FALSE, quote = FALSE,
            fileEncoding = "UTF-8")

two <- t(df[c(1, which(df$Y == 1)[1]), ])
write.csv(data.frame(column = rownames(two), record_1 = two[, 1], record_2 = two[, 2]),
          "two_records_readable.csv", row.names = FALSE)

# ------------------------------------------------ verify and report ---------
# Recompute the published quantities on the synthetic panel and write them out,
# so anyone can see how far the synthetic sits from the real panel.
cs   <- table(cell_key)
nvec <- as.integer(cs)
kvec <- as.integer(tapply(Y, cell_key, sum))
n0   <- (N - sum(nvec^2) / N) / (length(nvec) - 1)
pb   <- mean(Y)
msb  <- sum(nvec * (kvec / nvec - pb)^2) / (length(nvec) - 1)
msw  <- sum(kvec * (1 - kvec / nvec)^2 + (nvec - kvec) * (kvec / nvec)^2) / (N - length(nvec))
icc  <- (msb - msw) / (msb + (n0 - 1) * msw)

first_seq <- min(grep(paste0("^", CH_9[1]), names(df)))
manifest <- c(
  sprintf("generated            %s", Sys.time()),
  sprintf("SCALE                %.3f", SCALE),
  sprintf("rows                 %d", N),
  sprintf("cells                %d", length(nvec)),
  sprintf("sub-districts        %d", N_ADM3),
  sprintf("mean / median cell   %.1f / %.0f", mean(nvec), median(nvec)),
  sprintf("cells with n < 10    %d (%.1f%%)", sum(nvec < 10), 100 * mean(nvec < 10)),
  sprintf("default rate         %.4f  (real: 0.0782)", pb),
  sprintf("ICC                  %.4f  (real: %.4f)", icc, ICC_TARGET),
  sprintf("design effect        %.2f  (real: 13.41)", 1 + (n0 - 1) * icc),
  sprintf("columns              %d", ncol(df)),
  sprintf("first sequence col   %d  (%s)", first_seq, names(df)[first_seq]),
  "",
  "NOTE ON POSITIONAL COLUMN SELECTION",
  "R/collapse/sequence.r selects sequence columns as all_cols[42:113]. That",
  "index is correct for the real 9-channel file and is NOT correct here. Select",
  "by name instead; the column order of this file is documented in",
  "data/schema/codebook.md."
)
writeLines(manifest, "synthetic_manifest.txt")
cat(paste(manifest, collapse = "\n"), "\n")
