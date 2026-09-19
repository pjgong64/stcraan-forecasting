# ==========================================
# 0. Load libraries and set up the environment (Keras/Windows)
# ==========================================
library(data.table)
library(caret)
library(pROC)
library(MLmetrics)

library(reticulate)
use_condaenv("tf-gpu", required = TRUE) 
library(keras)
py_require_legacy_keras() 
library(tensorflow)

# 🌟 Pull in Python's own memory manager so we can drive it from R
py_gc <- import("gc") 

cat("🚀 Initializing Dynamic Keras ST-HDL Model with PyTorch Style & Advanced GC...\n")

# Check for a GPU device
gpu_devices <- tf$config$list_physical_devices("GPU")
if (length(gpu_devices) > 0) {
  cat("🔥 Compute Device Detected: GPU (", gpu_devices[[1]]$name, ")\n")
} else {
  cat("⚠️ Compute Device Detected: CPU (Running without GPU)\n")
}

# ==========================================
# Function that clears memory root and branch (Super Clear Session)
# ==========================================
super_clear_session <- function() {
  k_clear_session()
  py_gc$collect()
  invisible(gc(reset = TRUE))
  tf$random$set_seed(64L) # lock the RNG so every run draws the same numbers
}

# ==========================================
# 1. Data preparation and stream split
# ==========================================
dt <- fread("data_hybrid2_prec.txt", sep = "|", encoding = "UTF-8")
dt[, Y_num := as.numeric(as.character(factor(Y, levels = c(0, 1), labels = c(0, 1))))]

# Encode ADM3 for the entity embedding
dt[, ADM3_idx := as.integer(as.factor(ADM3))]
num_adm3_classes <- max(dt$ADM3_idx, na.rm = TRUE)
embed_dim <- 9 

train_data <- dt[Year %in% c(1, 2)]
test_data  <- dt[Year == 3]

y_train_raw <- train_data$Y_num
y_test_raw  <- test_data$Y_num

# 🌟 Group the columns for the hybrid split
all_cols <- names(dt)
seq_cols <- all_cols[42:113]  # 72 features (8*9)
drop_cols <- c("Year", "ID", "Y", "Y_num", "ADM3", "ADM3_idx")
static_cols <- setdiff(all_cols, c(drop_cols, seq_cols))

# Split the data into matrices
x_train_seq <- as.matrix(train_data[, ..seq_cols])
x_test_seq  <- as.matrix(test_data[, ..seq_cols])

x_train_stat <- as.matrix(train_data[, ..static_cols])
x_test_stat  <- as.matrix(test_data[, ..static_cols])

x_train_cat <- train_data$ADM3_idx
x_test_cat  <- test_data$ADM3_idx

# 🌟 Keras needs the sequence data as a 3D array 
x_train_seq_3d <- array_reshape(x_train_seq, c(nrow(x_train_seq), 8, 9))
x_test_seq_3d  <- array_reshape(x_test_seq, c(nrow(x_test_seq), 8, 9))

static_dimension <- ncol(x_train_stat)

rm(dt, train_data, test_data, x_train_seq, x_test_seq)
gc()

# ==========================================
# 2. Function that builds the Keras hybrid model
# ==========================================
build_hybrid_model <- function(lstm_hd, lr, drop_seq, drop_stat, num_layers = 2, stat_hd = 64, lstm_layers = 1, wd_rate = 0.001) {
  
  # 🌟 Use the full memory wipe instead of k_clear_session()
  super_clear_session() 
  
  # -- Branch A: Sequential Branch (LSTM) --
  input_seq <- layer_input(shape = c(8, 9), name = "seq_input")
  x_seq <- input_seq
  
  if (lstm_layers > 1) {
    for (j in 1:(lstm_layers - 1)) {
      x_seq <- x_seq %>% 
        layer_lstm(units = lstm_hd, return_sequences = TRUE, kernel_regularizer = regularizer_l2(l = wd_rate)) %>% 
        layer_dropout(rate = drop_seq)
    }
  }
  lstm_out <- x_seq %>% 
    layer_lstm(units = lstm_hd, return_sequences = FALSE, kernel_regularizer = regularizer_l2(l = wd_rate)) %>% 
    layer_dropout(rate = drop_seq)
  
  # -- Branch B: Static Branch (Numeric + Entity Embedding) --
  input_stat <- layer_input(shape = c(static_dimension), name = "stat_input")
  
  input_cat <- layer_input(shape = c(1), name = "cat_input")
  emb_out <- input_cat %>% 
    layer_embedding(input_dim = num_adm3_classes + 1, output_dim = embed_dim) %>% 
    layer_flatten()
  
  # 🌟 Upgraded static branch: PyTorch style (LeCun init, BN momentum 0.9)
  h_stat <- layer_concatenate(list(input_stat, emb_out)) %>% 
    layer_dense(
      units = stat_hd, 
      kernel_initializer = initializer_lecun_uniform(), # 🌟 weight init mirroring PyTorch
      kernel_regularizer = regularizer_l2(l = wd_rate)
    ) %>% 
    layer_batch_normalization(momentum = 0.9, epsilon = 1e-5) %>% # 🌟 PyTorch-style BN
    layer_activation("relu") %>%                      
    layer_dropout(rate = drop_stat)
  
  if (num_layers >= 2) {
    h_stat <- h_stat %>% 
      layer_dense(
        units = max(16, stat_hd / 2), 
        kernel_initializer = initializer_lecun_uniform(), 
        kernel_regularizer = regularizer_l2(l = wd_rate)
      ) %>% 
      layer_batch_normalization(momentum = 0.9, epsilon = 1e-5) %>% 
      layer_activation("relu") %>% 
      layer_dropout(rate = drop_stat)
  }
  
  # -- Fusion --
  fusion <- layer_concatenate(list(h_stat, lstm_out)) %>% 
    layer_dense(
      units = 32, 
      kernel_initializer = initializer_lecun_uniform(),   
      activation = "relu", 
      kernel_regularizer = regularizer_l2(l = wd_rate)
    )
  
  # The output layer needs no LeCun init because we use a sigmoid (Keras's default Glorot is already best)
  output <- fusion %>% layer_dense(units = 1, activation = "sigmoid", name = "output")
  
  model <- keras_model(inputs = list(seq_input = input_seq, stat_input = input_stat, cat_input = input_cat), 
                       outputs = output)
  
  model %>% compile(
    optimizer = optimizer_adam(learning_rate = lr, epsilon = 1e-8, clipnorm = 1.0), # 🌟 PyTorch Optimizer Style
    loss = "binary_crossentropy",
    metrics = list(tf$keras$metrics$AUC(name = "auc"))
  )
  
  return(model)
}

# 📌 Global Parameters (taken from the baseline run)
mlp_best_layers  <- 2
mlp_best_nodes   <- 128
mlp_best_dropout <- 0.2 
batch_size       <- 2048

# ==========================================
# 3. Stratified 20% sample for tuning
# ==========================================
cat("\n🚀 Sampling 20% Stratified Data for Hyperparameter Tuning...\n")

set.seed(64)
tune_idx <- as.vector(createDataPartition(y_train_raw, p = 0.2, list = FALSE))

t_x_stat_full <- x_train_stat[tune_idx, ]
t_x_seq_full  <- x_train_seq_3d[tune_idx, , ]
t_x_cat_full  <- x_train_cat[tune_idx]
t_y_full      <- y_train_raw[tune_idx]

set.seed(64)
train_t_idx <- as.vector(createDataPartition(t_y_full, p = 0.8, list = FALSE))

tune_tr_x <- list(
  stat_input = t_x_stat_full[train_t_idx, ],
  seq_input  = array_reshape(t_x_seq_full[train_t_idx, , ], c(length(train_t_idx), 8, 9)),
  cat_input  = t_x_cat_full[train_t_idx]
)
tune_tr_y <- t_y_full[train_t_idx]

tune_val_x <- list(
  stat_input = t_x_stat_full[-train_t_idx, ],
  seq_input  = array_reshape(t_x_seq_full[-train_t_idx, , ], c(length(t_y_full) - length(train_t_idx), 8, 9)),
  cat_input  = t_x_cat_full[-train_t_idx]
)
tune_val_y <- t_y_full[-train_t_idx]

rm(t_x_stat_full, t_x_seq_full, t_x_cat_full, t_y_full)
gc()

# ==========================================
# 4. Targeted Hyperparameter Tuning (Keras)
# ==========================================
grid_lstm        <- c(64)        
grid_lr          <- c(0.001, 0.0001) 
grid_drop_seq    <- c(0.20) 
grid_lstm_layers <- c(2)            
grid_wd          <- c(0.0001)   
grid_weight_1    <- c(100/6.575) 

all_configs <- expand.grid(
  lstm = grid_lstm, lr = grid_lr, drop_seq = grid_drop_seq,
  lstm_layers = grid_lstm_layers, wd = grid_wd, weight_1 = grid_weight_1
) 

best_auc_tune <- 0
best_hybrid_params <- list() 



# 1. Emergency brake: stop training if AUC does not improve by 0.0002 for 3 epochs
early_stop <- tf$keras$callbacks$EarlyStopping(
  monitor = "val_auc", mode = "max", patience = 3L, min_delta = 0.0002, restore_best_weights = TRUE
)

# 2. Automatic descent: halve the Learning Rate if AUC stalls for more than 5 Epochs
reduce_lr <- callback_reduce_lr_on_plateau(
  monitor = "val_auc", 
  factor = 0.5, 
  patience = 2L, 
  min_lr = 1e-6, 
  verbose = 1 # 🌟 print to the console whenever the LR is cut, so we can see it working
)


for (i in 1:nrow(all_configs)) {
  cfg <- all_configs[i, ]
  
  cat(sprintf("\n🛠️ Config %d/%d -> LSTM: %d | Lyr: %d | LR: %.4f | Drop: %.2f | WD: %g | W1: %.2f ...\n", i, nrow(all_configs), cfg$lstm, cfg$lstm_layers, cfg$lr, cfg$drop_seq, cfg$wd, cfg$weight_1))
  
  model <- build_hybrid_model(
    lstm_hd = cfg$lstm, lr = cfg$lr, drop_seq = cfg$drop_seq, 
    drop_stat = mlp_best_dropout, lstm_layers = cfg$lstm_layers, wd_rate = cfg$wd                
  )
  
  current_class_weights <- list("0" = 1, "1" = cfg$weight_1)
  
  history <- model %>% fit(
    x = tune_tr_x, y = tune_tr_y, validation_data = list(tune_val_x, tune_val_y),
    epochs = 100, batch_size = batch_size, callbacks = list(early_stop, reduce_lr), 
    class_weight = current_class_weights, verbose = 1 
  )
  
  val_auc_max <- max(history$metrics$val_auc)
  best_ep <- which.max(history$metrics$val_auc)
  
  cat(sprintf("✅ Result -> AUC: %.4f (Stop at Epoch: %d)\n", val_auc_max, best_ep))
  
  if (val_auc_max > best_auc_tune) {
    best_auc_tune <- val_auc_max
    best_hybrid_params <- cfg
    best_hybrid_params$epochs <- best_ep
  }
}

rm(tune_tr_x, tune_tr_y, tune_val_x, tune_val_y)
gc()

cat("\n🎉 Tuning Complete! Best Parameters:\n")
print(best_hybrid_params)

# ==========================================
# 5. Running 5-Fold Stratified CV
# ==========================================
cat("\nStarting 5-Fold Stratified CV for Hybrid Model...\n")
set.seed(64)
folds <- createFolds(as.factor(y_train_raw), k = 10, list = TRUE, returnTrain = FALSE)
all_metrics_df <- data.frame(Metric = c("Accuracy", "Precision", "Recall", "F1-Score", "AUC-ROC", "Gini", "KS_Stat", "Train_Time_s", "Inference_Time_s"))

# Take the best class weight from tuning and have it ready for use
best_weights_for_training <- list("0" = 1, "1" = best_hybrid_params$weight_1)

for(i in 1:length(folds)) {
  val_idx <- folds[[i]]
  
  fold_tr_x <- list(
    stat_input = x_train_stat[-val_idx, ],
    seq_input  = array_reshape(x_train_seq_3d[-val_idx, , ], c(nrow(x_train_stat) - length(val_idx), 8, 9)),
    cat_input  = x_train_cat[-val_idx]
  )
  fold_val_x <- list(
    stat_input = x_train_stat[val_idx, ],
    seq_input  = array_reshape(x_train_seq_3d[val_idx, , ], c(length(val_idx), 8, 9)),
    cat_input  = x_train_cat[val_idx]
  )
  
  model <- build_hybrid_model(
    lstm_hd = best_hybrid_params$lstm, lr = best_hybrid_params$lr, 
    drop_seq = best_hybrid_params$drop_seq, drop_stat = mlp_best_dropout,
    lstm_layers = best_hybrid_params$lstm_layers, wd_rate = best_hybrid_params$wd
  )
  
  # 🌟 Time the training for this fold
  start_train_cv <- Sys.time()
  model %>% fit(
    x = fold_tr_x, y = y_train_raw[-val_idx], validation_data = list(fold_val_x, y_train_raw[val_idx]),
    epochs = best_hybrid_params$epochs + 5, batch_size = batch_size, 
    callbacks = list(early_stop), class_weight = best_weights_for_training, verbose = 1
  )
  train_time_cv <- as.numeric(difftime(Sys.time(), start_train_cv, units = "secs"))
  
  # 🌟 Time the inference for this fold
  start_inf_cv <- Sys.time()
  val_prob <- model %>% predict(fold_val_x, batch_size = 512) %>% as.numeric()
  inf_time_cv <- as.numeric(difftime(Sys.time(), start_inf_cv, units = "secs"))
  
  val_pred_class <- ifelse(val_prob >= 0.5, 1, 0)
  pred_f <- factor(val_pred_class, levels = c(0, 1), labels = c("Payable", "Default"))
  actual_f <- factor(y_train_raw[val_idx], levels = c(0, 1), labels = c("Payable", "Default"))
  
  cm_fold <- confusionMatrix(pred_f, actual_f, positive = "Default")
  fold_roc <- roc(y_train_raw[val_idx], val_prob, direction = "<", quiet = TRUE)
  f_auc <- auc(fold_roc)
  
  # Record Train_Time_s and Inference_Time_s in place of the NAs
  all_metrics_df[[paste0("Fold_", i)]] <- c(cm_fold$overall["Accuracy"], cm_fold$byClass["Pos Pred Value"], cm_fold$byClass["Sensitivity"], cm_fold$byClass["F1"], f_auc, (2 * f_auc) - 1, max(fold_roc$sensitivities + fold_roc$specificities - 1), train_time_cv, inf_time_cv)
  
  cat(sprintf("⭐ Fold %d completed | AUC: %.4f | Train Time: %.2fs | Inf Time: %.2fs\n", i, f_auc, train_time_cv, inf_time_cv))
}

# ==========================================
# 6. Train the final model & evaluate (Final Model)
# ==========================================
cat("\n🚀 Training final Hybrid Model on full dataset...\n")

final_tr_x <- list(stat_input = x_train_stat, seq_input = x_train_seq_3d, cat_input = x_train_cat)
final_test_x <- list(stat_input = x_test_stat, seq_input = x_test_seq_3d, cat_input = x_test_cat)

final_model <- build_hybrid_model(
  lstm_hd = best_hybrid_params$lstm, lr = best_hybrid_params$lr, 
  drop_seq = best_hybrid_params$drop_seq, drop_stat = mlp_best_dropout,
  lstm_layers = best_hybrid_params$lstm_layers, wd_rate = best_hybrid_params$wd
)

# 🌟 Time the training of the final model
start_train <- Sys.time()
final_model %>% fit(
  x = final_tr_x, y = y_train_raw, epochs = best_hybrid_params$epochs, 
  batch_size = batch_size, class_weight = best_weights_for_training, verbose = 1 
)
train_time_sec <- as.numeric(difftime(Sys.time(), start_train, units = "secs"))

cat("\n📊 Evaluating on Test Set (Year 3)...\n")

# 🌟 Time the inference on the Test set
start_inf <- Sys.time()
test_prob <- final_model %>% predict(final_test_x, batch_size = 512) %>% as.numeric()
inference_time_sec <- as.numeric(difftime(Sys.time(), start_inf, units = "secs"))

cat(sprintf("\n✅ Final Model Trained in %.2f seconds | Inference took %.2f seconds\n", train_time_sec, inference_time_sec))

test_pred_class <- ifelse(test_prob >= 0.5, 1, 0)
pred_factor <- factor(test_pred_class, levels = c(0, 1), labels = c("Payable", "Default"))
actual_factor <- factor(y_test_raw, levels = c(0, 1), labels = c("Payable", "Default"))

cm_test <- confusionMatrix(pred_factor, actual_factor, positive = "Default")
roc_test <- roc(y_test_raw, test_prob, direction = "<", quiet = TRUE)
AUC_Value <- auc(roc_test)

pred_df <- data.table(Actual_Class = actual_factor, Predicted_Class = pred_factor, Predicted_Prob = test_prob)

all_metrics_df$Test_Set <- c(cm_test$overall["Accuracy"], cm_test$byClass["Pos Pred Value"], cm_test$byClass["Sensitivity"], cm_test$byClass["F1"], AUC_Value, (2 * AUC_Value) - 1, max(roc_test$sensitivities + roc_test$specificities - 1), train_time_sec, inference_time_sec)
all_metrics_df[, -1] <- round(all_metrics_df[, -1], 4)

print("\n=======================================================")
print("--- Summary of All Folds and Test Set (ST-HDL - Keras) ---")
print("=======================================================")
print(all_metrics_df)

write.csv(all_metrics_df, "HB_DL2_Keras.csv", row.names = FALSE)
saveRDS(roc_test, "ROC_HB_DL2_Keras.rds")
saveRDS(cm_test, "CM_HB_DL2_Keras.rds")
save_model_tf(final_model, "HBDL2_Keras_Final_Model")
fwrite(pred_df, "HB_DL2_Keras_predict.txt", sep = "|", encoding = "UTF-8")

cat("\n🎉 Process finished successfully! Keras has completed the run without crashing.\n")
