library(data.table)
dt <- fread("data_hybrid2_prec_sai.txt", sep = "|", encoding = "UTF-8")
dt[, Y_num := as.numeric(as.character(Y))]

for (ch in c("SAI_NDVI","SAI_NDWI")) {
  cols <- paste0("norm_", ch, 5:12)
  sm <- rowMeans(as.matrix(dt[, ..cols]), na.rm = TRUE)
  sx <- do.call(pmax, c(as.list(dt[, ..cols]), na.rm = TRUE))
  rm_ <- cor(sm, dt$Y_num, use = "complete.obs")
  rx_ <- cor(sx, dt$Y_num, use = "complete.obs")
  rmo <- sapply(cols, function(v) cor(dt[[v]], dt$Y_num, use = "complete.obs"))
  cat(sprintf("\n%s\n  Season_Mean r = %+.4f  %s\n  Season_Max  r = %+.4f  %s\n  Monthly max |r| = %.4f  (%d/8 columns pass)\n",
              ch, rm_, ifelse(abs(rm_)<0.01,"<- fails","passes"),
              rx_, ifelse(abs(rx_)<0.01,"<- fails","passes"),
              max(abs(rmo)), sum(abs(rmo) >= 0.01)))
}
