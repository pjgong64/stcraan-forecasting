### =====================================================================
### Experiment C — reviving the collapsed EO branch
###   1) drop kernel_regularizer from the LSTM layers   (the cause of |kernel| -> 1e-7)
###   2) auxiliary output head off lstm_out             (gradient reaches it straight from the label)
###   3) drop clipnorm                                  (stop squeezing the smaller branch's gradient)
###   4) warm-start from the temporal-only model pretrained in this same script
### Baselines: 9-ch 0.90057 | 11-ch 0.89222 | static-only 0.89681
### =====================================================================

N_CH            <- 11
LR_USED         <- 0.001
EPOCHS_FUSED    <- 20
EPOCHS_PRETRAIN <- 15
AUX_WEIGHT      <- 0.3
DATA_FILE       <- "data_hybrid2_prec_sai.txt"
W1              <- 100/6.575       # 15.209

library(data.table); library(caret); library(pROC); library(reticulate)
use_condaenv("tf-gpu", required = TRUE)
library(keras); py_require_legacy_keras(); library(tensorflow)
py_gc <- import("gc")
gpus <- tf$config$list_physical_devices("GPU")
if (length(gpus) > 0) tf$config$experimental$set_memory_growth(gpus[[1]], TRUE)

super_clear_session <- function() {
  k_clear_session(); py_gc$collect(); invisible(gc(reset = TRUE)); tf$random$set_seed(64L)
}

## =====================================================================
## 1. Data
## =====================================================================
dt <- fread(DATA_FILE, sep = "|", encoding = "UTF-8")
dt[, Y_num := as.numeric(as.character(factor(Y, levels = c(0,1), labels = c(0,1))))]
dt[, ADM3_idx := as.integer(as.factor(ADM3))]
num_adm3_classes <- max(dt$ADM3_idx, na.rm = TRUE); embed_dim <- 9
nm <- names(dt)

PREFIX <- c(NDVI="norm_NDVI", NDWI="norm_NDWI", LST="norm_LST",
            Precipitation="norm_Precipitation", SMAP="norm_SMAP", NTL="norm_log_NTL",
            VHI="norm_VHI", CRD="norm_Rainfall_Deficit", HSD="norm_Heat_Stress_Days",
            SAI_NDVI="norm_SAI_NDVI", SAI_NDWI="norm_SAI_NDWI")
CH       <- names(PREFIX)[1:N_CH]
seq_cols <- unlist(lapply(CH,          function(c) paste0(PREFIX[[c]], 5:12)), use.names = FALSE)
all_seq  <- unlist(lapply(names(PREFIX), function(c) paste0(PREFIX[[c]], 5:12)), use.names = FALSE)
if (length(setdiff(seq_cols, nm))) { print(setdiff(seq_cols, nm)); stop("missing columns") }

drop_cols   <- c("Year","ID","Y","Y_num","ADM3","ADM3_idx")
static_cols <- setdiff(nm, c(drop_cols, all_seq))

tr <- dt[Year %in% c(1,2)]; te <- dt[Year == 3]
y_tr <- tr$Y_num; y_te <- te$Y_num

col_map <- matrix(seq_along(seq_cols), nrow = 8, ncol = N_CH)
ord     <- as.vector(t(col_map))
xtr_seq <- array_reshape(as.matrix(tr[, ..seq_cols])[, ord], c(nrow(tr), 8, N_CH))
xte_seq <- array_reshape(as.matrix(te[, ..seq_cols])[, ord], c(nrow(te), 8, N_CH))
stopifnot(all.equal(as.vector(xtr_seq[1, , ]), as.vector(as.matrix(tr[1, ..seq_cols])[, col_map])))
cat("✅ tensor axes verified: dim2 = month, dim3 = channel (", N_CH, ")\n")

xtr_stat <- as.matrix(tr[, ..static_cols]); xte_stat <- as.matrix(te[, ..static_cols])
xtr_cat  <- tr$ADM3_idx;                    xte_cat  <- te$ADM3_idx
static_dimension <- ncol(xtr_stat)
cat("static dim:", static_dimension, "\n")
rm(dt, tr, te); gc()

sw_tr <- ifelse(y_tr == 1, W1, 1)          # stands in for class_weight (multi-output does not accept class_weight)

## =====================================================================
## 2. STAGE 1 — pretrain the temporal branch on its own
## =====================================================================
cat("\n================ STAGE 1: pretrain temporal branch ================\n")
super_clear_session()

build_temporal <- function(n_ch, lr, drop_seq = 0.2, lstm_hd = 64) {
  inp <- layer_input(shape = c(8, n_ch), name = "seq_input")
  x <- inp %>%
    layer_lstm(units = lstm_hd, return_sequences = TRUE, name = "seq_lstm_1") %>%   # 🌟 no L2
    layer_dropout(rate = drop_seq) %>%
    layer_lstm(units = lstm_hd, return_sequences = FALSE, name = "seq_lstm_2") %>%  # 🌟 no L2
    layer_dropout(rate = drop_seq)
  out <- x %>% layer_dense(units = 32, activation = "relu") %>%
               layer_dense(units = 1, activation = "sigmoid", name = "output")
  m <- keras_model(inp, out)
  m %>% compile(optimizer = optimizer_adam(learning_rate = lr, epsilon = 1e-8),  # 🌟 no clipnorm
                loss = "binary_crossentropy",
                metrics = list(tf$keras$metrics$AUC(name = "auc")))
  m
}

pre <- build_temporal(N_CH, LR_USED)
pre %>% fit(x = xtr_seq, y = y_tr, epochs = EPOCHS_PRETRAIN, batch_size = 2048,
            class_weight = list("0" = 1, "1" = W1), verbose = 1)

p_pre <- pre %>% predict(xte_seq, batch_size = 512) %>% as.numeric()
cat(sprintf("\nTemporal-only test AUC = %.5f   (0.6492 in the paper)\n",
            as.numeric(auc(roc(y_te, p_pre, direction = "<", quiet = TRUE)))))
w_pre <- list(seq_lstm_1 = pre$get_layer("seq_lstm_1")$get_weights(),
              seq_lstm_2 = pre$get_layer("seq_lstm_2")$get_weights())
cat(sprintf("pretrained |kernel| : L1 %.6f   L2 %.6f\n",
            mean(abs(w_pre$seq_lstm_1[[1]])), mean(abs(w_pre$seq_lstm_2[[1]]))))

## =====================================================================
## 3. STAGE 2 — fused model + aux head + warm-start
## =====================================================================
cat("\n================ STAGE 2: fused model ================\n")
super_clear_session()

build_fused <- function(n_ch, lr, wd = 1e-4, lstm_hd = 64, stat_hd = 64,
                        drop_seq = 0.2, drop_stat = 0.2) {
  input_seq <- layer_input(shape = c(8, n_ch), name = "seq_input")
  lstm_out <- input_seq %>%
    layer_lstm(units = lstm_hd, return_sequences = TRUE, name = "seq_lstm_1") %>%   # 🌟 no L2
    layer_dropout(rate = drop_seq) %>%
    layer_lstm(units = lstm_hd, return_sequences = FALSE, name = "seq_lstm_2") %>%  # 🌟 no L2
    layer_dropout(rate = drop_seq)

  input_stat <- layer_input(shape = c(static_dimension), name = "stat_input")
  input_cat  <- layer_input(shape = c(1), name = "cat_input")
  emb_out <- input_cat %>% layer_embedding(input_dim = num_adm3_classes + 1,
                                           output_dim = embed_dim) %>% layer_flatten()

  h_stat <- layer_concatenate(list(input_stat, emb_out)) %>%
    layer_dense(units = stat_hd, kernel_initializer = initializer_lecun_uniform(),
                kernel_regularizer = regularizer_l2(l = wd)) %>%
    layer_batch_normalization(momentum = 0.9, epsilon = 1e-5) %>%
    layer_activation("relu") %>% layer_dropout(rate = drop_stat) %>%
    layer_dense(units = max(16, stat_hd/2), kernel_initializer = initializer_lecun_uniform(),
                kernel_regularizer = regularizer_l2(l = wd)) %>%
    layer_batch_normalization(momentum = 0.9, epsilon = 1e-5) %>%
    layer_activation("relu") %>% layer_dropout(rate = drop_stat)

  fusion <- layer_concatenate(list(h_stat, lstm_out)) %>%
    layer_dense(units = 32, kernel_initializer = initializer_lecun_uniform(),
                activation = "relu", kernel_regularizer = regularizer_l2(l = wd),
                name = "fusion_dense")
  main_out <- fusion %>% layer_dense(units = 1, activation = "sigmoid", name = "output")

  # 🌟 auxiliary head: forces the temporal branch to receive gradient straight from the label
  aux_out <- lstm_out %>% layer_dense(units = 1, activation = "sigmoid", name = "aux_output")

  m <- keras_model(inputs = list(seq_input = input_seq, stat_input = input_stat,
                                 cat_input = input_cat),
                   outputs = list(output = main_out, aux_output = aux_out))
  m %>% compile(
    optimizer = optimizer_adam(learning_rate = lr, epsilon = 1e-8),   # 🌟 no clipnorm
    loss = list(output = "binary_crossentropy", aux_output = "binary_crossentropy"),
    loss_weights = list(output = 1.0, aux_output = AUX_WEIGHT),
    metrics = list(output = tf$keras$metrics$AUC(name = "auc")))
  m
}

model <- build_fused(N_CH, LR_USED)

# 🌟 warm-start
model$get_layer("seq_lstm_1")$set_weights(w_pre$seq_lstm_1)
model$get_layer("seq_lstm_2")$set_weights(w_pre$seq_lstm_2)
cat("✅ warm-started seq_lstm_1 / seq_lstm_2 from temporal-only\n")

xtr <- list(seq_input = xtr_seq, stat_input = xtr_stat, cat_input = xtr_cat)
xte <- list(seq_input = xte_seq, stat_input = xte_stat, cat_input = xte_cat)

fit_ok <- try(
  model %>% fit(x = xtr, y = list(output = y_tr, aux_output = y_tr),
                epochs = EPOCHS_FUSED, batch_size = 2048,
                sample_weight = list(output = sw_tr, aux_output = sw_tr), verbose = 1),
  silent = TRUE)
if (inherits(fit_ok, "try-error")) {
  cat("\n⚠️  sample_weight as a list failed; retrying with a single vector\n")
  model %>% fit(x = xtr, y = list(output = y_tr, aux_output = y_tr),
                epochs = EPOCHS_FUSED, batch_size = 2048,
                sample_weight = sw_tr, verbose = 1)
}

## =====================================================================
## 4. Health of the EO branch after training   <<< first decisive check
## =====================================================================
cat("\n============ A) EO branch health ============\n")
for (n in c("seq_lstm_1","seq_lstm_2")) {
  w <- model$get_layer(n)$get_weights()
  cat(sprintf("%-12s |kernel| %.6f   |recurrent| %.6f   |bias| %.6f\n",
              n, mean(abs(w[[1]])), mean(abs(w[[2]])), mean(abs(w[[3]]))))
}
cat("   (before the fix: |kernel| = 0.00000007 and 0.00000063)\n")

enc <- keras_model(inputs = model$inputs, outputs = model$get_layer("seq_lstm_2")$output)
set.seed(42); idx <- sample(length(y_te), min(50000L, length(y_te)))
Hs <- enc %>% predict(list(seq_input  = xte_seq[idx, , , drop = FALSE],
                           stat_input = xte_stat[idx, , drop = FALSE],
                           cat_input  = xte_cat[idx]), batch_size = 512, verbose = 0)
sds <- apply(Hs, 2, sd)
cat(sprintf("SD of lstm_out across borrowers: mean %.6f  max %.6f  (units < 1e-6: %d/64)\n",
            mean(sds), max(sds), sum(sds < 1e-6)))
cat("   (before the fix: mean 0.000000, 64/64 units dead)\n")

Wf <- model$get_layer("fusion_dense")$get_weights()[[1]]
ns <- max(16, 64/2)
cat(sprintf("fusion |w| static %.6f  |w| LSTM %.6f  -> ratio %.4f\n",
            mean(abs(Wf[1:ns, ])), mean(abs(Wf[(ns+1):nrow(Wf), ])),
            mean(abs(Wf[(ns+1):nrow(Wf), ])) / mean(abs(Wf[1:ns, ]))))
cat("   (before the fix: ratio 0.0006)\n")

## =====================================================================
## 5. Performance
## =====================================================================
pr <- model %>% predict(xte, batch_size = 512, verbose = 1)
p  <- as.numeric(if (is.list(pr)) pr[[1]] else pr)
fwrite(data.table(Actual = y_te, Prob = p), "STCRAAN_ExpC_predict.txt", sep = "|")
save_model_tf(model, "HBDL2_Keras_ExpC_Model")

r <- roc(y_te, p, direction = "<", quiet = TRUE)
cat("\n============ B) Performance on Test 2022 ============\n")
cat(sprintf("AUC          %.5f   (9-ch 0.90057 | 11-ch 0.89222 | static-only 0.89681)\n",
            as.numeric(auc(r))))
cat(sprintf("KS           %.5f   (9-ch 0.63710 | static-only 0.63251)\n",
            max(r$sensitivities + r$specificities - 1)))
cat(sprintf("Recall @0.5  %.4f\n", mean(p[y_te == 1] >= 0.5)))
cat(sprintf("pos rate     %.4f\n", mean(p >= 0.5)))

## =====================================================================
## 6. Compare against static-only at the same operating point   <<< second decisive check
## =====================================================================
ds <- fread("StaticOnly_predict.txt", sep = "|")
ps <- ds$Prob; ys <- ds$Actual
rate <- mean(p >= 0.5); thr <- quantile(ps, 1 - rate)
recF <- mean(p[y_te == 1] >= 0.5); recS <- mean(ps[ys == 1] >= thr)
P <- sum(y_te == 1)
cat("\n============ C) matched operating point ============\n")
cat(sprintf("pos rate                 %.4f\n", rate))
cat(sprintf("Recall  ExpC             %.4f   FN %d\n", recF, round(P*(1-recF))))
cat(sprintf("Recall  static-only      %.4f   FN %d\n", recS, round(P*(1-recS))))
cat(sprintf("GAIN                     %+.2f pp   FN avoided %d\n",
            (recF-recS)*100, round(P*(recS-recF))))
cat("   (9-ch +0.39 pp / 704 borrowers | 11-ch +0.03 pp / -55 borrowers)\n")

## =====================================================================
## 7. Switch off the entire EO branch   <<< third decisive check
## =====================================================================
eps <- 1e-7; lg <- function(v) { v <- pmin(pmax(v, eps), 1-eps); log(v/(1-v)) }
mseq <- apply(xte_seq, MARGIN = c(2,3), FUN = mean, na.rm = TRUE)
xz <- xte
for (t in 1:8) for (f in 1:N_CH) xz$seq_input[, t, f] <- mseq[t, f]
prz <- model %>% predict(xz, batch_size = 512, verbose = 0)
pz  <- as.numeric(if (is.list(prz)) prz[[1]] else prz)

cat("\n============ D) neutralise EO branch ============\n")
cat(sprintf("AUC  %.5f -> %.5f   (lost %.5f)\n", as.numeric(auc(r)),
            as.numeric(auc(roc(y_te, pz, direction = "<", quiet = TRUE))),
            as.numeric(auc(r)) - as.numeric(auc(roc(y_te, pz, direction="<", quiet=TRUE)))))
cat(sprintf("mean |Delta logit|  %.6f   (9-ch 0.001919 | 11-ch 0.000000)\n",
            mean(abs(lg(p) - lg(pz)))))
cat(sprintf("Recall %.4f -> %.4f\n", mean(p[y_te==1] >= 0.5), mean(pz[y_te==1] >= 0.5)))
cat("\n🎉 done\n")


p_dev <- pre %>% predict(xtr_seq, batch_size = 512) %>% as.numeric()
cat(sprintf("Temporal-only  DEV AUC (Year 1-2) = %.5f\n",
            as.numeric(auc(roc(y_tr, p_dev, direction = "<", quiet = TRUE)))))
cat(sprintf("Temporal-only  TEST AUC (Year 3)  = %.5f\n",
            as.numeric(auc(roc(y_te, p_pre, direction = "<", quiet = TRUE)))))
