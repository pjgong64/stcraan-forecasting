# ==========================================
# Control: shuffled month order — everything matches the real model except the ordering of months
# ==========================================
LR_USED     <- 0.001   # 🔴 set the lr the real model used
EPOCHS_USED <- 10      # 🔴 set the epoch count the real model used
# (read them off the console log at "🎉 Tuning Complete! Best Parameters:")

library(data.table); library(caret); library(pROC); library(reticulate)
use_condaenv("tf-gpu", required = TRUE)
library(keras); py_require_legacy_keras(); library(tensorflow)
py_gc <- import("gc")
gpus <- tf$config$list_physical_devices("GPU")
if (length(gpus) > 0) tf$config$experimental$set_memory_growth(gpus[[1]], TRUE)

# ---------- 1. Data + correct reshape ----------
dt <- fread("data_hybrid2_prec.txt", sep = "|", encoding = "UTF-8")
dt[, Y_num := as.numeric(as.character(factor(Y, levels = c(0,1), labels = c(0,1))))]
dt[, ADM3_idx := as.integer(as.factor(ADM3))]
num_adm3_classes <- max(dt$ADM3_idx, na.rm = TRUE); embed_dim <- 9

train_data <- dt[Year %in% c(1,2)]; test_data <- dt[Year == 3]
y_train_raw <- train_data$Y_num;    y_test_raw <- test_data$Y_num

all_cols  <- names(dt)
seq_cols  <- all_cols[42:113]
drop_cols <- c("Year","ID","Y","Y_num","ADM3","ADM3_idx")
static_cols <- setdiff(all_cols, c(drop_cols, seq_cols))

col_map   <- matrix(seq_along(seq_cols), nrow = 8, ncol = 9)
seq_order <- as.vector(t(col_map))

x_train_seq_3d <- array_reshape(as.matrix(train_data[, ..seq_cols])[, seq_order],
                                c(nrow(train_data), 8, 9))
x_test_seq_3d  <- array_reshape(as.matrix(test_data[,  ..seq_cols])[, seq_order],
                                c(nrow(test_data), 8, 9))
x_train_stat <- as.matrix(train_data[, ..static_cols])
x_test_stat  <- as.matrix(test_data[,  ..static_cols])
x_train_cat  <- train_data$ADM3_idx; x_test_cat <- test_data$ADM3_idx
static_dimension <- ncol(x_train_stat)
rm(dt, train_data, test_data); gc()

# ---------- 2. 🌟 Shuffle the month order ----------
set.seed(64)
month_perm <- sample(8)
cat("Month permutation:", month_perm, "\n")
x_train_seq_3d <- x_train_seq_3d[, month_perm, , drop = FALSE]
x_test_seq_3d  <- x_test_seq_3d[,  month_perm, , drop = FALSE]

# ---------- 3. Model (line for line the same as the real one) ----------
super_clear_session <- function() {
  k_clear_session(); py_gc$collect(); invisible(gc(reset = TRUE))
  tf$random$set_seed(64L)
}

build_hybrid_model <- function(lstm_hd, lr, drop_seq, drop_stat, num_layers = 2,
                               stat_hd = 64, lstm_layers = 1, wd_rate = 0.001) {
  super_clear_session()
  input_seq <- layer_input(shape = c(8, 9), name = "seq_input")
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
    layer_dense(units = max(16, stat_hd / 2),
                kernel_initializer = initializer_lecun_uniform(),
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

# ---------- 4. Train the final model only ----------
final_model <- build_hybrid_model(lstm_hd = 64, lr = LR_USED, drop_seq = 0.20,
                                  drop_stat = 0.2, lstm_layers = 2, wd_rate = 1e-4)

final_model %>% fit(
  x = list(stat_input = x_train_stat, seq_input = x_train_seq_3d, cat_input = x_train_cat),
  y = y_train_raw, epochs = EPOCHS_USED, batch_size = 2048,
  class_weight = list("0" = 1, "1" = 100/6.575), verbose = 1
)

# ---------- 5. Evaluate ----------
final_test_x <- list(stat_input = x_test_stat, seq_input = x_test_seq_3d, cat_input = x_test_cat)
test_prob <- final_model %>% predict(final_test_x, batch_size = 512) %>% as.numeric()
pred_f   <- factor(ifelse(test_prob >= 0.5, 1, 0), levels = c(0,1), labels = c("Payable","Default"))
actual_f <- factor(y_test_raw, levels = c(0,1), labels = c("Payable","Default"))
cm  <- confusionMatrix(pred_f, actual_f, positive = "Default")
rc  <- roc(y_test_raw, test_prob, direction = "<", quiet = TRUE)

cat("\n=========== SHUFFLED-MONTH CONTROL ===========\n")
cat(sprintf("Accuracy  %.4f   (real model 0.8220)\n", cm$overall["Accuracy"]))
cat(sprintf("Precision %.4f   (real model 0.3868)\n", cm$byClass["Pos Pred Value"]))
cat(sprintf("Recall    %.4f   (real model 0.8128)\n", cm$byClass["Sensitivity"]))
cat(sprintf("AUC       %.4f   (real model 0.9006)\n", as.numeric(auc(rc))))
cat(sprintf("KS        %.4f   (real model 0.6371)\n", max(rc$sensitivities + rc$specificities - 1)))

save_model_tf(final_model, "HBDL2_Keras_Shuffle_Model")
saveRDS(month_perm, "month_perm.rds")
cat("\n✅ saved. Next, run the Risk Calendar on this model\n")

