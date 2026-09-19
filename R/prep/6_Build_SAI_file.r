### =====================================================================
### Build the SAI model file : data_hybrid2_prec.txt  +  16 norm_SAI_* cols
### Normalisation follows apply_global_minmax() in Join_Normalize.r exactly
###   - global min/max per "channel" (all 8 months pooled), not per month
###   - estimated from Train (Year 1,2) only
###   - rounded to 4 decimals, as in the original pipeline
### =====================================================================
library(data.table)

MODEL_FILE <- "data_hybrid2_prec.txt"
GEO_FILE   <- "3_geo3y20_22.txt"
OUT_FILE   <- "data_hybrid2_prec_sai.txt"

dtm <- fread(MODEL_FILE, sep = "|", encoding = "UTF-8")
geo <- fread(GEO_FILE,   sep = "|", encoding = "UTF-8")

cat("model file :", nrow(dtm), "rows x", ncol(dtm), "cols\n")
cat("geo file   :", nrow(geo), "rows x", ncol(geo), "cols\n")

## ---- 0. Check the source columns -----------------------------------
sai_raw <- c(paste0("SAI_NDVI", 5:12), paste0("SAI_NDWI", 5:12))
miss <- setdiff(sai_raw, names(geo))
if (length(miss)) {
  cat("\n*** These columns were not found in", GEO_FILE, "***\n"); print(miss)
  cat("\nColumns with SAI-like names:\n"); print(grep("SAI", names(geo), value = TRUE, ignore.case = TRUE))
  stop("SAI columns missing")
}
if (!all(c("Year","ADM3") %in% names(geo))) stop("geo file must contain Year and ADM3")
if (!all(c("Year","ADM3") %in% names(dtm))) stop("model file must contain Year and ADM3")

## ---- 1. Make the key types match (as Join_Normalize.r does) --------
dtm[, `:=`(Year = as.character(Year), ADM3 = as.character(ADM3))]
geo[, `:=`(Year = as.character(Year), ADM3 = as.character(ADM3))]

## ---- 2. Keep key + SAI, drop duplicate (Year, ADM3) rows -----------
geo_s <- unique(geo[, c("Year","ADM3", sai_raw), with = FALSE], by = c("Year","ADM3"))
cat("distinct (Year, ADM3) in geo :", nrow(geo_s), "\n")

## ---- 3. Restrict to (Year, ADM3) pairs present in the model file ---
##  Important: min/max are order statistics, so they are unaffected by the
##  borrower count per sub-district - identical to the borrower-level table
keys  <- unique(dtm[, .(Year, ADM3)])
geo_s <- geo_s[keys, on = .(Year, ADM3), nomatch = 0L]
cat("matched (Year, ADM3)         :", nrow(geo_s), "of", nrow(keys), "\n")
if (nrow(geo_s) < nrow(keys))
  cat("⚠️  missing", nrow(keys) - nrow(geo_s), "pairs — those borrower rows will be NA\n")

## ---- 4. Global Min-Max per channel, from Train only ----------------
tr <- which(geo_s$Year %in% c("1","2"))
cat("train (Year 1,2) rows used for scaling :", length(tr), "\n\n")

apply_global_minmax <- function(D, cols, prefix = "norm_") {
  g_min <- min(as.matrix(D[tr, ..cols]), na.rm = TRUE)
  g_max <- max(as.matrix(D[tr, ..cols]), na.rm = TRUE)
  new   <- paste0(prefix, cols)
  D[, (new) := lapply(.SD, function(x) (x - g_min) / (g_max - g_min + 1e-8)), .SDcols = cols]
  cat(sprintf("  %-10s global min %.4f  max %.4f\n", sub("[0-9]+$","",cols[1]), g_min, g_max))
  invisible(NULL)
}
apply_global_minmax(geo_s, paste0("SAI_NDVI", 5:12))
apply_global_minmax(geo_s, paste0("SAI_NDWI", 5:12))

sai_norm <- paste0("norm_", sai_raw)
geo_s[, (sai_norm) := lapply(.SD, round, digits = 4), .SDcols = sai_norm]
geo_keep <- geo_s[, c("Year","ADM3", sai_norm), with = FALSE]

## ---- 5. Join back into the model file ------------------------------
setkey(geo_keep, Year, ADM3)
setkey(dtm,      Year, ADM3)
out <- geo_keep[dtm, on = .(Year, ADM3)]          # left join on the borrower side
setcolorder(out, names(dtm))                       # original columns first, SAI appended
setorder(out, Year, ID)

cat("\n---- post-join checks ----\n")
cat("rows in  :", nrow(dtm), " rows out :", nrow(out), "\n")
na_cnt <- colSums(is.na(out[, ..sai_norm]))
cat("NA in SAI columns :", sum(na_cnt), "values out of", nrow(out)*16, "\n")
if (sum(na_cnt) > 0) print(na_cnt[na_cnt > 0])

## ---- 6. Check the original 72 sequential columns and their order ---
CH9 <- c("norm_NDVI","norm_NDWI","norm_LST","norm_Precipitation",
         "norm_SMAP","norm_log_NTL","norm_VHI","norm_Rainfall_Deficit",
         "norm_Heat_Stress_Days")
expect72 <- unlist(lapply(CH9, function(p) paste0(p, 5:12)))
actual72 <- names(dtm)[42:113]
cat("\norder of the original 72 columns matches expectation :", identical(expect72, actual72), "\n")
if (!identical(expect72, actual72)) {
  cat("expected:\n"); print(head(expect72, 12))
  cat("actual:\n");   print(head(actual72, 12))
}

## ---- 7. r_pb for the 16 new columns --------------------------------
out[, Y_num := as.numeric(as.character(Y))]
rpb <- sapply(sai_norm, function(v) {
  x <- out[[v]]
  if (all(is.na(x)) || sd(x, na.rm = TRUE) == 0) return(NA_real_)
  cor(x, out$Y_num, use = "complete.obs")
})
cat("\n---- point-biserial r for SAI (against the 0.01 screening cut-off) ----\n")
print(round(rpb, 4))
cat("count with |r| < 0.01 :", sum(abs(rpb) < 0.01, na.rm = TRUE), "of 16\n")
out[, Y_num := NULL]

## ---- 8. Write the file ---------------------------------------------
fwrite(out, OUT_FILE, sep = "|")
cat("\n✅ wrote", OUT_FILE, ":", nrow(out), "rows x", ncol(out), "cols\n")
cat("   (was", ncol(dtm), "cols + 16)\n")
