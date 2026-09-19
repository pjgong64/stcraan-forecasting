# =============================================================================
#  00_paths.R   --   every file path the analysis uses, in one place.
#  ---------------------------------------------------------------------------
#  Source this at the top of any script in R/ and refer to PATHS$<name>. The
#  point is that a reader can run the whole repository against the synthetic
#  panel by changing one line, instead of editing a hard-coded filename in each
#  of fifteen scripts and missing two of them.
#
#      source("R/00_paths.R")
#      dt <- data.table::fread(PATHS$panel_11ch, sep = "|", encoding = "UTF-8")
#
#  Set DATA_MODE before sourcing, or export SYNTH=1, to switch to synthetic.
# =============================================================================

DATA_MODE <- if (exists("DATA_MODE")) DATA_MODE else
             if (nzchar(Sys.getenv("SYNTH"))) "synthetic" else "real"

repo_root <- function() {
  d <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  for (i in 1:6) {
    if (file.exists(file.path(d, "CITATION.cff"))) return(d)
    p <- dirname(d); if (p == d) break; d <- p
  }
  getwd()
}
ROOT <- repo_root()

PATHS <- if (identical(DATA_MODE, "synthetic")) {
  list(
    mode        = "synthetic",
    panel_11ch  = file.path(ROOT, "data/synthetic/panel_synthetic.txt"),
    panel_9ch   = file.path(ROOT, "data/synthetic/panel_synthetic_9ch.txt"),
    geo_raw     = NA_character_,
    month_perm  = file.path(ROOT, "R/collapse/month_perm.rds"),
    model_11ch  = NA_character_,
    xgb_pred    = NA_character_,
    stcraan_pred = NA_character_,
    results_dir = file.path(ROOT, "output/results")
  )
} else {
  list(
    mode        = "real",
    panel_11ch  = "data_hybrid2_prec_sai.txt",
    panel_9ch   = "data_hybrid2_prec.txt",
    geo_raw     = "3_geo3y20_22.txt",
    month_perm  = "month_perm.rds",
    model_11ch  = "HBDL2_Keras_11ch_Model",
    xgb_pred    = "metric_compare/XGB_predict.txt",
    stcraan_pred = "STCRAAN/HB_DL2_Keras_predict.txt",
    results_dir = "."
  )
}

# ------------------------------------------------------ seeds and session ---
# Stated once, used everywhere, and dumped alongside the results so that a
# reader can tell which package versions produced a number.
SEED <- 20260911L
set.seed(SEED)

dump_session <- function(dir = PATHS$results_dir,
                         file = "sessionInfo.txt") {
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  con <- file(file.path(dir, file), open = "wt")
  on.exit(close(con))
  writeLines(c(sprintf("generated   %s", Sys.time()),
               sprintf("data mode   %s", PATHS$mode),
               sprintf("seed        %d", SEED), ""), con)
  capture.output(sessionInfo(), file = con)
  invisible(NULL)
}

# ---------------------------------------------------------- name-based EO ---
# Positional selection of the sequence block (all_cols[42:113]) is correct for
# one specific file and silently wrong for every other. Use this instead.
CHANNELS_9  <- c("norm_NDVI", "norm_NDWI", "norm_LST", "norm_Precipitation",
                 "norm_SMAP", "norm_log_NTL", "norm_VHI",
                 "norm_Rainfall_Deficit", "norm_Heat_Stress_Days")
CHANNELS_11 <- c(CHANNELS_9, "norm_SAI_NDVI", "norm_SAI_NDWI")
MONTHS      <- 5:12

seq_columns <- function(all_cols, channels = CHANNELS_11, months = MONTHS) {
  want <- as.vector(t(outer(channels, months, paste0)))   # month varies fastest
  miss <- setdiff(want, all_cols)
  if (length(miss))
    stop(sprintf("%d sequence columns missing, e.g. %s",
                 length(miss), paste(head(miss, 3), collapse = ", ")))
  want
}
