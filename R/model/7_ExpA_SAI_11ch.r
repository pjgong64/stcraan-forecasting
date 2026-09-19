### =====================================================================
### Experiment A — restore SAI_NDVI / SAI_NDWI : 9 channels -> 11 channels
### Question: do sub-district-standardised ANOMALIES add forecasting power
###           that raw LEVELS do not, once ADM3 identity is already in the model?
### =====================================================================

LR_USED     <- 0.001   # same value as the real ST-CRAAN run
EPOCHS_USED <- 20      # same value as the real ST-CRAAN run
SEQ_FILE    <- "data_hybrid2_prec_sai.txt"   # output of 6_Build_SAI_file.r

library(data.table); library(caret); library(pROC); library(reticulate)
use_condaenv("tf-gpu", required = TRUE)
library(keras); py_require_legacy_keras(); library(tensorflow)
py_gc <- import("gc")
gpus <- tf$config$list_physical_devices("GPU")
if (length(gpus) > 0) tf$config$experimental$set_memory_growth(gpus[[1]], TRUE)

super_clear_session <- function() {
  k_clear_session(); py_gc$collect(); invisible(gc(reset = TRUE)); tf$random$set_seed(64L)
}

## ---------------------------------------------------------------------
## STEP 0 — first check: does this file actually carry the SAI columns?
## ---------------------------------------------------------------------
dt <- fread(SEQ_FILE, sep = "|", encoding = "UTF-8")
nm <- names(dt)

cat("\n================ STEP 0: column audit ================\n")
cat("total columns:", length(nm), "\n")
sai <- grep("^norm_SAI_", nm, value = TRUE)
cat("SAI columns found:", length(sai), "\n")
if (length(sai)) print(sai)

if (length(sai) != 16) {
  cat("\n*** stop here ***\n")
  cat("need 16 SAI columns (SAI_NDVI 8 months + SAI_NDWI 8 months) but found", length(sai), "columns\n")
  cat("that means this file was built after screening, so SAI was dropped upstream\n")
  cat("go back to the pre-screening file and merge the SAI columns back in on key (ID, Year)\n")
  cat("all column names in this file:\n"); print(nm)
  stop("SAI columns not available in this file.")
}

## ---------------------------------------------------------------------
## STEP 1 — data prep : sequential 11 channels x 8 months = 88 columns
## ---------------------------------------------------------------------
dt[, Y_num := as.numeric(as.character(factor(Y, levels = c(0,1), labels = c(0,1))))]
dt[, ADM3_idx := as.integer(as.factor(ADM3))]
num_adm3_classes <- max(dt$ADM3_idx, na.rm = TRUE); embed_dim <- 9

CH <- c("NDVI","NDWI","LST","Precipitation","SMAP","NTL","VHI","CRD","HSD","SAI_NDVI","SAI_NDWI")
MN <- 5:12

# 🔴 Name the columns exactly - no regex, no positional indexing
#    (a regex such as "_NDVI5$" would also catch norm_SAI_NDVI5)
PREFIX <- c(NDVI          = "norm_NDVI",
            NDWI          = "norm_NDWI",
            LST           = "norm_LST",
            Precipitation = "norm_Precipitation",
            SMAP          = "norm_SMAP",
            NTL           = "norm_log_NTL",
            VHI           = "norm_VHI",
            CRD           = "norm_Rainfall_Deficit",
            HSD           = "norm_Heat_Stress_Days",
            SAI_NDVI      = "norm_SAI_NDVI",
            SAI_NDWI      = "norm_SAI_NDWI")

seq_cols <- unlist(lapply(CH, function(c) paste0(PREFIX[[c]], MN)), use.names = FALSE)
missing_cols <- setdiff(seq_cols, nm)
if (length(missing_cols)) { cat("columns not found:\n"); print(missing_cols); stop("column names do not match") }
stopifnot(length(seq_cols) == 88)

# Confirm the first 72 columns match the file's original sequential block (positions 42:113)
if (identical(seq_cols[1:72], nm[42:113])) {
  cat("✅ first 72 columns match the original sequential block exactly, in the original order\n")
} else {
  cat("⚠️  order does not match 42:113 of the file - check before going on\n")
  print(data.frame(expected = seq_cols[1:12], file = nm[42:53]))
}

cat("\n================ STEP 1: sequential block ================\n")
print(matrix(seq_cols, nrow = 8, ncol = 11,
             dimnames = list(month = paste0("M", MN), channel = CH)))

drop_cols   <- c("Year","ID","Y","Y_num","ADM3","ADM3_idx")
static_cols <- setdiff(nm, c(drop_cols, seq_cols))
cat("\nstatic features:", length(static_cols), "\n")

train_data <- dt[Year %in% c(1,2)]; test_data <- dt[Year == 3]
y_train_raw <- train_data$Y_num;    y_test_raw <- test_data$Y_num

# The correct reshape: order month-major first, then reshape
col_map   <- matrix(seq_along(seq_cols), nrow = 8, ncol = 11)
seq_order <- as.vector(t(col_map))

x_train_seq <- as.matrix(train_data[, ..seq_cols])
x_test_seq  <- as.matrix(test_data[,  ..seq_cols])
x_train_seq_3d <- array_reshape(x_train_seq[, seq_order], c(nrow(x_train_seq), 8, 11))
x_test_seq_3d  <- array_reshape(x_test_seq[,  seq_order], c(nrow(x_test_seq),  8, 11))

stopifnot(all.equal(as.vector(x_train_seq_3d[1, , ]), as.vector(x_train_seq[1, col_map])))
cat("✅ tensor axes verified: dim2 = month, dim3 = channel (11)\n")

x_train_stat <- as.matrix(train_data[, ..static_cols])
x_test_stat  <- as.matrix(test_data[,  ..static_cols])
x_train_cat  <- train_data$ADM3_idx; x_test_cat <- test_data$ADM3_idx
static_dimension <- ncol(x_train_stat)
rm(dt, train_data, test_data, x_train_seq, x_test_seq); gc()

## ---------------------------------------------------------------------
## STEP 2 — model : identical to ST-CRAAN line for line, only shape = c(8, 11) differs
## ---------------------------------------------------------------------
build_hybrid_model <- function(lstm_hd, lr, drop_seq, drop_stat, num_layers = 2,
                               stat_hd = 64, lstm_layers = 1, wd_rate = 0.001, n_ch = 11) {
  super_clear_session()
  input_seq <- layer_input(shape = c(8, n_ch), name = "seq_input")
  x_seq <- input_seq
  if (lstm_layers > 1) for (j in 1:(lstm_layers - 1))
    x_seq <- x_seq %>% layer_lstm(units = lstm_hd, return_sequences = TRUE,
                                  kernel_regularizer = regularizer_l2(l = wd_rate)) %>%
                       layer_dropout(rate = drop_seq)
  lstm_out <- x_seq %>% layer_lstm(units = lstm_hd, return_sequences = FALSE,
                                   kernel_regularizer = regularizer_l2(l = wd_rate)) %>%
                        layer_dropout(rate = drop_seq)

  input_stat <- layer_input(shape = c(static_dimension), name = "stat_input")
  input_cat  <- layer_input(shape = c(1), name = "cat_input")
  emb_out <- input_cat %>% layer_embedding(input_dim = num_adm3_classes + 1,
                                           output_dim = embed_dim) %>% layer_flatten()

  h_stat <- layer_concatenate(list(input_stat, emb_out)) %>%
    layer_dense(units = stat_hd, kernel_initializer = initializer_lecun_uniform(),
                kernel_regularizer = regularizer_l2(l = wd_rate)) %>%
    layer_batch_normalization(momentum = 0.9, epsilon = 1e-5) %>%
    layer_activation("relu") %>% layer_dropout(rate = drop_stat)
  if (num_layers >= 2)
    h_stat <- h_stat %>%
      layer_dense(units = max(16, stat_hd / 2), kernel_initializer = initializer_lecun_uniform(),
                  kernel_regularizer = regularizer_l2(l = wd_rate)) %>%
      layer_batch_normalization(momentum = 0.9, epsilon = 1e-5) %>%
      layer_activation("relu") %>% layer_dropout(rate = drop_stat)

  fusion <- layer_concatenate(list(h_stat, lstm_out)) %>%
    layer_dense(units = 32, kernel_initializer = initializer_lecun_uniform(),
                activation = "relu", kernel_regularizer = regularizer_l2(l = wd_rate))
  output <- fusion %>% layer_dense(units = 1, activation = "sigmoid", name = "output")

  model <- keras_model(inputs = list(seq_input = input_seq, stat_input = input_stat,
                                     cat_input = input_cat), outputs = output)
  model %>% compile(optimizer = optimizer_adam(learning_rate = lr, epsilon = 1e-8, clipnorm = 1.0),
                    loss = "binary_crossentropy",
                    metrics = list(tf$keras$metrics$AUC(name = "auc")))
  model
}

model11 <- build_hybrid_model(lstm_hd = 64, lr = LR_USED, drop_seq = 0.20,
                              drop_stat = 0.2, lstm_layers = 2, wd_rate = 1e-4, n_ch = 11)

cat("\n================ STEP 2: training 11-channel model ================\n")
model11 %>% fit(
  x = list(seq_input = x_train_seq_3d, stat_input = x_train_stat, cat_input = x_train_cat),
  y = y_train_raw, epochs = EPOCHS_USED, batch_size = 2048,
  class_weight = list("0" = 1, "1" = 100/6.575), verbose = 1
)

## ---------------------------------------------------------------------
## STEP 3 — evaluate
## ---------------------------------------------------------------------
test_x <- list(seq_input = x_test_seq_3d, stat_input = x_test_stat, cat_input = x_test_cat)
p11 <- model11 %>% predict(test_x, batch_size = 512) %>% as.numeric()
fwrite(data.table(Actual = y_test_raw, Prob = p11), "STCRAAN11_predict.txt", sep = "|")
save_model_tf(model11, "HBDL2_Keras_11ch_Model")

r11 <- roc(y_test_raw, p11, direction = "<", quiet = TRUE)
cat("\n================ STEP 3: 11-channel ST-CRAAN ================\n")
cat(sprintf("AUC            %.5f   (9-ch 0.90057 | static-only 0.89681)\n", as.numeric(auc(r11))))
cat(sprintf("KS             %.5f   (9-ch 0.63710 | static-only 0.63251)\n",
            max(r11$sensitivities + r11$specificities - 1)))
cat(sprintf("Recall @0.5    %.4f\n", mean(p11[y_test_raw == 1] >= 0.5)))
cat(sprintf("pos rate @0.5  %.4f\n", mean(p11 >= 0.5)))

## ---------------------------------------------------------------------
## STEP 4 — compare with static-only at the same operating point  <<< the number we want
## ---------------------------------------------------------------------
ds <- fread("StaticOnly_predict.txt", sep = "|")
stopifnot(nrow(ds) == length(p11))
ps <- ds$Prob; ys <- ds$Actual

rate  <- mean(p11 >= 0.5)                 # operating point of the 11-channel model
thr_s <- quantile(ps, 1 - rate)
rec11 <- mean(p11[y_test_raw == 1] >= 0.5)
recS  <- mean(ps[ys == 1] >= thr_s)
P     <- sum(y_test_raw == 1)

cat("\n============ STEP 4: matched operating point ============\n")
cat(sprintf("predicted-positive rate      %.4f\n", rate))
cat(sprintf("Recall  ST-CRAAN 11-ch       %.4f   FN %d\n", rec11, round(P*(1-rec11))))
cat(sprintf("Recall  static-only          %.4f   FN %d\n", recS,  round(P*(1-recS))))
cat(sprintf("GAIN                         %+.2f pp   FN avoided %d\n",
            (rec11-recS)*100, round(P*(recS-rec11))))
cat(sprintf("   (9-channel gain was       +0.39 pp   FN avoided 704)\n"))

## ---------------------------------------------------------------------
## STEP 5 — switch off the whole sequential branch : how much does EO really contribute
## ---------------------------------------------------------------------
eps <- 1e-7; lg <- function(p) { p <- pmin(pmax(p, eps), 1-eps); log(p/(1-p)) }
mean_seq <- apply(x_test_seq_3d, MARGIN = c(2,3), FUN = mean, na.rm = TRUE)
for (t in 1:8) for (f in 1:11) test_x$seq_input[, t, f] <- mean_seq[t, f]
pz <- model11 %>% predict(test_x, batch_size = 512) %>% as.numeric()

cat("\n============ STEP 5: neutralise the whole EO branch ============\n")
cat(sprintf("AUC  before %.5f  ->  after %.5f   (lost %.5f)\n",
            as.numeric(auc(r11)),
            as.numeric(auc(roc(y_test_raw, pz, direction = "<", quiet = TRUE))),
            as.numeric(auc(r11)) - as.numeric(auc(roc(y_test_raw, pz, direction="<", quiet=TRUE)))))
cat(sprintf("mean |Delta logit|  %.6f   (9-channel model was 0.001919)\n",
            mean(abs(lg(p11) - lg(pz)))))
cat("\n🎉 done\n")
