# =============================================================================
#  sequence.r  --  score a saved month permutation against a trained model
#  ---------------------------------------------------------------------------
#  WHICH MODEL THIS LOADS IS THE WHOLE EXPERIMENT. Set it deliberately.
#
#    HBDL2_Keras_Shuffle_Model   the network TRAINED on shuffled months
#                                (written by STCRAAN_shuffle_month.r). Loading
#                                this asks: does a model trained on scrambled
#                                time learn a different position profile?
#
#    HBDL2_Keras_Final_Model     the production network, trained on real month
#                                order. Loading this instead asks a different
#                                question: how does the production model respond
#                                when its input months are permuted at scoring
#                                time -- permutation importance, not a trained
#                                control.
#
#  Both are legitimate; they are not the same experiment, and the banner further
#  down says "SHUFFLED MODEL". Whichever you pick, the path is printed at load
#  so the console record cannot disagree with the file it read.
# =============================================================================
MODEL_PATH <- "STCRAAN/HBDL2_Keras_Final_Model"

library(data.table); library(pROC); library(reticulate)
use_condaenv("tf-gpu", required = TRUE)
library(keras); py_require_legacy_keras(); library(tensorflow)
py_gc <- import("gc")
gpus <- tf$config$list_physical_devices("GPU")
if (length(gpus) > 0) tf$config$experimental$set_memory_growth(gpus[[1]], TRUE)

# ---------- Data ----------
dt <- fread("data_hybrid2_prec.txt", sep = "|", encoding = "UTF-8")
dt[, Y_num := as.numeric(as.character(factor(Y, levels = c(0,1), labels = c(0,1))))]
dt[, ADM3_idx := as.integer(as.factor(ADM3))]
test_data <- dt[Year == 3]; y_all <- test_data$Y_num

all_cols  <- names(dt)
seq_cols  <- all_cols[42:113]
drop_cols <- c("Year","ID","Y","Y_num","ADM3","ADM3_idx")
static_cols <- setdiff(all_cols, c(drop_cols, seq_cols))

col_map   <- matrix(seq_along(seq_cols), nrow = 8, ncol = 9)
seq_order <- as.vector(t(col_map))

seq_all  <- array_reshape(as.matrix(test_data[, ..seq_cols])[, seq_order],
                          c(nrow(test_data), 8, 9))

# ---------- 🌟 Shuffle months with the saved permutation ----------
month_perm <- readRDS("month_perm.rds")
cat("Month permutation:", month_perm, "\n")
seq_all <- seq_all[, month_perm, , drop = FALSE]

stat_all <- as.matrix(test_data[, ..static_cols])
cat_all  <- test_data$ADM3_idx
rm(dt, test_data); gc()

# ---------- subsample ----------
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

# ---------- 🌟 Load the model named at the top of this file ----------
if (!dir.exists(MODEL_PATH) && !file.exists(MODEL_PATH))
  stop(sprintf("model not found: %s -- see the header of this script", MODEL_PATH))
cat(sprintf("\nmodel loaded: %s\n", MODEL_PATH))
model <- load_model_tf(MODEL_PATH)

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
seq_feature_names <- c("NDVI","NDWI","LST","Precipitation","SMAP","NTL","VHI","CRD","HSD")
# 🔴 these are position labels, not month labels — the months have already been shuffled
pos_names <- paste0("pos", 1:8)

eps <- 1e-7; lg <- function(p) { p <- pmin(pmax(p, eps), 1-eps); log(p/(1-p)) }

base_p <- predict_chunked(model, X); base_l <- lg(base_p)
imp_abs <- matrix(0, 8, 9, dimnames = list(position = pos_names, channel = seq_feature_names))

for (t in 1:8) for (f in 1:9) {
  orig <- X$seq_input[, t, f]
  X$seq_input[, t, f] <- mean_seq_vals[t, f]
  p <- predict_chunked(model, X)
  imp_abs[t, f] <- mean(abs(base_l - lg(p)))
  X$seq_input[, t, f] <- orig
  py_gc$collect(); gc()
  cat(sprintf("  pos%d x %-14s  %.6f\n", t, seq_feature_names[f], imp_abs[t, f]))
}

rs <- rowSums(imp_abs)
cat(sprintf("\n=== importance by SEQUENCE POSITION | model: %s ===\n", basename(MODEL_PATH)))
print(round(rs, 6))
cat(sprintf("\nmax/min ratio = %.2f   (real model = 4.16)\n", max(rs)/min(rs)))
cat("Real month sitting at each position:", month_perm + 4, "\n")

write.csv(cbind(position = pos_names, as.data.frame(imp_abs)),
          "RiskCalendar_SHUFFLE_absLogOddsV2.csv", row.names = FALSE)

cat("\n--- magnitudes ---\n")
print(signif(rs, 4))
cat("sum(imp_abs) =", format(sum(imp_abs), scientific = TRUE, digits = 4), "\n")
cat("sd(base_p)   =", signif(sd(base_p), 4), "\n")

# ---------- Switch off the whole sequential branch in one go ----------
Xz <- X
for (t in 1:8) for (f in 1:9) Xz$seq_input[, t, f] <- mean_seq_vals[t, f]
pz <- predict_chunked(model, Xz)

auc0 <- as.numeric(auc(roc(y, base_p, direction = "<", quiet = TRUE)))
auc1 <- as.numeric(auc(roc(y, pz,     direction = "<", quiet = TRUE)))

cat("\n--- whole sequential branch off ---\n")
cat(sprintf("AUC before            %.5f\n", auc0))
cat(sprintf("AUC branch off        %.5f\n", auc1))
cat(sprintf("AUC lost              %.5f\n", auc0 - auc1))
cat(sprintf("mean |Delta logit|    %.6f\n", mean(abs(lg(base_p) - lg(pz)))))
cat(sprintf("Recall before         %.4f\n", mean(base_p[y==1] >= 0.5)))
cat(sprintf("Recall branch off     %.4f\n", mean(pz[y==1] >= 0.5)))
rm(Xz); gc()
