# =============================================================================
#  12_Factorial7_config.R
#  ---------------------------------------------------------------------------
#  Configuration for the 7-arm x 5-family factorial.
#  EDIT THIS FILE ONLY. The runner (12_Factorial7_run.R) reads it and should not
#  need changing.
#
#  Companion to: 11_Level_diagnostics.r (the ACESD ceiling)
#  Feeds:        Forecasting Table 2 / Table 4 / Sec 4.8 / Sec 5.2 / Sec 6
# =============================================================================

# ---------------------------------------------------------------- paths -----
CFG <- list()

# Bumped whenever this file gains something the runner relies on. check_setup
# prints it, so "I copied the new file" and "the new file is actually there"
# stop being the same claim.
CFG$config_version <- "2026-09-15b"

CFG$data_file   <- "data_hybrid2_prec_sai.txt"   # the model file (140 cols)
CFG$out_dir     <- "factorial7_out"              # results + checkpoints land here
CFG$sep         <- "|"     # pipe-delimited. Set to NULL to auto-detect from the
                           # header; the runner refuses to proceed if the file
                           # resolves to a single column.

# ---------------------------------------------------------------- schema ----
# Column names the runner needs. Set them to whatever your file actually uses;
# the runner asserts each one exists and stops with a readable message if not.
CFG$col_id      <- "ID"           # borrower id
CFG$col_year    <- "Year"         # crop year
CFG$col_adm3    <- "ADM3"         # sub-district code
CFG$col_target  <- "Y"            # 0/1 outcome
# NB: "Previous_Default" is last year's outcome — a legitimate FIN feature,
# not the target. Do not confuse the two.

# The Year column is CODED, not calendar: 1 = 2020, 2 = 2021, 3 = 2022.
# Write the codes here, not the calendar years. With calendar years the split
# silently selects zero rows; the runner now stops rather than returning NA.
CFG$year_labels <- c(`1` = 2020, `2` = 2021, `3` = 2022)   # for printing only
CFG$dev_years   <- c(1, 2)      # 2020, 2021
CFG$test_years  <- c(3)         # 2022

# ---------------------------------------------------------------- features --
# SPATIAL IDENTITY (SP)
#   Everything that encodes "which sub-district is this" — above all the target
#   encoding of ADM3, which IS the sub-district default history.
#   These columns MUST be listed here and MUST NOT remain inside FIN, or the
#   F-only arm silently contains spatial history and the whole factorial is
#   uninterpretable.
#   Five target encodings exist. Confirmed meanings:
#     ADM3   = administrative level 3 (sub-district / tambon)
#     IDProv = administrative level 1 (province) -- COARSER than ADM3
#     RL     = residential location of the borrower
#     DT     = land-rights document type (legal class of the document conferring
#              cultivation rights; NOT geographic -- a tenure attribute)
#   The test that matters is not "is it geographic" but "is it constant within
#   an (ADM3, Year) cell", because that is the only property the 0.662 ceiling
#   constrains. Measured on this file, three are not:
#     TE_ADM3RL     ADM3 x RL     -> contains ADM3, so a strict REFINEMENT of
#                                    it. Its own ceiling is ABOVE 0.662.
#     TE_IDProv_RL  Province x RL -> province is coarser than ADM3, so this is
#                                    NOT a refinement of ADM3; it cuts across
#                                    sub-district boundaries. Neither finer nor
#                                    coarser, and 0.662 says nothing about it.
#     TE_IDDT       document type -> not geographic at all.
#   All three must leave SP regardless of which case they are, because SP has to
#   be constant within (ADM3, Year) for the falsification test to mean anything.
#   Run 12_Factorial7_partition.R to see the measured verdict per column.
CFG$sp_cols <- c(
  "TE_ADM3",          # sub-district                        -> areal at ADM3
  "TE_IDProv_rice",   # province x rice                     -> areal at ADM3
  "TE_ADM3RL",        # sub-district x residence  -> refines ADM3
  "TE_IDProv_RL",     # province x residence      -> crosscuts ADM3
  "TE_IDDT"           # land-rights document type           -> NOT spatial
)

# The two residence-bearing spatial encodings, named separately so they can be
# studied on their own without contaminating the ADM3 ceiling test.
CFG$sp_fine_cols <- c("TE_ADM3RL", "TE_IDProv_RL")

# The runner verifies that every SP column is CONSTANT within (ADM3, Year).
# That is the definition of areal, and the EO+SP arm has to be purely areal for
# the 0.662 falsification test to mean anything.
CFG$check_areal <- TRUE

# What to do with an SP candidate that turns out not to be areal:
#   "split" spatial ones (CFG$sp_fine_cols) STAY in SP; the rest go to FIN.
#           RECOMMENDED. SP then means "all location information", and the
#           falsification test uses the SPA block instead, which the runner
#           builds automatically from the areal subset.
#   "fin"   keep every non-areal candidate as a FIN feature
#   "drop"  remove it from the study entirely
#   "stop"  halt and let you decide by hand
# "fin" keeps the deployed model's feature set intact, so F+SP+EO can still
# reproduce the 0.909 benchmark, while SP stays clean for the ceiling test.
# Cost of "fin", stated plainly: TE_ADM3RL and TE_IDProv_RL are genuinely
# geographic, so F now carries real spatial information and F -> F+SP
# UNDERSTATES what location is worth. It does not touch F+SP -> F+SP+EO, which
# is the contrast the EO claim rests on.
# TE_IDDT is a different case: it belongs in FIN on the merits, not as a
# fallback. Document class governs whether the plot can be pledged at all.
CFG$sp_nonareal_action <- "split"

# ENVIRONMENTAL (EO) — channel prefixes, matched as  <prefix><month>
# Use the exact names. Do NOT use regex on "_NDVI" alone: it also matches
# "norm_SAI_NDVI".
CFG$eo_prefix <- c(
  NDVI          = "norm_NDVI",
  NDWI          = "norm_NDWI",
  LST           = "norm_LST",
  Precipitation = "norm_Precipitation",
  SMAP          = "norm_SMAP",
  NTL           = "norm_log_NTL",
  VHI           = "norm_VHI",
  CRD           = "norm_Rainfall_Deficit",     # NB: high = MORE rain
  HSD           = "norm_Heat_Stress_Days"
)
# The two standardized-anomaly channels. Screened out in the main pipeline but
# kept here as an option, because Sec 3.6 of the ACESD paper shows the screen
# removed them for a structural reason rather than because they carry nothing.
CFG$eo_prefix_anomaly <- c(
  SAI_NDVI = "norm_SAI_NDVI",
  SAI_NDWI = "norm_SAI_NDWI"
)
# TRUE -> 11 channels x 8 months = 88 columns.
# Set TRUE deliberately. The headline claim of both papers is that EO adds
# little. A null result obtained after discarding two channels is attackable;
# the same null with every channel available is not. And SAI is the channel
# where an in-season signal would live if one existed: norm_NDVI is dominated
# by persistent geography (some places are always greener), whereas a
# standardized anomaly removes each location's own mean and leaves exactly the
# deviation-from-normal that the 0.013 in-season component is supposed to be.
# Excluding it and then reporting that EO carries no in-season signal would be
# close to circular.
CFG$include_anomaly <- TRUE

CFG$months <- 5:12                # May .. December

# How the month is glued onto a channel base. Leave NULL and the runner detects
# it from the file; set it only to override. One of:
#   "<base><m>"  "<base>_<m>"  "<base>.<m>"  "<base>M<m>"
#   "<base>_M<m>"  "<base><mm>"  "<base>_<mm>"
CFG$month_pattern <- NULL

# FINANCIAL (FIN)
#   Left as "everything else": all numeric columns that are neither the id/year/
#   target, nor SP, nor EO. The runner prints the resolved list — read it once
#   and confirm nothing spatial or environmental leaked in.
#   With this file FIN resolves to 43 columns: Has_Credit_History,
#   Previous_Default, 16 norm_log_*, 14 norm_win_*, 5 norm_n*/norm_CD,
#   IDRV_4/5, and the four planting/harvest cyclical terms MP_sin/cos, MH_sin/cos.
#   43 FIN + 5 SP = the "48 financial and administrative covariates" the
#   manuscript reports — i.e. the published 48 already contained four spatial
#   encodings (two constant within ADM3, two not) and one land-tenure encoding.
#   Section 2.3 now says so.
CFG$fin_exclude_extra <- character(0)   # names to force out of FIN

# Columns whose name looks spatial but which measurement has cleared. TE_IDDT
# is the land-rights document class: 64 levels, one of them present in 5,741 of
# the 6,236 sub-districts, i.e. a nationwide categorical, not a place. It sits
# in FIN on the merits. Listing it here stops the startup warning crying wolf
# on every run, which is how a real warning gets ignored.
CFG$fin_known_nonspatial <- c("TE_IDDT")

# ---------------------------------------------------------------- arms ------
# 7 feature sets. Each is a character vector of blocks.
#   FIN = borrower-level only (43 + TE_IDDT: tenure, not place)
#   SP  = ALL location information, areal and sub-cell alike
#   SPA = the areal subset of SP -- the only block the 0.662 bound constrains
#   EO  = the satellite tensor
CFG$arms <- list(
  "F"        = c("FIN"),              # truly borrower-level. Expect < 0.897.
  "F+EO"     = c("FIN", "EO"),
  "F+SP"     = c("FIN", "SP"),        # what location is worth on top of FIN
  "F+SP+EO"  = c("FIN", "SP", "EO"),  # full model -> should reproduce 0.909
  "EO"       = c("EO"),
  "SP"       = c("SP"),               # all location alone. NOT capped at 0.662.
  "SPA"      = c("SPA"),
  "EO+SPA"   = c("EO", "SPA")         # falsification test. MUST be <= 0.662.
)
# NOTE the one that changed: the ceiling test is EO+SPA, never EO+SP. SP now
# contains sub-cell spatial encodings, which a 0.662 bound defined on (ADM3,
# Year) does not constrain. Testing EO+SP against 0.662 would be a category
# error, not a test.

# ---------------------------------------------------------------- families --
# ST-CRAAN keeps its own static branch on the arms without EO, so it is defined
# everywhere. It is not the same model as MLP: the dense sizes, dropout, head
# and learning rate come from CFG$hp$stcraan, not CFG$hp$mlp.
CFG$families <- c("LR", "RF", "XGB", "MLP", "STCRAAN")
# ST-CRAAN now runs on ALL seven arms, like every other family. On an arm with
# no EO it fits its static branch alone -- same head, same optimiser, same
# early stopping, same hp block -- so F -> F+EO and F+SP -> F+SP+EO are
# measurable INSIDE ST-CRAAN. That is a cleaner statement of what EO adds to
# this architecture than comparing it across families, because no
# representation difference is involved.
# Grid is now 5 x 7 = 35 cells, not 32.
CFG$stcraan_arms <- names(CFG$arms)

# ---------------------------------------------------------------- hyper -----
# Every hyper-parameter the runner uses, in one place. They were chosen on the
# EO-BEARING arms and are applied unchanged to the arms without EO. That biases
# the comparison IN FAVOUR of EO, which is why "EO adds little" is the
# conservative reading -- so change these deliberately, and if you tune, tune on
# an EO arm and reuse, never per arm. Per-arm tuning would make the arms
# incomparable and the whole factorial uninterpretable.
CFG$hp <- list(

  xgb = list(
    eta              = 0.05,
    max_depth        = 6,
    subsample        = 0.8,
    colsample_bytree = 0.8,
    min_child_weight = 10,
    nrounds          = 800,    # upper bound; early stopping decides the real one
    early_stopping   = 30
  ),

  # h2o penalised logistic regression
  lr = list(
    lambda_search = TRUE,
    nlambdas      = 20,
    standardize   = TRUE
  ),

  rf = list(
    ntrees              = 300,
    max_depth           = 20,
    min_rows            = 50,
    stopping_rounds     = 3,
    score_tree_interval = 10
  ),

  # MLP: dense stack on the flat feature matrix
  mlp = list(
    units    = c(256, 128, 64),   # one dense layer per element
    dropout  = c(0.3, 0.2, 0),    # same length as units; 0 = no dropout layer
    lr       = 1e-3
  ),

  # ST-CRAAN: static dense branch + bidirectional GRU branch with attention
  stcraan = list(
    gru_units     = 64,        # bidirectional -> 2x this many output features
    l2            = 1e-5,      # applied to input, recurrent AND bias kernels
    static_units  = c(256, 128),
    static_drop   = c(0.3, 0),
    head_units    = 64,
    head_drop     = 0.2,
    lr            = 1e-3
  )
)

# ---------------------------------------------------------------- eval ------
CFG$alert_rates <- c(0.10, 0.20, 0.30)   # matched alert volume, NOT a 0.5 cut
CFG$seed        <- 20260910

# ---------------------------------------------------------------- compute ---
# --------------------------------------------------------------- python -----
# WHICH Python reticulate uses. This is the usual reason keras "is not
# installed" on a machine where it plainly is: reticulate picked a different
# environment. The error names the one it searched -- if that is not the env
# holding tensorflow, set it here.
#
#   CFG$python_env  <- "r-tensorflow"          # a conda env NAME, or
#   CFG$python_env  <- "C:/Users/You/anaconda3/envs/tf/python.exe"   # a full path
#
# Leave NULL to let reticulate choose. The runner prints which interpreter it
# ended up with, and if tensorflow is missing it lists the conda envs that do
# have it, so the value to put here is on screen.
CFG$python_env <- "tf-gpu"

# ---------------------------------------------------------------------------
#  Finding a conda environment WITHOUT the conda binary.
#
#  use_condaenv("tf-gpu") hands the NAME to conda and asks it where that env
#  lives, so it needs conda.exe to be findable. Anaconda's installer does not
#  put conda on PATH, and reticulate only looks on PATH plus a short list of
#  default roots -- so a plain cmd.exe window gets
#
#      Error : Unable to find conda binary. Is Anaconda installed?
#
#  while the identical call succeeds inside RStudio, which inherits a PATH set
#  up by Navigator or a shell profile. That is a difference in how the process
#  was launched, not a broken install.
#
#  An environment is just a folder, so the name lookup is avoidable: locate
#  <root>/envs/<name>/python.exe on disk and hand reticulate the full path.
#  reticulate recognises a conda env by the conda-meta folder beside the
#  interpreter and activates it properly, DLL directories included. No conda
#  binary is involved at any point.
#
#  Both the runner and check_setup.bat use these two functions, so what the
#  check prints is exactly what the run will do.
# ---------------------------------------------------------------------------
conda_roots <- function() {
  up <- Sys.getenv("USERPROFILE", Sys.getenv("HOME"))
  la <- Sys.getenv("LOCALAPPDATA")
  pf <- Sys.getenv("ProgramFiles")
  d  <- c("anaconda3", "miniconda3", "miniforge3", "mambaforge",
          "Anaconda3", "Miniconda3", "Miniforge3")
  cp <- Sys.getenv("CONDA_PREFIX")          # set if launched from an activated shell
  r  <- c(file.path(up, d), file.path(la, d), file.path(la, "Programs", d),
          file.path(pf, d), file.path("C:/ProgramData", d),
          "C:/Anaconda3", "C:/Miniconda3",
          if (nzchar(cp)) c(cp, dirname(dirname(cp))))
  r <- unique(Filter(nzchar, r))
  r[dir.exists(r)]
}

# Every environment this machine has, whether or not conda can be found.
# has_tf is read off the filesystem -- the site-packages folder -- rather than
# by importing, because importing binds reticulate for the whole session and
# that binding must not be spent on a diagnostic.
conda_envs <- function() {
  up   <- Sys.getenv("USERPROFILE", Sys.getenv("HOME"))
  dirs <- c(file.path(conda_roots(), "envs"), file.path(up, ".conda/envs"))
  dirs <- dirs[dir.exists(dirs)]
  out  <- list()
  for (d in dirs) for (e in list.dirs(d, recursive = FALSE)) {
    p <- file.path(e, if (.Platform$OS.type == "windows") "python.exe" else "bin/python")
    if (file.exists(p))
      out[[length(out) + 1]] <- data.frame(
        name   = basename(e),
        python = normalizePath(p, "/", mustWork = FALSE),
        has_tf = dir.exists(file.path(e, "Lib/site-packages/tensorflow")) ||
                 length(Sys.glob(file.path(e, "lib/python*/site-packages/tensorflow"))) > 0,
        stringsAsFactors = FALSE)
  }
  # the base environment is the root itself, not a folder under envs/
  for (r in conda_roots()) {
    p <- file.path(r, if (.Platform$OS.type == "windows") "python.exe" else "bin/python")
    if (file.exists(p))
      out[[length(out) + 1]] <- data.frame(
        name   = paste0("base (", basename(r), ")"),
        python = normalizePath(p, "/", mustWork = FALSE),
        has_tf = dir.exists(file.path(r, "Lib/site-packages/tensorflow")),
        stringsAsFactors = FALSE)
  }
  if (!length(out)) return(NULL)
  e <- do.call(rbind, out)
  e[!duplicated(e$python), , drop = FALSE]
}

# NA when nothing matches. A value containing a slash is taken as a path and
# returned as-is if it exists, so CFG$python_env accepts either form.
find_conda_python <- function(name) {
  if (is.null(name) || !nzchar(name)) return(NA_character_)
  if (grepl("[/\\\\]", name))
    return(if (file.exists(name)) normalizePath(name, "/") else NA_character_)
  e <- conda_envs()
  if (is.null(e)) return(NA_character_)
  hit <- e$python[e$name == name]
  if (length(hit)) return(hit[1])
  NA_character_
}

# Route the keras R API to tf_keras (Keras 2) rather than Keras 3, via
# py_require_legacy_keras(). The ST-CRAAN model is a two-input functional model
# fitted with sample_weight; that is Keras 2 API, and Keras 3 does not accept it
# unchanged. Set FALSE only if you have ported the model to Keras 3.
CFG$keras_legacy <- TRUE

CFG$h2o_mem       <- "24G"
CFG$h2o_threads   <- -1
CFG$xgb_nthread   <- parallel::detectCores()
CFG$keras_batch   <- 4096
CFG$keras_epochs  <- 30
CFG$keras_patience<- 5
# Live training output: xgboost every 10 rounds, keras per epoch, h2o progress
# bars. Set FALSE for a quiet log (keras then prints one line per epoch).
CFG$verbose <- TRUE

# Pause at the console after every finished cell -- [Y] next, [N] stop, [A] run
# the rest unattended. Resuming is free: finished cells are skipped, so stopping
# costs nothing. Set FALSE, or pass "auto" on the command line, to never ask.
# If no terminal is attached (nohup, pipe, cron) the script detects it and
# switches to auto by itself rather than hanging.
CFG$pause_between_runs <- TRUE

CFG$predict_chunk <- 200000L      # chunked prediction; avoids the OOM we hit before

# Smoke test: fraction of DEV rows used for fitting. 1 = full run.
# Never subsample the TEST set — AUC on a small test set quantizes (we found
# scores that were exact multiples of 1.886e-7 when a 5,000-row subsample was
# used). The runner refuses to subsample test.
CFG$dev_fraction  <- 1.0

# ---------------------------------------------------------------- anchors ---
# Values already established elsewhere. The runner compares against them and
# prints PASS / CHECK lines. These are sanity checks, not thresholds to hit.
CFG$anchor <- list(
  areal_ceiling_test = 0.66223,   # LOO oracle on (ADM3, Year), 2022   [11_]
  sp_history_test    = 0.64950,   # ranking 2022 on 2020-21 ADM3 rate  [11_]
                                  # SPA uses TE_ADM3, which carries 1,544
                                  # distinct values over 6,236 sub-districts.
                                  # Those collisions are rate-driven (equal
                                  # default rates encode to equal values), and
                                  # the oracle ties such cells too, so SPA
                                  # should land NEAR this anchor. A large gap
                                  # would mean the smoothing reordered cells,
                                  # not that resolution was lost.
  eo_only_test       = 0.51187,   # EO-only forecaster, 2022, 9 CHANNELS [prior]
  eo_only_dev        = 0.64259,   # with include_anomaly = TRUE the EO arm is a
                                  # different feature set; treat these two as a
                                  # floor, not as a target to match.
  fin_only_test      = 0.89681,   # static-only, but that run's feature set
                                  # INCLUDED the four spatial encodings, so the
                                  # new F arm is not the same quantity. Expect
                                  # F < 0.897; the drop IS the result.   [prior]
  xgb_full_test      = 0.90880    # strongest benchmark                [prior]
)
