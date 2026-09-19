# Silent modality collapse and the measurement of fusion gains

Analysis code for a nationwide out-of-time test of Earth observation for
agricultural default forecasting, on a panel of 1,496,721 Thai rice-cultivating
borrowers and 4,490,163 borrower-years across 6,236 sub-districts and three
crop seasons.

> **Paper.** Jungsatidkul, P.; Innate, S. *Silent Modality Collapse and the
> Measurement of Fusion Gains: A Nationwide Out-of-Time Test of Earth
> Observation for Agricultural Default Forecasting.* Manuscript submitted to
> *Forecasting*, 2026.

## What is here

The borrower records are restricted and are not in this repository. Everything
else is: the code, the published result files, the schema, and a generator that
builds a synthetic panel with the same structure so the pipeline runs end to end
without them.

```
R/            analysis code, by stage            see R/README.md
gee/          Earth Engine extraction            see gee/README.md
data/         schema and synthetic generator     see data/README.md
output/       published results and diagnostics  see output/README.md
bat/          Windows launchers
```

`output/EXCLUDED.md` lists what was deliberately withheld, and why. It is worth
reading before concluding that something is missing by accident.

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
| Neutralising the environmental tensor in the fitted model | ΔAUC = 0.00000 | `R/collapse/8_Diagnose_dead_branch.r` | — |
| Recurrent input kernel against unregularised matrices | ≈ 7×10⁻⁸ of initialisation | `R/collapse/8_Diagnose_dead_branch.r` | `note` column of `factorial7_results.csv` |
| Per-channel attribution of the collapsed model | AUC drop ~1e-7 | `R/collapse/RiskCalendar.r` | `output/diagnostics/risk_calendar_collapsed/` |
| Month-permutation control | same order as the unpermuted attribution | `R/collapse/sequence.r` | same directory |
| Branch revival | — | `R/collapse/9_ExpC_revive_branch.r` | — |
| Neutralisation against refitting disagree in sign | +0.80 pp vs −0.50 pp recall | `R/collapse/MoAblation_StaticOnlyV2.r` | — |
| Intracluster correlation of default | 0.0517 | `R/ceiling/11_Level_diagnostics.r` | `output/results/cluster_structure_summary.csv` |
| Design effect, effective sample size | 13.41, 334,910 | same | same |
| Leave-one-out areal bound on (ADM3, Year) | 0.66223 | same | — |
| Self-inclusion bias in the naive bound | 0.01499 (0.67721 naive) | same | — |
| Best cell in the factorial | XGB, F+SP, 0.90730 | `R/factorial/12_Factorial7_run.R` | `output/results/factorial7_results.csv` |
| EO added to financial and spatial covariates | loses AUC in 4 of 5 families | same | same |
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

- **The leave-one-out correction was missing from the repository and has been
  added.** The bound the paper reports as 0.66223 is a leave-one-out oracle, but
  `R/ceiling/11_Level_diagnostics.r` computed only the naive self-inclusive
  version. The correction is now in the script, and running it on the real panel
  reproduces every published figure exactly — 0.66223 corrected, 0.67721 naive,
  0.01499 of self-inclusion bias. See `AUDIT.md` A1.
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
