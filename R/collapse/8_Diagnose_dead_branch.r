### =====================================================================
### Diagnosis: where the LSTM branch died — in the encoder itself, or at the fusion layer
### Run against both the 9-channel and the 11-channel model (switch MODEL_PATH / N_CH)
### =====================================================================
MODEL_PATH <- "HBDL2_Keras_11ch_Model"   # or "production_models/HBDL2_Keras_Final_Model"
N_CH       <- 11                          # 11 or 9, to match the model
DATA_FILE  <- "data_hybrid2_prec_sai.txt"

library(data.table); library(reticulate)
use_condaenv("tf-gpu", required = TRUE)
library(keras); py_require_legacy_keras(); library(tensorflow)
gpus <- tf$config$list_physical_devices("GPU")
if (length(gpus) > 0) tf$config$experimental$set_memory_growth(gpus[[1]], TRUE)

model <- load_model_tf(MODEL_PATH)

## ---- 1. Layer map ----------------------------------------------------
cat("\n===== layers =====\n")
for (i in seq_along(model$layers)) {
  l <- model$layers[[i]]
  cat(sprintf("%2d  %-22s %-28s out=%s\n", i, class(l)[1], l$name,
              paste(unlist(l$output_shape), collapse = "x")))
}

lstm_name <- NULL; fuse_name <- NULL
for (l in model$layers) {
  if (grepl("LSTM",   class(l)[1])) lstm_name <- l$name
  if (grepl("Concat", class(l)[1])) fuse_in   <- l$name
}
# the first dense layer after the concatenate, the one with 96-dim input = the fusion layer
for (l in model$layers) {
  if (grepl("Dense", class(l)[1])) {
    w <- l$get_weights()
    if (length(w) && nrow(w[[1]]) == 96) fuse_name <- l$name
  }
}
cat("\nlstm layer :", lstm_name, "\nfusion dense:", fuse_name, "\n")

## ---- 2. Test-data sample ---------------------------------------------
dt <- fread(DATA_FILE, sep = "|", encoding = "UTF-8")
dt[, ADM3_idx := as.integer(as.factor(ADM3))]
te <- dt[Year == 3]
set.seed(64); te <- te[sample(.N, min(50000L, .N))]

CH <- c("NDVI","NDWI","LST","Precipitation","SMAP","NTL","VHI","CRD","HSD","SAI_NDVI","SAI_NDWI")[1:N_CH]
PREFIX <- c(NDVI="norm_NDVI", NDWI="norm_NDWI", LST="norm_LST",
            Precipitation="norm_Precipitation", SMAP="norm_SMAP", NTL="norm_log_NTL",
            VHI="norm_VHI", CRD="norm_Rainfall_Deficit", HSD="norm_Heat_Stress_Days",
            SAI_NDVI="norm_SAI_NDVI", SAI_NDWI="norm_SAI_NDWI")
seq_cols <- unlist(lapply(CH, function(c) paste0(PREFIX[[c]], 5:12)), use.names = FALSE)
all_seq  <- unlist(lapply(names(PREFIX), function(c) paste0(PREFIX[[c]], 5:12)), use.names = FALSE)
drop_cols   <- c("Year","ID","Y","Y_num","ADM3","ADM3_idx")
static_cols <- setdiff(names(dt), c(drop_cols, all_seq))

col_map <- matrix(seq_along(seq_cols), nrow = 8, ncol = N_CH)
ord     <- as.vector(t(col_map))
X <- list(seq_input  = array_reshape(as.matrix(te[, ..seq_cols])[, ord], c(nrow(te), 8, N_CH)),
          stat_input = as.matrix(te[, ..static_cols]),
          cat_input  = te$ADM3_idx)
cat("static dim:", ncol(X$stat_input), " seq dim:", dim(X$seq_input)[2], "x", dim(X$seq_input)[3], "\n")

## ---- 3. Does lstm_out vary across borrowers? -------------------------
enc <- keras_model(inputs = model$inputs, outputs = model$get_layer(lstm_name)$output)
H   <- enc %>% predict(X, batch_size = 512, verbose = 0)
sds <- apply(H, 2, sd)

cat("\n===== A) the LSTM encoder =====\n")
cat(sprintf("hidden units            %d\n", ncol(H)))
cat(sprintf("SD across cases mean    %.6f\n", mean(sds)))
cat(sprintf("                max     %.6f\n", max(sds)))
cat(sprintf("units with SD < 1e-6    %d / %d\n", sum(sds < 1e-6), length(sds)))

## ---- 4. Which side does the fusion layer weight? ---------------------
W <- model$get_layer(fuse_name)$get_weights()[[1]]   # 96 x 32
cat("\n===== B) fusion layer (kernel", nrow(W), "x", ncol(W), ") =====\n")
cat(sprintf("mean |w| static (rows  1-32)      %.6f\n", mean(abs(W[1:32, ]))))
cat(sprintf("mean |w| LSTM   (rows 33-96)      %.6f\n", mean(abs(W[33:96, ]))))
cat(sprintf("LSTM/static ratio                 %.4f\n",
            mean(abs(W[33:96, ])) / mean(abs(W[1:32, ]))))

cat("\n===== how to read this =====\n")
cat("A near 0  -> the encoder collapsed on its own (needs pretraining / drop clipnorm / separate lr / longer training)\n")
cat("A normal but B near 0 -> fusion learned to ignore this branch (needs an auxiliary head / gradient blending)\n")


for (l in model$layers) if (grepl("LSTM", class(l)[1])) {
  w <- l$get_weights()
  cat(sprintf("%-12s |kernel| %.8f   |recurrent| %.6f   |bias| %.6f\n",
              l$name, mean(abs(w[[1]])), mean(abs(w[[2]])), mean(abs(w[[3]]))))
}
