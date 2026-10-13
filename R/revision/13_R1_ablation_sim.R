### =====================================================================
### 13_R1_ablation_sim.R  --  revision round 1, reviewer 2 comment M4
###
### Two experiments on Configuration A (the 2-layer LSTM fused model of
### 7_ExpA_SAI_11ch.r / 9_ExpC_revive_branch.r):
###
###   ablation : which of the revival changes is needed?  Ten fits on the full
###              panel: the inherited and the revived configurations, each of
###              the four changes added alone to the inherited one, and each
###              removed alone from the revived one.
###                 l2in : L2 1e-4 on the LSTM input kernels (inherited = on)
###                 aux  : auxiliary head on the LSTM output, weight 0.3
###                 warm : LSTM layers initialised from a temporal-only fit
###                 clip : gradient-norm clipping at 1.0 (inherited = on)
###
###   sim      : do the branch-health diagnostics separate a modality WITH a
###              known out-of-time signal from one without?  On a 20% borrower
###              subsample the label is replaced by
###                 y_sim = max(y, Bernoulli(plogis(c0 + beta * e)))
###              where e is a sub-district-year EO index (z-scored mean of
###              norm_NDVI 8-10, scaled on the development years). The same
###              rule generates every year, so the signal persists into 2022
###              by construction. beta in {0, 0.5, 1.5} x {inherited, revived}.
###
### Every fit uses 2020-21 only; 2022 is only scored. Results are appended to
### factorial7_out/r1_ablation_sim.csv; finished rows are skipped on restart.
###
### Usage:  Rscript 13_R1_ablation_sim.R ablation
###         Rscript 13_R1_ablation_sim.R sim
### =====================================================================

MODE <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(MODE) || !MODE %in% c("ablation", "sim")) stop("usage: Rscript 13_R1_ablation_sim.R ablation|sim")

N_CH            <- 11
LR_USED         <- 0.001
EPOCHS_FUSED    <- 20
EPOCHS_PRETRAIN <- 15
AUX_WEIGHT      <- 0.3
WD              <- 1e-4
W1              <- 100 / 6.575        # 15.209, as in Configuration A
BATCH           <- 2048
SIM_FRAC        <- 0.20
SIM_C0          <- -3.5               # baseline extra-default log-odds (~3%)
DATA_FILE       <- "data_hybrid2_prec_sai.txt"
OUT_CSV         <- file.path("factorial7_out", "r1_ablation_sim.csv")
dir.create("factorial7_out", showWarnings = FALSE)

## log everything (including the error that stops the script) to a file,
## because the .bat window closes over it
dir.create("factorial7_out", showWarnings = FALSE)
.logcon <- file(file.path("factorial7_out", sprintf("r1_%s_console.txt", MODE)), open = "at")
sink(.logcon, split = TRUE); sink(.logcon, type = "message")
options(error = function() { traceback(2); quit(status = 1) })

library(data.table); library(pROC); library(reticulate)
## bind Python the same way 12_Factorial7_run.R does: by folder, not via conda.exe,
## which is not on PATH in a double-clicked cmd window ("Unable to find conda binary")
source("12_Factorial7_config.R")
.py <- tryCatch(find_conda_python(CFG$python_env), error = function(e) NA_character_)
if (!is.na(.py)) use_python(.py, required = TRUE) else use_condaenv(CFG$python_env, required = TRUE)
library(keras); py_require_legacy_keras(); library(tensorflow)
cat("python:", reticulate::py_config()$python, "\n")
py_gc <- import("gc")
gpus <- tf$config$list_physical_devices("GPU")
if (length(gpus) > 0) tf$config$experimental$set_memory_growth(gpus[[1]], TRUE)
say <- function(...) cat(sprintf("[%s] ", format(Sys.time(), "%H:%M:%S")), sprintf(...), "\n", sep = "")

clear <- function() { k_clear_session(); py_gc$collect(); invisible(gc()); tf$random$set_seed(64L); set.seed(64L) }

## ---------------------------------------------------------------- data ----
say("reading %s", DATA_FILE)
dt <- fread(DATA_FILE, sep = "|", encoding = "UTF-8")
dt[, Y_num := as.integer(as.character(Y))]
dt[, ADM3_idx := as.integer(as.factor(ADM3))]
num_adm3 <- max(dt$ADM3_idx)

PREFIX <- c(NDVI="norm_NDVI", NDWI="norm_NDWI", LST="norm_LST",
            Precipitation="norm_Precipitation", SMAP="norm_SMAP", NTL="norm_log_NTL",
            VHI="norm_VHI", CRD="norm_Rainfall_Deficit", HSD="norm_Heat_Stress_Days",
            SAI_NDVI="norm_SAI_NDVI", SAI_NDWI="norm_SAI_NDWI")
seq_cols <- unlist(lapply(names(PREFIX)[1:N_CH], function(c) paste0(PREFIX[[c]], 5:12)), use.names = FALSE)
stopifnot(all(seq_cols %in% names(dt)))
drop_cols   <- c("Year", "ID", "Y", "Y_num", "ADM3", "ADM3_idx")
static_cols <- setdiff(names(dt), c(drop_cols, seq_cols))
say("static dim %d (expect 48)", length(static_cols))

if (MODE == "sim") {
  set.seed(20261011)
  ids <- unique(dt$ID); keep <- sample(ids, floor(SIM_FRAC * length(ids)))
  dt <- dt[ID %in% keep]
  # EO index: mean of norm_NDVI 8-10 per row (constant within a cell), z-scored on dev
  dt[, e_raw := (norm_NDVI8 + norm_NDVI9 + norm_NDVI10) / 3]
  mu <- mean(dt[Year %in% c(1, 2), e_raw]); sdv <- sd(dt[Year %in% c(1, 2), e_raw])
  dt[, e_z := (e_raw - mu) / sdv]
  # one uniform draw per row, shared by every beta, so the betas differ only in signal
  dt[, u_sim := runif(.N)]
  say("sim subsample: %s borrowers, %s rows", format(length(keep), big.mark = ","), format(nrow(dt), big.mark = ","))
}

tr_i <- which(dt$Year %in% c(1, 2)); te_i <- which(dt$Year == 3)
col_map <- matrix(seq_along(seq_cols), nrow = 8, ncol = N_CH)
ord     <- as.vector(t(col_map))
mk_seq  <- function(i) array_reshape(as.matrix(dt[i, ..seq_cols])[, ord], c(length(i), 8, N_CH))
X_tr <- list(seq_input = mk_seq(tr_i), stat_input = as.matrix(dt[tr_i, ..static_cols]), cat_input = dt$ADM3_idx[tr_i])
X_te <- list(seq_input = mk_seq(te_i), stat_input = as.matrix(dt[te_i, ..static_cols]), cat_input = dt$ADM3_idx[te_i])
stopifnot(all.equal(as.vector(X_tr$seq_input[1, , ]), as.vector(as.matrix(dt[tr_i[1], ..seq_cols])[, col_map])))
static_dim <- ncol(X_tr$stat_input)

labels_for <- function(beta) {
  y <- dt$Y_num
  if (MODE == "sim") y <- pmax(y, as.integer(dt$u_sim < plogis(SIM_C0 + beta * dt$e_z)))
  list(tr = y[tr_i], te = y[te_i])
}

## ---------------------------------------------------------------- models --
build_temporal <- function(l2in, clip) {
  reg <- if (l2in) regularizer_l2(WD) else NULL
  inp <- layer_input(shape = c(8, N_CH), name = "seq_input")
  x <- inp %>% layer_lstm(64, return_sequences = TRUE,  kernel_regularizer = reg, name = "seq_lstm_1") %>%
    layer_dropout(0.2) %>%
    layer_lstm(64, return_sequences = FALSE, kernel_regularizer = reg, name = "seq_lstm_2") %>%
    layer_dropout(0.2)
  out <- x %>% layer_dense(32, activation = "relu") %>% layer_dense(1, activation = "sigmoid")
  m <- keras_model(inp, out)
  opt <- if (clip) optimizer_adam(learning_rate = LR_USED, epsilon = 1e-8, clipnorm = 1.0)
         else      optimizer_adam(learning_rate = LR_USED, epsilon = 1e-8)
  m %>% compile(optimizer = opt, loss = "binary_crossentropy")
  m
}

build_fused <- function(l2in, aux, clip) {
  reg <- if (l2in) regularizer_l2(WD) else NULL
  input_seq <- layer_input(shape = c(8, N_CH), name = "seq_input")
  lstm_out <- input_seq %>%
    layer_lstm(64, return_sequences = TRUE,  kernel_regularizer = reg, name = "seq_lstm_1") %>%
    layer_dropout(0.2) %>%
    layer_lstm(64, return_sequences = FALSE, kernel_regularizer = reg, name = "seq_lstm_2") %>%
    layer_dropout(0.2)
  input_stat <- layer_input(shape = c(static_dim), name = "stat_input")
  input_cat  <- layer_input(shape = c(1), name = "cat_input")
  emb <- input_cat %>% layer_embedding(input_dim = num_adm3 + 1, output_dim = 9) %>% layer_flatten()
  h <- layer_concatenate(list(input_stat, emb)) %>%
    layer_dense(64, kernel_initializer = initializer_lecun_uniform(), kernel_regularizer = regularizer_l2(WD)) %>%
    layer_batch_normalization(momentum = 0.9, epsilon = 1e-5) %>% layer_activation("relu") %>% layer_dropout(0.2) %>%
    layer_dense(32, kernel_initializer = initializer_lecun_uniform(), kernel_regularizer = regularizer_l2(WD)) %>%
    layer_batch_normalization(momentum = 0.9, epsilon = 1e-5) %>% layer_activation("relu") %>% layer_dropout(0.2)
  fusion <- layer_concatenate(list(h, lstm_out)) %>%
    layer_dense(32, kernel_initializer = initializer_lecun_uniform(), activation = "relu",
                kernel_regularizer = regularizer_l2(WD), name = "fusion_dense")
  main_out <- fusion %>% layer_dense(1, activation = "sigmoid", name = "output")
  ins <- list(seq_input = input_seq, stat_input = input_stat, cat_input = input_cat)
  m <- if (aux) {
    aux_out <- lstm_out %>% layer_dense(1, activation = "sigmoid", name = "aux_output")
    keras_model(inputs = ins, outputs = list(output = main_out, aux_output = aux_out))
  } else keras_model(inputs = ins, outputs = main_out)
  opt <- if (clip) optimizer_adam(learning_rate = LR_USED, epsilon = 1e-8, clipnorm = 1.0)
         else      optimizer_adam(learning_rate = LR_USED, epsilon = 1e-8)
  if (aux) {
    m %>% compile(optimizer = opt,
                  loss = list(output = "binary_crossentropy", aux_output = "binary_crossentropy"),
                  loss_weights = list(output = 1.0, aux_output = AUX_WEIGHT))
  } else {
    m %>% compile(optimizer = opt, loss = "binary_crossentropy")
  }
  m
}

kabs <- function(m, n) mean(abs(m$get_layer(n)$get_weights()[[1]]))
krec <- function(m, n) mean(abs(m$get_layer(n)$get_weights()[[2]]))
main_pred <- function(m, X) { p <- m %>% predict(X, batch_size = 4096, verbose = 0); as.numeric(if (is.list(p)) p[[1]] else p) }
rec_at <- function(p, y, a = 0.20) { t <- quantile(p, 1 - a, names = FALSE); mean(p[y == 1] >= t) }
lg <- function(v) { v <- pmin(pmax(v, 1e-7), 1 - 1e-7); log(v / (1 - v)) }

## pre-trained temporal weights, cached per label set so warm-start runs share them
pretrain <- function(lab, tag) {
  f <- file.path("factorial7_out", sprintf("r1_pretrain_%s.rds", tag))
  if (file.exists(f)) return(readRDS(f))
  clear(); say("pre-training temporal branch (%s)", tag)
  pm <- build_temporal(l2in = FALSE, clip = FALSE)
  pm %>% fit(X_tr$seq_input, lab$tr, epochs = EPOCHS_PRETRAIN, batch_size = BATCH,
             class_weight = list("0" = 1, "1" = W1), verbose = 2)
  w <- list(seq_lstm_1 = pm$get_layer("seq_lstm_1")$get_weights(),
            seq_lstm_2 = pm$get_layer("seq_lstm_2")$get_weights())
  saveRDS(w, f); w
}

run_one <- function(cfg, l2in, aux, warm, clip, b = NA_real_) {
  config <- cfg; beta <- b
  done <- if (file.exists(OUT_CSV)) fread(OUT_CSV) else NULL
  if (!is.null(done)) {
    hit <- done$mode == MODE & done$config == cfg & (is.na(b) | (!is.na(done$beta) & done$beta == b))
    if (any(hit)) { say("skip %s beta=%s (done)", cfg, b); return(invisible()) }
  }
  t0 <- Sys.time()
  lab <- labels_for(if (is.na(beta)) 0 else beta)
  tag <- if (MODE == "sim") sprintf("sim_beta%s", beta) else "real"
  wpre <- if (warm) pretrain(lab, tag) else NULL
  clear(); say("fitting %s  (l2in=%d aux=%d warm=%d clip=%d beta=%s)", config, l2in, aux, warm, clip, beta)
  m <- build_fused(l2in, aux, clip)
  k1_0 <- kabs(m, "seq_lstm_1"); k2_0 <- kabs(m, "seq_lstm_2")
  if (warm) { m$get_layer("seq_lstm_1")$set_weights(wpre$seq_lstm_1); m$get_layer("seq_lstm_2")$set_weights(wpre$seq_lstm_2) }
  sw <- ifelse(lab$tr == 1, W1, 1)
  if (aux) {
    m %>% fit(x = X_tr, y = list(output = lab$tr, aux_output = lab$tr), epochs = EPOCHS_FUSED,
              batch_size = BATCH, sample_weight = list(output = sw, aux_output = sw), verbose = 2)
  } else {
    m %>% fit(x = X_tr, y = lab$tr, epochs = EPOCHS_FUSED,
              batch_size = BATCH, sample_weight = sw, verbose = 2)
  }
  ## branch health
  set.seed(42); si <- sample(length(lab$te), min(50000L, length(lab$te)))
  enc <- keras_model(inputs = m$inputs, outputs = m$get_layer("seq_lstm_2")$output)
  H <- enc %>% predict(list(seq_input = X_te$seq_input[si, , , drop = FALSE],
                            stat_input = X_te$stat_input[si, , drop = FALSE],
                            cat_input = X_te$cat_input[si]), batch_size = 4096, verbose = 0)
  sds <- apply(H, 2, sd)
  Wf <- m$get_layer("fusion_dense")$get_weights()[[1]]          # (32 + 64) x 32
  ratio <- mean(abs(Wf[33:96, ])) / mean(abs(Wf[1:32, ]))
  ## performance and neutralisation on 2022
  p  <- main_pred(m, X_te)
  Xz <- X_te; mseq <- apply(X_te$seq_input, c(2, 3), mean)
  for (t in 1:8) for (f in 1:N_CH) Xz$seq_input[, t, f] <- mseq[t, f]
  pz <- main_pred(m, Xz)
  auc  <- as.numeric(auc(roc(lab$te, p,  direction = "<", quiet = TRUE)))
  aucz <- as.numeric(auc(roc(lab$te, pz, direction = "<", quiet = TRUE)))
  row <- data.table(mode = MODE, config = config, beta = beta, l2in = l2in, aux = aux, warm = warm, clip = clip,
                    k1_init = k1_0, k1 = kabs(m, "seq_lstm_1"), k2_init = k2_0, k2 = kabs(m, "seq_lstm_2"),
                    k1_ratio = kabs(m, "seq_lstm_1") / k1_0, rec1 = krec(m, "seq_lstm_1"), rec2 = krec(m, "seq_lstm_2"),
                    hid_sd_mean = mean(sds), units_dead = sum(sds < 1e-6), fusion_ratio = ratio,
                    auc = auc, auc_neutral = aucz, dAUC = auc - aucz, D = mean(abs(lg(p) - lg(pz))),
                    recall20 = rec_at(p, lab$te), recall20_neutral = rec_at(pz, lab$te),
                    test_rate = mean(lab$te), secs = as.numeric(difftime(Sys.time(), t0, units = "secs")),
                    stamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
  print(row)
  fwrite(row, OUT_CSV, append = file.exists(OUT_CSV))
  rm(m, enc, H, Xz); clear()
}

## ---------------------------------------------------------------- grid ----
if (MODE == "ablation") {
  grid <- rbind(
    data.table(config = "inherited",        l2in = 1, aux = 0, warm = 0, clip = 1),
    data.table(config = "revived",          l2in = 0, aux = 1, warm = 1, clip = 0),
    data.table(config = "inherited+noL2",   l2in = 0, aux = 0, warm = 0, clip = 1),
    data.table(config = "inherited+aux",    l2in = 1, aux = 1, warm = 0, clip = 1),
    data.table(config = "inherited+warm",   l2in = 1, aux = 0, warm = 1, clip = 1),
    data.table(config = "inherited+noclip", l2in = 1, aux = 0, warm = 0, clip = 0),
    data.table(config = "revived-withL2",   l2in = 1, aux = 1, warm = 1, clip = 0),
    data.table(config = "revived-noaux",    l2in = 0, aux = 0, warm = 1, clip = 0),
    data.table(config = "revived-nowarm",   l2in = 0, aux = 1, warm = 0, clip = 0),
    data.table(config = "revived-withclip", l2in = 0, aux = 1, warm = 1, clip = 1))
  for (i in seq_len(nrow(grid))) with(grid[i], run_one(config, l2in == 1, aux == 1, warm == 1, clip == 1))
} else {
  for (bb in c(0, 0.5, 1.5)) {
    run_one("inherited", TRUE,  FALSE, FALSE, TRUE,  b = bb)
    run_one("revived",   FALSE, TRUE,  TRUE,  FALSE, b = bb)
  }
}
say("done: %s", OUT_CSV)
