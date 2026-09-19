### =====================================================================
### Factorial experiment — "does alternative data help?" kept separate from "which architecture is best?"
###
###   4 model families  x  {without EO, with EO}  x  {with spatial identity, without}
###
### Scored by recall at a fixed "alert rate", a measure that does not depend on calibration
### and therefore compares fairly across model families
### =====================================================================

DATA_FILE   <- "dataset_for_modeling.txt"
W1          <- 100/6.575        # 15.209 default-class weight, the same for every model
ALERT_RATES <- c(0.10, 0.20, 0.2535, 0.30)   # alert rates used for the comparison

RUN_LR   <- TRUE
RUN_RF   <- TRUE
RUN_XGB  <- TRUE
RUN_MLP  <- TRUE
RUN_NOSPATIAL <- TRUE            # second block: vary the spatial identity features as well

RF_SUBSAMPLE <- 800000L          # RF is very slow on 3M rows; set NA to use all of them
LR_SUBSAMPLE <- NA_integer_

library(data.table); library(pROC)

## ---------------------------------------------------------------------
## 1. Data and feature-block definitions
## ---------------------------------------------------------------------
dt <- fread(DATA_FILE, sep = "|", encoding = "UTF-8")
dt[, Y_num := as.numeric(as.character(factor(Y, levels = c(0,1), labels = c(0,1))))]
nm <- names(dt)

# 12 seasonal summaries derived from satellite data = the EO block
EO_COLS <- grep("_Season_(Mean|Max|Sum)$", nm, value = TRUE)

# spatial / administrative identity (target-encoded)
SPATIAL_COLS <- grep("^TE_", nm, value = TRUE)

ID_COLS <- intersect(c("Year","ID","Y","Y_num","ADM3"), nm)
ALL_FEAT <- setdiff(nm, ID_COLS)
FIN_COLS <- setdiff(ALL_FEAT, c(EO_COLS, SPATIAL_COLS))

cat("\n================ Feature blocks ================\n")
cat("All features          :", length(ALL_FEAT), "\n")
cat("Financial / other     :", length(FIN_COLS), "\n")
cat("EO (seasonal agg)     :", length(EO_COLS), "\n"); print(EO_COLS)
cat("Spatial identity      :", length(SPATIAL_COLS), "\n"); print(SPATIAL_COLS)
if (length(EO_COLS) == 0) stop("no EO columns found — check the pattern _Season_Mean/_Season_Max")

tr_idx <- which(dt$Year %in% c(1,2)); te_idx <- which(dt$Year == 3)
y_tr <- dt$Y_num[tr_idx]; y_te <- dt$Y_num[te_idx]
P <- sum(y_te == 1)
cat(sprintf("\ntrain %d | test %d | defaults in test %d (%.2f%%)\n",
            length(tr_idx), length(te_idx), P, 100*P/length(te_idx)))

ARMS <- list(
  `F`         = FIN_COLS,
  `F+EO`      = c(FIN_COLS, EO_COLS)
)
if (RUN_NOSPATIAL) {
  FIN_NS <- setdiff(FIN_COLS, SPATIAL_COLS)   # FIN_COLS already excludes TE_, so the two are identical
  ARMS[["F+SP"]]    <- c(FIN_COLS, SPATIAL_COLS)
  ARMS[["F+SP+EO"]] <- c(FIN_COLS, SPATIAL_COLS, EO_COLS)
}
# Note: F and F+EO = no spatial identity | F+SP and F+SP+EO = with it
cat("\nExperimental arms:\n"); for (a in names(ARMS)) cat(sprintf("  %-10s %d features\n", a, length(ARMS[[a]])))

## ---------------------------------------------------------------------
## 2. Evaluation helper — recall at a fixed alert rate
## ---------------------------------------------------------------------
evaluate <- function(model, arm, p) {
  r <- roc(y_te, p, direction = "<", quiet = TRUE)
  out <- data.table(model = model, arm = arm, n_feat = length(ARMS[[arm]]),
                    AUC = as.numeric(auc(r)),
                    KS  = max(r$sensitivities + r$specificities - 1))
  for (a in ALERT_RATES) {
    thr <- quantile(p, 1 - a)
    out[[sprintf("Rec@%.0f%%", a*100)]] <- mean(p[y_te == 1] >= thr)
  }
  out
}

RES <- list()
record <- function(model, arm, p) {
  e <- evaluate(model, arm, p)
  RES[[paste(model, arm)]] <<- e
  print(e)
  fwrite(data.table(Actual = y_te, Prob = p),
         sprintf("pred_%s_%s.txt", model, gsub("[+]", "", arm)), sep = "|")
  invisible(NULL)
}

## ---------------------------------------------------------------------
## 3. XGBoost
## ---------------------------------------------------------------------
if (RUN_XGB) {
  library(xgboost)
  # 🔴 substitute the previously tuned values if available — these are sensible defaults
  XGB_P <- list(objective = "binary:logistic", eval_metric = "auc",
                eta = 0.05, max_depth = 6, subsample = 0.8,
                colsample_bytree = 0.8, min_child_weight = 5,
                scale_pos_weight = W1, nthread = parallel::detectCores())
  XGB_NROUND <- 400
  for (arm in names(ARMS)) {
    cat(sprintf("\n---- XGB | %s ----\n", arm))
    cols <- ARMS[[arm]]
    dtrain <- xgb.DMatrix(as.matrix(dt[tr_idx, ..cols]), label = y_tr)
    bst <- xgb.train(XGB_P, dtrain, nrounds = XGB_NROUND, verbose = 0)
    p <- predict(bst, as.matrix(dt[te_idx, ..cols]))
    record("XGB", arm, p); rm(dtrain, bst); gc()
  }
}

## ---------------------------------------------------------------------
## 4. Logistic Regression (elastic net)
## ---------------------------------------------------------------------
if (RUN_LR) {
  library(glmnet)
  sub <- if (is.na(LR_SUBSAMPLE)) tr_idx else { set.seed(64); sample(tr_idx, LR_SUBSAMPLE) }
  for (arm in names(ARMS)) {
    cat(sprintf("\n---- LR | %s ----\n", arm))
    cols <- ARMS[[arm]]
    X <- as.matrix(dt[sub, ..cols]); yy <- dt$Y_num[sub]
    w <- ifelse(yy == 1, W1, 1)
    fit <- glmnet(X, yy, family = "binomial", alpha = 0.5,
                  lambda = 1e-4, standardize = FALSE, weights = w)
    p <- as.numeric(predict(fit, as.matrix(dt[te_idx, ..cols]), type = "response"))
    record("LR", arm, p); rm(X, fit); gc()
  }
}

## ---------------------------------------------------------------------
## 5. Random Forest
## ---------------------------------------------------------------------
if (RUN_RF) {
  library(ranger)
  sub <- if (is.na(RF_SUBSAMPLE)) tr_idx else { set.seed(64); sample(tr_idx, RF_SUBSAMPLE) }
  cat(sprintf("\n[RF trained on a sample of %d rows]\n", length(sub)))
  for (arm in names(ARMS)) {
    cat(sprintf("\n---- RF | %s ----\n", arm))
    cols <- ARMS[[arm]]
    d <- dt[sub, c(cols, "Y_num"), with = FALSE]
    d[, Y_num := factor(Y_num, levels = c(0,1))]
    rf <- ranger(dependent.variable.name = "Y_num", data = d, probability = TRUE,
                 num.trees = 300, min.node.size = 50, num.threads = parallel::detectCores(),
                 case.weights = ifelse(d$Y_num == "1", W1, 1), verbose = FALSE)
    p <- predict(rf, dt[te_idx, ..cols], num.threads = parallel::detectCores())$predictions[, "1"]
    record("RF", arm, p); rm(d, rf); gc()
  }
}

## ---------------------------------------------------------------------
## 6. MLP  (same structure as the static branch of ST-CRAAN)
## ---------------------------------------------------------------------
if (RUN_MLP) {
  library(reticulate); use_condaenv("tf-gpu", required = TRUE)
  library(keras); py_require_legacy_keras(); library(tensorflow)
  py_gc <- import("gc")
  g <- tf$config$list_physical_devices("GPU")
  if (length(g) > 0) tf$config$experimental$set_memory_growth(g[[1]], TRUE)

  for (arm in names(ARMS)) {
    cat(sprintf("\n---- MLP | %s ----\n", arm))
    cols <- ARMS[[arm]]
    k_clear_session(); py_gc$collect(); tf$random$set_seed(64L)
    inp <- layer_input(shape = c(length(cols)))
    out <- inp %>%
      layer_dense(units = 64, kernel_initializer = initializer_lecun_uniform(),
                  kernel_regularizer = regularizer_l2(1e-4)) %>%
      layer_batch_normalization(momentum = 0.9, epsilon = 1e-5) %>%
      layer_activation("relu") %>% layer_dropout(0.2) %>%
      layer_dense(units = 32, kernel_initializer = initializer_lecun_uniform(),
                  kernel_regularizer = regularizer_l2(1e-4)) %>%
      layer_batch_normalization(momentum = 0.9, epsilon = 1e-5) %>%
      layer_activation("relu") %>% layer_dropout(0.2) %>%
      layer_dense(units = 1, activation = "sigmoid")
    m <- keras_model(inp, out)
    m %>% compile(optimizer = optimizer_adam(learning_rate = 1e-3, epsilon = 1e-8),
                  loss = "binary_crossentropy",
                  metrics = list(tf$keras$metrics$AUC(name = "auc")))
    m %>% fit(x = as.matrix(dt[tr_idx, ..cols]), y = y_tr, epochs = 20, batch_size = 2048,
              class_weight = list("0" = 1, "1" = W1), verbose = 1)
    p <- m %>% predict(as.matrix(dt[te_idx, ..cols]), batch_size = 512) %>% as.numeric()
    record("MLP", arm, p); rm(m); gc()
  }
}

## ---------------------------------------------------------------------
## 7. Summary table + effect of EO within each family
## ---------------------------------------------------------------------
R <- rbindlist(RES)
setorder(R, model, arm)
cat("\n\n================ Combined results table ================\n")
print(R)
fwrite(R, "Factorial_EO_results.csv")

cat("\n================ Effect of adding EO (within the same family) ================\n")
mk <- function(base, plus, label) {
  d <- merge(R[arm == base], R[arm == plus], by = "model", suffixes = c("_no","_eo"))
  if (!nrow(d)) return(invisible(NULL))
  cat(sprintf("\n--- %s ---\n", label))
  cat(sprintf("%-6s %10s %10s %8s | %11s %11s %8s %10s\n",
              "model","AUC_noEO","AUC_EO","dAUC","Rec@25_no","Rec@25_EO","d pp","d cases"))
  for (i in seq_len(nrow(d))) {
    a0 <- d$AUC_no[i]; a1 <- d$AUC_eo[i]
    r0 <- d$`Rec@25%_no`[i]; r1 <- d$`Rec@25%_eo`[i]
    cat(sprintf("%-6s %10.5f %10.5f %+8.5f | %11.4f %11.4f %+8.2f %+10d\n",
                d$model[i], a0, a1, a1-a0, r0, r1, (r1-r0)*100, round(P*(r1-r0))))
  }
}
mk("F", "F+EO", "without spatial identity")
if (RUN_NOSPATIAL) mk("F+SP", "F+SP+EO", "with spatial identity")

cat("\n🎉 done — saved to Factorial_EO_results.csv and pred_*.txt\n")
