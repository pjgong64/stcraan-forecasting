# Code audit

A line-by-line read of every script here, done before release. It is published
for the same reason the paper exists: a model that nobody checks reports whatever
it happens to report, and the only defence is to look. Twenty-eight findings
follow, with what was done about each.

Three of them were fixed because they could affect a reported number. One is
left in place deliberately. The rest are recorded so that a reader meets them
here rather than discovering them alone.

**Legend.** *Fixed* — corrected in this release. *Evidence* — left uncorrected
on purpose, because the file documents what the original model did. *Noted* —
real but not worth changing code that has already produced published results.

---

## A. Findings that touch a published number

### A1. The leave-one-out correction was not in the repository — Fixed and verified

`R/ceiling/11_Level_diagnostics.r`

The manuscript reports an areal bound of **0.66223** and describes it as a
leave-one-out oracle, with the naive self-inclusive calculation returning 0.677
and the difference — 0.015 of AUC — stated as the cost of getting it wrong.

The script as it stood computed only the naive version:

```r
cl <- dt[, .(n = .N, k = sum(Y_num), p = mean(Y_num)), by = .(ADM3, Year)]
auc_oracle_same <- auc(roc(te$Y_num, te$cell_rate, ...))   # cell_rate = p
```

`p` is the mean of a cell that contains the borrower being scored, so a
defaulter raises the rate of the very cell it is then ranked by. No
leave-one-out arithmetic appeared anywhere in the tree — a search for
`(k - y)`, `n - 1` and similar returned nothing.

The correction is now computed explicitly:

```r
te[, loo_rate := fifelse(cell_n > 1L, (cell_k - Y_num) / (cell_n - 1L), grand)]
```

Singleton cells keep nothing once the borrower is removed, so they take the
overall default rate. The script now prints the corrected bound, the naive one
and the difference between them, and the downstream decomposition uses the
corrected figure.

Run on the real panel, it reproduces every published figure:

```
Leave-one-out oracle on (ADM3, Year), 2022      0.66223
Naive oracle, borrower included in own cell     0.67721
Self-inclusion bias                             0.01499
Singleton cells given the overall rate          153
```

The cluster diagnostics above it match as well: ICC 0.05174, design effect
13.41, effective sample 334,910 from 4,490,163. The manuscript's figures were
right; only the code that produced them was missing, and it is now here.

### A2. False-negative counts used the wrong denominator — Fixed

`R/evaluation/XGB.r`

`P <- sum(yf == 1)` counted positives in the ST-CRAAN prediction file, and the
same `P` was then used for the XGBoost false-negative figure. `sum(yx == 1)` was
never computed. If the two files cover the same test rows the counts coincide
and nothing was wrong, but nothing checked that they do.

The script now computes both counts, uses each model's own denominator, and
stops with a clear message if the two files disagree on row count or positive
count. It also prints the matched threshold, the alert count, both AUCs, and the
difference at a shared 0.5 threshold beside the difference at matched volume —
so the confounded comparison and the fair one appear side by side.

This file is what overturned a previously reported advantage of 13.23 percentage
points. Its arithmetic should be visible rather than inferred.

### A3. The month-permutation control loaded an unlabelled model — Fixed and resolved

`R/collapse/sequence.r`

The script printed results under `=== SHUFFLED MODEL ===` while loading
`STCRAAN/HBDL2_Keras_Final_Model`, the production network.
`R/collapse/STCRAAN_shuffle_month.r` saves its shuffle-trained network as
`HBDL2_Keras_Shuffle_Model`. Read literally, the script fed month-permuted
inputs to a model trained on real month order — permutation importance, which is
a reasonable experiment, but not the one the banner claimed.

The path is now a named constant at the top of the file, with both candidates
and what each one asks written out above it; the loaded path is printed at load
time and echoed in the results banner, so the console record cannot disagree
with the file it read. The default is unchanged, so behaviour is identical until
someone deliberately changes it.

**Resolved.** `HBDL2_Keras_Shuffle_Model` exists on disk but is dated *after* the
published CSV was written, so that file cannot have come from it. The production
network is what produced it, and `MODEL_PATH` is left pointing there.

So the published file is a **scoring-time permutation control**, not a control
trained on scrambled months: the production model's own months were permuted at
inference and its per-position attribution was recomputed. That is the stronger
reading for this paper's purpose. A network genuinely reading a time series
should respond when its months are reordered; this one did not, because the
branch feeding it was inert. The files are named and described accordingly.

### A4. The original model's tensor reshape has no column permutation — Evidence

`R/model/5_HB_DLprec.r:72`

```r
x_train_seq_3d <- array_reshape(x_train_seq, c(nrow(x_train_seq), 8, 9))
```

`reticulate::array_reshape` is C-order while the sequence columns are laid out
channel-major (`norm_NDVI5 … norm_NDVI12`, then `norm_NDWI5 …`). Element
`[i, t, f]` is therefore read from flat column `(t-1)*9 + f`, whereas month *t*
of channel *f* actually sits at column `(f-1)*8 + t`. In the original network the
LSTM's time axis was an interleaving of month and channel rather than time.

Every later script fixes this. `R/model/7_ExpA_SAI_11ch.r:91` builds an explicit
`col_map`, permutes, and asserts the round trip, calling it "the correct
reshape". `R/factorial/12_Factorial7_run.R:792` does the same with a
`stopifnot`, and names the trap in its header:

> reticulate::array_reshape is C-order; R's dim<- is Fortran-order. Getting this
> wrong scrambles month against channel silently.

**No published number is affected.** Everything the manuscript reports comes
from the factorial, which permutes correctly and asserts it.

Left uncorrected on purpose. `5_HB_DLprec.r` is published as a record of what
the original network did — it is the file a reader opens to check the paper's
central claim about the regulariser — and silently repairing a second defect in
it would misrepresent that record. It means the original model was broken in two
independent ways while still reporting strong aggregate performance, which is
the paper's argument rather than a complication of it.

---

## B. Correctness traps that no published number depends on

| # | Where | Finding |
|---|---|---|
| B1 | eleven scripts | `use_condaenv("tf-gpu", required = TRUE)` fails wherever conda is not on `PATH`. Replace with `source("R/00_python_env.R"); bind_python("tf-gpu")`, which resolves the environment on disk. `R/factorial/` already does. |
| B2 | `5_HB_DLprec.r:57`, `MoAblation_StaticOnlyV2.r:47`, `STCRAAN_shuffle_month.r:25`, `sequence.r:15` | Sequence columns selected positionally as `all_cols[42:113]`. Correct for one file and silently wrong for any other — it does not error, it returns a plausible number. `R/00_paths.R` provides `seq_columns()` for name-based selection. |
| B3 | `R/prep/datamani.r:16-17` | The line building `sum_dt` is commented out; the `fwrite(sum_dt, …)` below it is not. A straight run stops with `object 'sum_dt' not found`. |
| B4 | `8_Diagnose_dead_branch.r:34,74-79` | The fusion layer is located by matching a Dense layer with exactly 96 input rows, and the static/LSTM split is hard-coded as rows `1:32` / `33:96`. Works for both the 9- and 11-channel models only because 96 = 32 + 64 in both. Any other width leaves `fuse_name` as `NULL` and line 74 errors. |
| B5 | `9_ExpC_revive_branch.r:191-196` | `ns <- max(16, 64/2)` hard-codes `stat_hd = 64` instead of reading it from the model, and the `%d/64` message hard-codes `lstm_hd`. Different widths would take the kernel split at the wrong row and report a meaningless ratio without erroring. |
| B6 | `6_Build_SAI_file.r:52` | `apply_global_minmax()` reads `tr` from the enclosing global scope rather than taking it as an argument. Correct for both current calls; silently wrong scaling if ever called with another table. |
| B7 | `6_Build_SAI_file.r:46` | Unmatched `(Year, ADM3)` pairs emit a `cat` warning and the resulting NAs are written to the output file regardless. Those NAs reach the Keras input tensors and produce a NaN loss with no further guard. |
| B8 | `11_Level_diagnostics.r:13` | `setnames(dt, old = grep("^ADM3$", …), new = "ADM3")` is a no-op when `ADM3` exists and errors when it does not — `old` is `character(0)` against a length-1 `new`. It gives no protection against the case it appears to guard. |
| B9 | `MoAblation_StaticOnlyV2.r:128-134` | `rate` comes from the ST-CRAAN prediction file while `p_static` comes from this script's own `Year == 3` split, with no check that they cover the same rows. The same class of problem as A2, in a script that was not rewritten. |
| B10 | `7_ExpA_SAI_11ch.r:185` | `stopifnot(nrow(ds) == length(p11))` checks length, not row alignment, and the comparison then mixes `ds$Actual` with `y_test_raw`. |

---

## C. Labelling, dead code and inconsistencies

| # | Where | Finding |
|---|---|---|
| C1 | `5_HB_DLprec.r:269-273` | The section heading and its `cat` both say "5-Fold"; the code is `createFolds(..., k = 10)`. Ten folds run. |
| C2 | `5_HB_DLprec.r:225` | The comment above `reduce_lr` says the learning rate halves after five stalled epochs; the argument is `patience = 2L`. |
| C3 | `5_HB_DLprec.r` | Tuning passes `list(early_stop, reduce_lr)`, cross-validation passes `early_stop` alone and runs `epochs + 5`, and the final fit passes no callbacks and no validation data. The tuned epoch count was chosen under a schedule the final model never sees. |
| C4 | `5_HB_DLprec.r:371-373` | `print("\n====…")` where `cat` was intended — emits a quoted string with a literal `\n`. |
| C5 | `5_HB_DLprec.r` | `build_hybrid_model()` reads `embed_dim`, `num_adm3_classes` and `static_dimension` from the global environment instead of taking them as arguments. |
| C6 | `11_Level_diagnostics.r:8` | The trailing comment offers `data_hybrid2_prec_sai.txt` as an alternative to itself. It was presumably meant to name `data_hybrid2_prec.txt`. |
| C7 | `11_Level_diagnostics.r:139` | `dur := (MH_use - MP_use) %% 12` makes a twelve-month season indistinguishable from a zero-month one. |
| C8 | `11_Level_diagnostics.r:121-124` | `K`, `K2` and `K2dev` are printed in one aligned column but `K2dev` is on a different base (development years only). |
| C9 | `10_Factorial_EO.r:18` | `RUN_NOSPATIAL` reads as "run the no-spatial variant"; setting it `TRUE` *adds* the two spatial arms. |
| C10 | `10_Factorial_EO.r:77` | `sprintf("Rec@%.0f%%", a*100)` rounds the 0.2535 alert rate to `"Rec@25%"`, and line 205 depends on that rounded name. Two rates rounding to the same integer would overwrite a column rather than error. |
| C11 | `10_Factorial_EO.r:60,118,136` | `FIN_NS` is assigned and never read; `sub` is reused as a global across the LR and RF blocks. |
| C12 | `9_ExpC_revive_branch.r:185,191` | The message calls the measured tensor `lstm_out`; `enc` is built on `seq_lstm_2`, before the dropout that produces `lstm_out`. They coincide at inference, so the conclusion holds and the label does not. |
| C13 | `9_ExpC_revive_branch.r:255-259` | Two diagnostic lines sit after the completion message and reprint a figure already shown. |
| C14 | `RiskCalendar.r:78,105` | The two sections use opposite sign conventions — `base_l - lg(p)` against `lg(p) - base_l`. Line 94 flags it deliberately, but `RiskCalendar_signed.csv` and `ChannelResponse_quantile.csv` carry opposite sign meanings and neither file records that. |
| C15 | `RiskCalendar.r:43` | The perturbation baseline is the mean of a 200k stratified subsample rather than of the full test set. |
| C16 | `MoAblation_StaticOnlyV2.r:69` vs `STCRAAN_shuffle_month.r:56` | `wd_rate` defaults to `1e-4` in one model builder and `0.001` in the other. Both are called with an explicit value, so results are unaffected. |
| C17 | `7_ExpA_SAI_11ch.r:175-176,200` | Comparison baselines are hard-coded literals (`0.90057`, `0.63710`, `704`) rather than read from the 9-channel run's outputs. |
| C18 | `7_ExpA_SAI_11ch.r:211-214` | The same `auc(roc(...))` is recomputed three times inside one `sprintf`. |
| C19 | `10_Factorial_EO.r` | Class weighting is expressed four different ways across families (`scale_pos_weight`, `weights`, `case.weights`, `class_weight`). The intent is consistent, but `scale_pos_weight` also shifts XGBoost's base score, so the raw probabilities are not on a common scale. The fixed-alert-rate metric is immune to this, which is the point — but the `pred_*.txt` outputs should not be pooled or thresholded at a shared absolute cutoff. |
| C20 | `8_Diagnose_dead_branch.r:28` | `fuse_in <- l$name` is assigned and never read. |

---

## What this list is not

It is not a defect count for the findings. Every number in the manuscript comes
from `R/factorial/`, `R/ceiling/` and `R/evaluation/`, and A1 to A3 are the only
entries that reach any of them — two now fixed in code, one a labelling change
with unchanged behaviour. A4 concerns a superseded network that the paper
describes as broken.

It is a record that the code was read. The manuscript argues that a fused model
reporting a gain nobody has tested is not evidence of anything. The same applies
to the code that produced it.
