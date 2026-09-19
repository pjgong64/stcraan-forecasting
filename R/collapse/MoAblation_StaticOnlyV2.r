### STCRAAN Modelity Ablation
### Only Static + Entity Em
# ==========================================
# 0. Load libraries and set up
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

py_gc <- import("gc") 
cat("🚀 Initializing Keras STATIC-ONLY (With Entity Embedding) Model...\n")

super_clear_session <- function() {
  k_clear_session()
  py_gc$collect()
  invisible(gc(reset = TRUE))
  tf$random$set_seed(64L)
}

# ==========================================
# 1. Data preparation (keep both Static Numeric and Categorical)
# ==========================================
super_clear_session()

dt <- fread("data_hybrid2_prec.txt", sep = "|", encoding = "UTF-8")
dt[, Y_num := as.numeric(as.character(factor(Y, levels = c(0, 1), labels = c(0, 1))))]

# 🌟 Keep the Entity Embedding (no longer dropped)
dt[, ADM3_idx := as.integer(as.factor(ADM3))]
num_adm3_classes <- max(dt$ADM3_idx, na.rm = TRUE)
embed_dim <- 9 

train_data <- dt[Year %in% c(1, 2)]
test_data  <- dt[Year == 3]

y_train_raw <- train_data$Y_num
y_test_raw  <- test_data$Y_num

all_cols <- names(dt)
seq_cols <- all_cols[42:113]  
drop_cols <- c("Year", "ID", "Y", "Y_num", "ADM3", "ADM3_idx")
static_cols <- setdiff(all_cols, c(drop_cols, seq_cols))

# Split out the Matrix data
x_train_stat <- as.matrix(train_data[, ..static_cols])
x_test_stat  <- as.matrix(test_data[, ..static_cols])

# 🌟 Prepare the Category variable for the Embedding
x_train_cat <- train_data$ADM3_idx
x_test_cat  <- test_data$ADM3_idx

input_dim_static <- ncol(x_train_stat)

rm(dt, train_data, test_data)
gc()

LR_USED     <- 0.001   # 🔴 same lr as ST-CRAAN
EPOCHS_USED <- 10      # 🔴 same epochs as ST-CRAAN

# ---------- 2. Static-only model whose structure matches ST-CRAAN's static branch ----------
build_static_model <- function(input_dim, num_classes, emb_dim,
                               lr, wd_rate = 1e-4, stat_hd = 64, drop_stat = 0.2) {
  super_clear_session()
  static_input <- layer_input(shape = c(input_dim), name = "stat_input")
  cat_input    <- layer_input(shape = c(1), name = "cat_input")
  emb_out <- cat_input %>%
    layer_embedding(input_dim = num_classes + 1, output_dim = emb_dim) %>% layer_flatten()
  
  h <- layer_concatenate(list(static_input, emb_out)) %>%
    layer_dense(units = stat_hd, kernel_initializer = initializer_lecun_uniform(),
                kernel_regularizer = regularizer_l2(l = wd_rate)) %>%
    layer_batch_normalization(momentum = 0.9, epsilon = 1e-5) %>%
    layer_activation("relu") %>% layer_dropout(rate = drop_stat) %>%
    layer_dense(units = max(16, stat_hd / 2), kernel_initializer = initializer_lecun_uniform(),
                kernel_regularizer = regularizer_l2(l = wd_rate)) %>%
    layer_batch_normalization(momentum = 0.9, epsilon = 1e-5) %>%
    layer_activation("relu") %>% layer_dropout(rate = drop_stat)
  
  # ST-CRAAN fusion layer — kept so the depth is the same, the only difference is that no lstm_out is concatenated in
  out <- h %>% layer_dense(units = 32, kernel_initializer = initializer_lecun_uniform(),
                           activation = "relu", kernel_regularizer = regularizer_l2(l = wd_rate)) %>%
    layer_dense(units = 1, activation = "sigmoid", name = "output")
  
  model <- keras_model(inputs = list(stat_input = static_input, cat_input = cat_input), outputs = out)
  model %>% compile(optimizer = optimizer_adam(learning_rate = lr, epsilon = 1e-8, clipnorm = 1.0),
                    loss = "binary_crossentropy",
                    metrics = list(tf$keras$metrics$AUC(name = "auc")))
  model
}

static_model <- build_static_model(input_dim_static, num_adm3_classes, embed_dim, lr = LR_USED)

# ---------- 3. Train — 🌟 apply the same class_weight as ST-CRAAN ----------
static_model %>% fit(
  x = list(stat_input = x_train_stat, cat_input = x_train_cat),
  y = y_train_raw,
  batch_size = 2048,
  epochs = EPOCHS_USED,
  class_weight = list("0" = 1, "1" = 100/6.575),
  verbose = 1
)

# ---------- 4. Evaluate + compare at the same operating point ----------
p_static <- static_model %>% predict(list(stat_input = x_test_stat, cat_input = x_test_cat),
                                     batch_size = 512) %>% as.numeric()
fwrite(data.table(Actual = y_test_raw, Prob = p_static),
       "StaticOnly_predict.txt", sep = "|")

r_s <- roc(y_test_raw, p_static, direction = "<", quiet = TRUE)

cat("\n===== STATIC-ONLY (all variables controlled) =====\n")
cat(sprintf("AUC            %.5f\n", as.numeric(auc(r_s))))
cat(sprintf("KS             %.5f\n", max(r_s$sensitivities + r_s$specificities - 1)))
cat(sprintf("Recall @0.5    %.4f\n", mean(p_static[y_test_raw == 1] >= 0.5)))
cat(sprintf("pos rate @0.5  %.4f\n", mean(p_static >= 0.5)))
cat(sprintf("FN             %d\n", sum(p_static[y_test_raw == 1] < 0.5)))

d_full <- fread("STCRAAN/HB_DL2_Keras_predict.txt", sep = "|", encoding = "UTF-8")
y_f <- as.integer(d_full$Actual_Class == "Default"); p_f <- d_full$Predicted_Prob

rate <- mean(p_f >= 0.5)   # ST-CRAAN rate of risk predictions
thr_s <- quantile(p_static, 1 - rate)

cat("\n===== compared at the same operating point =====\n")
cat(sprintf("positive rate               %.4f\n", rate))
cat(sprintf("Recall  ST-CRAAN            %.4f\n", mean(p_f[y_f == 1] >= 0.5)))
cat(sprintf("Recall  static-only         %.4f\n", mean(p_static[y_test_raw == 1] >= thr_s)))
cat(sprintf("AUC     ST-CRAAN            %.5f\n", as.numeric(auc(roc(y_f, p_f, direction="<", quiet=TRUE)))))
cat(sprintf("AUC     static-only         %.5f\n", as.numeric(auc(r_s))))

