# Silent modality collapse and the measurement of fusion gains

Analysis code for a nationwide out-of-time test of Earth observation for
agricultural default forecasting, on a panel of 1,496,721 Thai rice-cultivating
borrowers and 4,490,163 borrower-years across 6,236 sub-districts and three
crop seasons.

> **Paper.** Jungsatidkul, P.; Innate, S. *Silent Modality Collapse and the
> Measurement of Fusion Gains: A Nationwide Out-of-Time Test of Earth
> Observation for Agricultural Default Forecasting.* Manuscript under revision
> (round 1) at *Forecasting*, 2026.

## What is here

The borrower records are restricted and are not in this repository. Everything
else is: the code, the published result files, the schema, and a generator that
builds a synthetic panel with the same structure so the pipeline runs end to end
without them.

```
R/            analysis code, by stage            see R/README.md
R/revision/   analyses added for the reviewers   see R/revision/README.md
python/       post-processing of saved scores    see R/revision/README.md
gee/          Earth Engine extraction            see gee/README.md
data/         schema and synthetic generator     see data/README.md
output/       published results and diagnostics  see output/README.md
bat/          Windows launchers
```

`output/EXCLUDED.md` lists what was deliberately withheld, and why. It is worth
reading before concluding that something is missing by accident.

## Revision round 1 (v1.1.0)

The reviewers asked for uncertainty intervals, a second year boundary, a
borrower-grouped validation split, out-of-fold target encodings, an ablation of
the branch revival, a test of the diagnostics on a known signal, and an exact
derivation of the areal bound. Every one of those analyses is in this release:

| Request | Script | Result file | Paper |
|---|---|---|---|
| Exact areal bound (ties counted ½) | `python/revision/r1_areal_ceiling.py`, `R/ceiling/11_Level_diagnostics.r` | `output/revision/r1_areal_ceiling.csv` | §4.10, Note S1 |
| Sub-district-clustered bootstrap | `python/revision/r3_cluster_bootstrap.py` | `output/revision/boot_refit1_*.csv` | §4.14 |
| Refits under further seeds | `R/factorial/12_Factorial7_run.R seed=<n>` | `output/revision/r5_*.csv` | §4.14 |
| Intervals that pool seeds and bootstrap | `python/revision/r4_seed_pooled_ci.py` | `output/revision/seedci_*.csv`, `table9.csv` | Table 9 |
| Recall at 10% and 30% alert volume | `R/factorial/12_Factorial7_run.R` | `output/revision/r2_recall_alert_volumes_published.csv` | Table S5 |
| Rolling origin, fit 2020 → score 2021 | `R/revision/12_Factorial7_run_rolling.R` | `output/revision/rolling_2020_to_2021_results.csv` | §4.15, Table 10 |
| Borrower-grouped split, out-of-fold encodings | `R/revision/12_Factorial7_run_grouped.R` | `output/revision/grouped_val_oof_results.csv` | §4.16, Table S6 |
| Ablation of the revival; diagnostics on a planted signal | `R/revision/13_R1_ablation_sim.R` | `output/revision/r1_ablation_sim.csv` | §4.6.1–4.6.2, Tables S7–S8 |
| Branch health of the factorial's ST-CRAAN | `R/revision/12_Factorial7_run_diag.R` | `output/revision/configB_diag.csv` | Table S9 |

None of them uses the 2022 season to fit, tune or select anything. Two results
changed what the paper says, and `CHANGELOG.md` states both: the bound is 0.67721,
not the leave-one-out 0.66223; and the collapse is gradient starvation, which
weight decay completes rather than causes.

## Quick start

```bash
git clone https://github.com/pjgong64/stcraan-forecasting && cd stcraan-forecasting

cd data/synthetic && Rscript make_synthetic.R && cd ../..   # ~1 min
SYNTH=1 Rscript R/ceiling/11_Level_diagnostics.r            # cluster structure
SYNTH=1 Rscript R/factorial/12_Factorial7_run.R LR          # one family
Rscript R/factorial/12_Factorial7_report.R                  # read the table
```

The synthetic panel reproduces the cluster structure of the real one but not the
joint dependence among covariates, so the AUC values it produces are not the
paper's. `data/README.md` says exactly what transfers and what does not.

## Traceability

Every number in the manuscript comes from a file here.

| Claim | Value | Produced by | Published in |
|---|---|---|---|
| Neutralising the environmental tensor in the fitted model (Configuration A, inherited) | ΔAUC = 0.00000 | `R/collapse/8_Diagnose_dead_branch.r` | — |
| Recurrent input kernel against unregularised matrices | ≈ 7×10⁻⁸ of initialisation | `R/collapse/8_Diagnose_dead_branch.r` | `note` column of `factorial7_results.csv` |
| Per-channel attribution of the collapsed model | AUC drop ~1e-7 | `R/collapse/RiskCalendar.r` | `output/diagnostics/risk_calendar_collapsed/` |
| Month-permutation control | same order as the unpermuted attribution | `R/collapse/sequence.r` | same directory |
| Branch revival | — | `R/collapse/9_ExpC_revive_branch.r` | — |
| Neutralisation against refitting disagree in sign | +0.80 pp vs −0.50 pp recall | `R/collapse/MoAblation_StaticOnlyV2.r` | — |
| Intracluster correlation of default | 0.0517 | `R/ceiling/11_Level_diagnostics.r` | `output/results/cluster_structure_summary.csv` |
| Design effect, effective sample size | 13.41, 334,910 | same | same |
| Exact areal bound on (ADM3, Year), ties counted ½ | 0.67721 | same; `python/revision/r1_areal_ceiling.py` | `output/revision/r1_areal_ceiling.csv` |
| Leave-one-out statistic (reported in v1.0.0; understates the bound) | 0.66223 | same | same |
| Best cell in the factorial | XGB, F+SP, 0.90730 | `R/factorial/12_Factorial7_run.R` | `output/results/factorial7_results.csv` |
| EO added to financial and spatial covariates, one fit | loses AUC in 4 of 5 families | same | same |
| Same contrast over refits | negative in every fit of LR, RF, XGBoost; MLP +0.0026 (SD 0.0059), ST-CRAAN −0.0017 (SD 0.0042) over six fits | `R/factorial/12_Factorial7_run.R seed=`, `python/revision/r4_seed_pooled_ci.py` | `output/revision/table9.csv` |
| Paired standard error of an AUC difference, sub-district bootstrap | 0.0001–0.0004 | `python/revision/r3_cluster_bootstrap.py` | `output/revision/boot_refit1_contrasts.csv` |
| Rolling origin 2020 → 2021: EO-only AUC | 0.520–0.541 | `R/revision/12_Factorial7_run_rolling.R` | `output/revision/rolling_2020_to_2021_results.csv` |
| Grouped split + out-of-fold encodings: development AUC of SPA, LR | 0.691 → 0.671 | `R/revision/12_Factorial7_run_grouped.R` | `output/revision/grouped_val_oof_results.csv` |
| Removing the input-kernel penalty alone | 62 of 64 units still constant | `R/revision/13_R1_ablation_sim.R` | `output/revision/r1_ablation_sim.csv` |
| Planted signal, β = 1.5: neutralisation ΔAUC, revived vs inherited | +0.0100 vs +0.0047 | same | same |
| Factorial ST-CRAAN branch in use, neutralisation ΔAUC | +0.00003, −0.00032, −0.00175 | `R/revision/12_Factorial7_run_diag.R` | `output/revision/configB_diag.csv` |
| EO added to areal spatial history alone (SPA → EO+SPA) | negative in all 5, −0.00082 to −0.00318 | same | same |
| Two sub-cell columns added (SPA → SP) | positive in all 5, +0.00705 to +0.00927 | same | same |
| Falsification test: every EO+SPA cell below the bound | 0.64591–0.64868, spread 0.00277 | same | same |
| SPA agreement across function classes | spread 0.00043, mean 0.64941 | same | same |
| EO alone, development against withheld season | 0.709 → 0.490 | same | same |
| Block membership of each target encoding | measured, not assumed | `R/factorial/12_Factorial7_partition.R` | `data/schema/financial_columns.csv` |
| L2 on the recurrent input kernel, none on the recurrent matrix | `5_HB_DLprec.r` lines 95, 100, 150 | `R/model/5_HB_DLprec.r` | — |
| Every transform parameter estimated on years 1–2 only | `which(dt$Year %in% c(1, 2))` | `R/prep/Join_Normalize.r` | — |
| Matched alert volume against fixed threshold | — | `R/evaluation/XGB.r` | `recall_a*` / `fn_a*` columns |
| Seasonal aggregation hides the anomaly channels | 0.002–0.008 aggregated, 0.080 monthly | `R/prep/SAI_NDVI_NDWI.r` | `output/diagnostics/rpb_sequential.csv` |

## Requirements

R 4.6, and a Python environment with TensorFlow for the two Keras families.
`R/00_python_env.R` locates that environment on disk, so conda does not need to
be on `PATH`. `bat/check.bat` prints what a Windows machine actually has.

Package versions are pinned in `renv.lock` and `environment.yml`; `ENVIRONMENT.md`
says how those two files were produced and what they do not cover. Each run
writes `sessionInfo.txt` next to its results.

The machine the study ran on, since neither lock file covers the GPU stack:

```
TensorFlow      2.10.0
CUDA (TF build) 11.2     what TensorFlow was compiled against -- match this
cuDNN           8
GPU             NVIDIA GeForce RTX 4060
Driver          596.49
CUDA (driver)   13.2     the highest runtime this driver supports, per nvidia-smi
```


## Reproducibility and what it is worth here

The restricted data mean nobody outside the lender can reproduce the AUC values,
and it would be dishonest to imply otherwise. What this repository does support
is the part that matters more: the diagnostics are cheap, general and run on any
fused forecaster. If you have a model with an added modality, you can take
`R/collapse/8_Diagnose_dead_branch.r`, point it at your own network, and find out
in a few minutes whether the branch you are crediting is reading its input at
all. That check is the manuscript's most portable contribution, and it does not
need our data.

## Known issues in this release

`AUDIT.md` is the full read-through: twenty-eight findings, what was done about
each, and which of them could touch a reported number (three, all resolved). The
headline items:

- **The areal bound is 0.67721, not 0.66223 (changed in v1.1.0).** v1.0.0
  treated the self-inclusive cell-rate ranking as inflated and reported the
  leave-one-out statistic. Reviewer 2 showed the reverse: a score constant
  within a cell, with within-cell ties counted ½, is the exact bound, and the
  leave-one-out score understates it. `R/ceiling/11_Level_diagnostics.r` now
  labels the two figures accordingly. See `AUDIT.md` A1 and `CHANGELOG.md`.
- **`R/model/5_HB_DLprec.r` reshapes the environmental tensor without a column
  permutation.** `array_reshape(x, c(n, 8, 9))` is C-order while the columns are
  laid out channel-major, so in the original network the LSTM's time axis was an
  interleaving of month and channel rather than time. Every later script fixes
  this with an explicit `COL_MAP` and a `stopifnot` — see
  `R/factorial/12_Factorial7_run.R`, whose header names the trap, and
  `R/model/7_ExpA_SAI_11ch.r`, which calls its own version "the correct reshape".
  **No published number is affected**: everything in the paper comes from the
  factorial, which permutes correctly and asserts it. The defect belongs to the
  superseded network alone, alongside the regulariser asymmetry, and is left in
  place rather than silently corrected because that file is published as evidence
  of what the original model did.
- **Eleven scripts still call `use_condaenv("tf-gpu", required = TRUE)`.** That
  fails on any machine where conda is not on `PATH`, which includes a
  double-clicked shortcut on an ordinary Anaconda install. Replace with
  `source("R/00_python_env.R"); bind_python("tf-gpu")`, which locates the
  environment on disk. `R/factorial/` already does this.
- **Scripts read their input filenames directly** rather than through
  `R/00_paths.R`. Until they are switched over, `SYNTH=1` does not reach them.
- The remaining twenty-four findings — a positional column slice, hard-coded
  layer widths, a `sum_dt` that is written before it is created, a heading that
  says five folds over code that runs ten — are in `AUDIT.md`.

## Uploading and archiving

`UPLOAD.md` is the step-by-step for putting this on GitHub and getting a Zenodo
DOI, including the two mistakes that cannot be undone afterwards.

## Licence and citation

MIT — see `LICENSE`. The licence covers the code only and confers no rights over
any BAAC data. `CITATION.cff` carries the machine-readable citation.

## Funding and competing interests

P.J. is an employee of the Bank for Agriculture and Agricultural Cooperatives
(BAAC) and is supported by a BAAC doctoral scholarship, which also covers the
article processing charge; BAAC owns the de-identified dataset analysed here.
These relationships are disclosed as a conflict of interest. BAAC's involvement
was limited to that scholarship support and to the release and de-identification
of the dataset under its internal data-governance rules. S.I., who has no
affiliation with BAAC, supervised and independently reviewed the data
processing, model specification and results.
