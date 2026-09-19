# =============================================================================
#  XGB.r  --  compare two separately fitted models at MATCHED ALERT VOLUME
#  ---------------------------------------------------------------------------
#  Purpose   Settle whether ST-CRAAN's reported advantage over gradient boosting
#            survives a fair comparison. It does not. Comparing two separately
#            fitted models at a shared probability threshold of 0.5 confounds
#            calibration with discrimination: the model that happens to output
#            larger probabilities raises more alerts, and therefore catches more
#            defaulters, without ranking anyone better. Fix the alert volume
#            instead and the difference goes away.
#  Inputs    metric_compare/XGB_predict.txt        actual + predicted probability
#            STCRAAN/HB_DL2_Keras_predict.txt      actual + predicted probability
#  Outputs   console only
#  Section   Section 3.2; the self-correction in Section 1.4
#
#  Fifteen lines, and the reason a previously reported advantage of 13.23
#  percentage points is not in this paper.
# =============================================================================

library(data.table); library(pROC)
dx <- fread("metric_compare/XGB_predict.txt", sep = "|", encoding = "UTF-8")  # must contain actual + prob
df <- fread("STCRAAN/HB_DL2_Keras_predict.txt", sep = "|", encoding = "UTF-8")

yx <- as.integer(dx$Actual_Class == "Default"); px <- dx$Predicted_Prob
yf <- as.integer(df$Actual_Class == "Default"); pf <- df$Predicted_Prob

# The comparison is only meaningful if both files describe the same test rows.
# Nothing upstream guarantees that, so check it here rather than discover it in
# a reviewer's report. Matching row counts and positive counts is a weak check,
# but it catches the failures that actually happen: a stale prediction file, or
# one written from a different split.
stopifnot(length(px) == length(pf))
if (sum(yx == 1) != sum(yf == 1))
  stop(sprintf("positive counts differ: XGB %d, ST-CRAAN %d -- the two prediction files are not the same test set",
               sum(yx == 1), sum(yf == 1)))

rate <- mean(pf >= 0.5)                       # ST-CRAAN operating point
thr  <- quantile(px, 1 - rate)                # set XGBoost to raise the same number of alerts
Pf <- sum(yf == 1)                            # positives, ST-CRAAN file
Px <- sum(yx == 1)                            # positives, XGB file -- equal by the check above,
                                              # computed separately so the FN figures cannot
                                              # silently borrow the other model's denominator
rec_f    <- mean(pf[yf == 1] >= 0.5)
rec_x_50 <- mean(px[yx == 1] >= 0.5)
rec_x_mt <- mean(px[yx == 1] >= thr)

cat(sprintf("test rows              %d   positives %d\n", length(pf), Pf))
cat(sprintf("alert rate (ST-CRAAN @0.5)  %.4f   alerts %d\n", rate, round(rate * length(pf))))
cat(sprintf("XGB matched threshold       %.6f\n", thr))
cat(sprintf("\nRecall ST-CRAAN        %.4f   FN %d\n", rec_f,    round(Pf * (1 - rec_f))))
cat(sprintf("Recall XGB @0.5        %.4f   FN %d\n", rec_x_50, round(Px * (1 - rec_x_50))))
cat(sprintf("Recall XGB @matched    %.4f   FN %d\n", rec_x_mt, round(Px * (1 - rec_x_mt))))
cat(sprintf("\nDifference at a shared 0.5 threshold   %+.2f pp   <- confounded, do not report\n",
            100 * (rec_f - rec_x_50)))
cat(sprintf("Difference at matched alert volume     %+.2f pp   <- this is the comparable one\n",
            100 * (rec_f - rec_x_mt)))
cat(sprintf("\nAUC  ST-CRAAN %.5f | XGB %.5f\n",
            as.numeric(auc(roc(yf, pf, direction = "<", quiet = TRUE))),
            as.numeric(auc(roc(yx, px, direction = "<", quiet = TRUE)))))
