### =====================================================================
### Level diagnostics — the two questions that decide whether to keep investing effort
###   Part 1  ICC / design effect / ceiling of any area-level predictor
###   Part 2  distribution of the planting month MP  -> is Route C feasible?
### Total runtime about 15 minutes
### =====================================================================

DATA_FILE <- "data_hybrid2_prec_sai.txt"    # or data_hybrid2_prec_sai.txt works too
library(data.table); library(pROC)

dt <- fread(DATA_FILE, sep = "|", encoding = "UTF-8")
dt[, Y_num := as.numeric(as.character(Y))]
setnames(dt, old = grep("^ADM3$", names(dt), value = TRUE), new = "ADM3")
cat(sprintf("rows %s | cols %d\n", format(nrow(dt), big.mark = ","), ncol(dt)))

## =====================================================================
## Part 1.1 — cluster structure
## =====================================================================
cl <- dt[, .(n = .N, k = sum(Y_num), p = mean(Y_num)), by = .(ADM3, Year)]
setorder(cl, ADM3, Year)

N  <- nrow(dt); K <- nrow(cl)
mbar <- mean(cl$n)
m0   <- (N - sum(cl$n^2)/N) / (K - 1)      # mean cluster size adjusted for unequal clusters

cat("\n================ 1.1 cluster structure (ADM3, Year) ================\n")
cat(sprintf("Clusters (ADM3 x Year)          %s\n", format(K, big.mark = ",")))
cat(sprintf("Distinct ADM3                   %s\n", format(uniqueN(dt$ADM3), big.mark = ",")))
cat(sprintf("Cluster size  mean %.1f | median %.0f | min %d | max %s\n",
            mbar, median(cl$n), min(cl$n), format(max(cl$n), big.mark = ",")))
cat(sprintf("m0 (adjusted for unequal sizes)  %.2f\n", m0))
cat(sprintf("Clusters with < 10 borrowers    %d (%.1f%%)\n",
            sum(cl$n < 10), 100*mean(cl$n < 10)))

## =====================================================================
## Part 1.2 — ICC and design effect
## =====================================================================
grand <- mean(dt$Y_num)
MSB <- sum(cl$n * (cl$p - grand)^2) / (K - 1)
SSW <- sum(cl$n * cl$p * (1 - cl$p))          # for a 0/1 variable within clusters
MSW <- SSW / (N - K)
ICC <- (MSB - MSW) / (MSB + (m0 - 1) * MSW)
ICC <- max(ICC, 0)

DEFF  <- 1 + (m0 - 1) * ICC
n_eff <- N / DEFF

cat("\n================ 1.2 ICC and design effect ================\n")
cat(sprintf("Overall default rate           %.4f\n", grand))
cat(sprintf("ICC (ANOVA estimator)          %.5f\n", ICC))
cat(sprintf("Design effect  1+(m0-1)*ICC    %.2f\n", DEFF))
cat(sprintf("n_eff of the outcome           %s   (from %s)\n",
            format(round(n_eff), big.mark = ","), format(N, big.mark = ",")))
cat(sprintf("\n>>> Sample size for a 'cluster-level variable' (EO) = number of clusters = %s\n",
            format(K, big.mark = ",")))
cat(sprintf("    in the development set (years 1-2) = %s\n",
            format(nrow(cl[Year %in% c(1,2)]), big.mark = ",")))

## =====================================================================
## Part 1.3 — ceiling of any area-level predictor  <<< the most important number here
## =====================================================================
## What AUC would we get if the (ADM3, Year) cell default rate were known perfectly?
## This is the upper limit for any spatial predictor, a perfect EO model included.
dt <- merge(dt, cl[, .(ADM3, Year, cell_rate = p)], by = c("ADM3","Year"), all.x = TRUE)

te <- dt[Year == 3]
auc_oracle_same <- as.numeric(auc(roc(te$Y_num, te$cell_rate, direction = "<", quiet = TRUE)))

## --- Leave-one-out correction. This is the number the paper reports. ---------
## The rate above is computed from a cell that CONTAINS the borrower being
## scored, so a defaulter raises the rate of the very cell it is then ranked by.
## That is self-fulfilling and inflates the bound. Score each borrower against
## their own cell with themselves removed:
##
##     loo_rate(i) = (k_c - y_i) / (n_c - 1)
##
## Singleton cells have nothing left once the borrower is removed, so they get
## the overall default rate -- the best a lender could say about a borrower
## whose cell carries no other information.
##
## The gap between the two is the self-inclusion bias, and it is not small.
## Report the corrected figure; keep the naive one only to show the size of the
## correction.
te <- merge(te, cl[, .(ADM3, Year, cell_n = n, cell_k = k)],
            by = c("ADM3", "Year"), all.x = TRUE)
te[, loo_rate := fifelse(cell_n > 1L, (cell_k - Y_num) / (cell_n - 1L), grand)]
auc_oracle_loo <- as.numeric(auc(roc(te$Y_num, te$loo_rate, direction = "<", quiet = TRUE)))

## Attainable version: use the year 1-2 rates to rank year-3 borrowers
hist_rate <- dt[Year %in% c(1,2), .(hist = sum(Y_num)/.N), by = ADM3]
te2 <- merge(te[, .(ADM3, Y_num)], hist_rate, by = "ADM3", all.x = TRUE)
te2[is.na(hist), hist := grand]
auc_oracle_hist <- as.numeric(auc(roc(te2$Y_num, te2$hist, direction = "<", quiet = TRUE)))

cat("\n================ 1.3 ceiling of an area-level predictor ================\n")
cat(sprintf("Leave-one-out oracle on (ADM3, Year), 2022      %.5f   <- THE CEILING. this is the number the paper reports\n", auc_oracle_loo))
cat(sprintf("Naive oracle, borrower included in own cell     %.5f   <- inflated, do not report\n", auc_oracle_same))
cat(sprintf("Self-inclusion bias                             %.5f   <- the cost of getting this wrong\n", auc_oracle_same - auc_oracle_loo))
cat(sprintf("Singleton cells given the overall rate          %d\n", te[cell_n == 1L, .N]))
cat(sprintf("AUC from the year 1-2 rates (attainable)         %.5f   <- what TE_ADM3 actually does\n", auc_oracle_hist))
cat(sprintf("\nCf.:   EO-only as measured  Dev 0.643  Test 0.512\n"))
cat(  "       static-only 0.897 | ST-CRAAN 0.901 | XGBoost 0.909\n")

fwrite(cl, "cluster_summary_ADM3_Year.csv")

## =====================================================================
## Part 2 — distribution of the planting month MP
## =====================================================================
cat("\n\n================ 2. planting month (MP) ================\n")

if ("MP" %in% names(dt)) {
  dt[, MP_use := as.integer(MP)]
  cat("found the MP column directly\n")
} else if (all(c("MP_sin","MP_cos") %in% names(dt))) {
  cat("raw MP not found — recovering it from MP_sin / MP_cos\n")
  dt[, MP_use := {
    a <- atan2(MP_sin, MP_cos) * 12 / (2*pi)
    a <- round(a) %% 12
    fifelse(a == 0L, 12L, as.integer(a))
  }]
} else {
  stop("neither MP nor MP_sin/MP_cos found — use a file that carries this variable, e.g. full_database.txt")
}

tab <- dt[!is.na(MP_use), .(n = .N), by = MP_use][order(MP_use)]
tab[, share := 100*n/sum(n)]
cat("\n--- nationwide distribution of the planting month ---\n"); print(tab)

top <- tab[order(-n)][1, ]
cat(sprintf("\nmost common month: month %d  accounting for %.1f%%\n", top$MP_use, top$share))
cat(sprintf("months with a share >= 5%%      : %d\n", nrow(tab[share >= 5])))

## The "within-subdistrict" variety is what decides Route C
within <- dt[!is.na(MP_use), .(n_mp = uniqueN(MP_use), n = .N), by = .(ADM3, Year)]
cat("\n--- distinct planting months within each (ADM3, Year) ---\n")
print(within[, .(.N, share = 100*.N/nrow(within)), by = n_mp][order(n_mp)])
cat(sprintf("\nmean distinct planting months per cell %.2f | median %.0f\n",
            mean(within$n_mp), median(within$n_mp)))

K2 <- nrow(unique(dt[!is.na(MP_use), .(ADM3, Year, MP_use)]))
K2dev <- nrow(unique(dt[!is.na(MP_use) & Year %in% c(1,2), .(ADM3, Year, MP_use)]))

cat("\n================ implications for Route C ================\n")
cat(sprintf("Distinct sequences  now (ADM3, Year)          %s\n", format(K, big.mark = ",")))
cat(sprintf("Distinct sequences  if aligned on MP          %s   (x%.1f)\n",
            format(K2, big.mark = ","), K2/K))
cat(sprintf("   development set only                      %s\n", format(K2dev, big.mark = ",")))
cat(sprintf("Borrowers per sequence  now %.0f  ->  after alignment %.0f\n", N/K, N/K2))

cat("\n--- decision rule ---\n")
if (nrow(tab[share >= 5]) >= 3 && median(within$n_mp) >= 2) {
  cat("✅ MP is spread out and varies within subdistricts -> Route C is worth doing\n")
} else {
  cat("⚠️  MP is heavily concentrated, or barely varies within subdistricts -> Route C gains little\n")
}

## Harvest month and season length, in case the time window needs redefining
if ("MH" %in% names(dt) || all(c("MH_sin","MH_cos") %in% names(dt))) {
  if ("MH" %in% names(dt)) dt[, MH_use := as.integer(MH)] else
    dt[, MH_use := { a <- atan2(MH_sin, MH_cos)*12/(2*pi); a <- round(a) %% 12
                     fifelse(a == 0L, 12L, as.integer(a)) }]
  dt[, dur := (MH_use - MP_use) %% 12]
  cat("\n--- season length (MH - MP, months) ---\n")
  print(dt[!is.na(dur), .(n = .N), by = dur][order(dur)])
}

cat("\n🎉 done — wrote cluster_summary_ADM3_Year.csv\n")

## Ceiling on the development set — a sanity check, must be >= 0.643
dv <- dt[Year %in% c(1,2)]
cat(sprintf("Ceiling AUC on the development set  %.5f   (must be >= 0.643, otherwise there is a bug)\n",
            as.numeric(auc(roc(dv$Y_num, dv$cell_rate, direction = "<", quiet = TRUE)))))

## Decomposition: persistent vs year-specific
cat(sprintf("\nC  ceiling for 2022        %.5f\n", auc_oracle_loo))
cat(sprintf("H  from 2020-21 history    %.5f   <- this is all TE_ADM3 achieves\n", auc_oracle_hist))
cat(sprintf("E  EO-only                 %.5f\n", 0.51187))
cat(sprintf("\nPersistent part       H - 0.5      %.4f\n", auc_oracle_hist - 0.5))
cat(sprintf("Year-specific part    C - H        %.4f   <- this is what EO should capture\n",
            auc_oracle_loo - auc_oracle_hist))
cat(sprintf("EO actually captures  E - H        %+.4f\n", 0.51187 - auc_oracle_hist))
