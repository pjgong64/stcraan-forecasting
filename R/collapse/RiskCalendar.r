library(data.table); library(pROC); library(reticulate)
use_condaenv("tf-gpu", required = TRUE)
library(keras); py_require_legacy_keras(); library(tensorflow)
py_gc <- import("gc")

# 🌟 do not let TF reserve the whole GPU up front
gpus <- tf$config$list_physical_devices("GPU")
if (length(gpus) > 0) tf$config$experimental$set_memory_growth(gpus[[1]], TRUE)

# ---------- load data ----------

dt <- fread("data_hybrid2_prec.txt", sep = "|", encoding = "UTF-8")
dt[, Y_num := as.numeric(as.character(factor(Y, levels = c(0,1), labels = c(0,1))))]
dt[, ADM3_idx := as.integer(as.factor(ADM3))]
test_data <- dt[Year == 3]; y_all <- test_data$Y_num

all_cols  <- names(dt)
seq_cols  <- all_cols[42:113]
drop_cols <- c("Year","ID","Y","Y_num","ADM3","ADM3_idx")
static_cols <- setdiff(all_cols, c(drop_cols, seq_cols))

col_map   <- matrix(seq_along(seq_cols), nrow = 8, ncol = 9)
seq_order <- as.vector(t(col_map))                      # 🌟 month-major

seq_all  <- array_reshape(as.matrix(test_data[, ..seq_cols])[, seq_order],
                          c(nrow(test_data), 8, 9))
stat_all <- as.matrix(test_data[, ..static_cols])
cat_all  <- test_data$ADM3_idx
rm(dt, test_data); gc()

# ---------- stratified subsample ----------
target <- 200000L
set.seed(64)
n1 <- round(target * mean(y_all == 1)); n0 <- target - n1
idx <- c(sample(which(y_all == 1), n1), sample(which(y_all == 0), n0))

X <- list(seq_input  = seq_all[idx, , , drop = FALSE],
          stat_input = stat_all[idx, , drop = FALSE],
          cat_input  = cat_all[idx])
y <- y_all[idx]
rm(seq_all, stat_all, cat_all); gc()

mean_seq_vals <- apply(X$seq_input, MARGIN = c(2,3), FUN = mean, na.rm = TRUE)

model <- load_model_tf("STCRAAN/HBDL2_Keras_Final_Model")

# ---------- 🌟 predict in chunks ----------
predict_chunked <- function(model, X, chunk = 50000L) {
  n <- length(X$cat_input); out <- numeric(n)
  for (s in seq(1L, n, by = chunk)) {
    e <- min(s + chunk - 1L, n); i <- s:e
    out[i] <- as.numeric(predict(model, list(
      seq_input  = X$seq_input[i, , , drop = FALSE],
      stat_input = X$stat_input[i, , drop = FALSE],
      cat_input  = X$cat_input[i]
    ), batch_size = 512L, verbose = 0))
  }
  out
}

# ---------- perturbation ----------
timesteps <- c("May","June","July","August","September","October","November","December")
seq_feature_names <- c("NDVI","NDWI","LST","Precipitation","SMAP","NTL","VHI","CRD","HSD")
eps <- 1e-7; lg <- function(p) { p <- pmin(pmax(p, eps), 1-eps); log(p/(1-p)) }

base_p <- predict_chunked(model, X); base_l <- lg(base_p)
base_auc <- as.numeric(auc(roc(y, base_p, direction = "<", quiet = TRUE)))
cat(sprintf("Baseline AUC: %.6f\n", base_auc))

dn <- list(month = timesteps, channel = seq_feature_names)
imp_abs <- imp_signed <- imp_auc <- matrix(0, 8, 9, dimnames = dn)

for (t in 1:8) for (f in 1:9) {
  orig <- X$seq_input[, t, f]
  X$seq_input[, t, f] <- mean_seq_vals[t, f]
  
  p <- predict_chunked(model, X)
  d <- base_l - lg(p)
  imp_abs[t,f]    <- mean(abs(d))
  imp_signed[t,f] <- mean(d)
  imp_auc[t,f]    <- base_auc - as.numeric(auc(roc(y, p, direction = "<", quiet = TRUE)))
  
  X$seq_input[, t, f] <- orig
  py_gc$collect(); gc()
  cat(sprintf("  %-10s x %-14s  |Δlogit|=%.6f\n", timesteps[t], seq_feature_names[f], imp_abs[t,f]))
}

print(round(rowSums(imp_abs), 6))
write.csv(cbind(month = timesteps, as.data.frame(imp_abs)),    "RiskCalendar_absLogOdds.csv", row.names = FALSE)
write.csv(cbind(month = timesteps, as.data.frame(imp_signed)), "RiskCalendar_signed.csv",     row.names = FALSE)
write.csv(cbind(month = timesteps, as.data.frame(imp_auc)),    "RiskCalendar_AUCdrop.csv",    row.names = FALSE)

# ---------- M6: direction and shape of each channel ----------
# Sign: + = pushes toward Default   (reversed relative to the previous script)
qs   <- c(0.10, 0.25, 0.50, 0.75, 0.90)
resp <- matrix(0, length(qs), 9,
               dimnames = list(quantile = paste0("q", qs*100), channel = seq_feature_names))

for (f in 1:9) {
  orig <- X$seq_input[, , f]
  vals <- quantile(as.vector(orig), probs = qs, na.rm = TRUE)
  for (k in seq_along(qs)) {
    X$seq_input[, , f] <- vals[k]           # pin all 8 months at that quantile
    p <- predict_chunked(model, X)
    resp[k, f] <- mean(lg(p) - base_l)
  }
  X$seq_input[, , f] <- orig
  py_gc$collect(); gc()
  cat(sprintf("  %-14s done\n", seq_feature_names[f]))
}
print(round(resp, 5))
write.csv(cbind(quantile = rownames(resp), as.data.frame(resp)),
          "ChannelResponse_quantile.csv", row.names = FALSE)
