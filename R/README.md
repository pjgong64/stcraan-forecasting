# R/

Run order, and what each script is for.

## Shared

| File | Purpose |
|---|---|
| `00_paths.R` | Every data path in one place. Switch to the synthetic panel with `SYNTH=1`. Also holds the seed, `dump_session()`, and `seq_columns()` for name-based selection of the environmental block. |
| `00_python_env.R` | Binds reticulate to a TensorFlow environment by locating it on disk, so that nothing depends on conda being on `PATH`. Source this instead of calling `use_condaenv()`. |

## prep/ — building the analysis file

| File | Purpose |
|---|---|
| `datamani.r` | Stacks the three annual financial extracts and handles outliers. |
| `geomaniV2.r` | Assembles the eleven environmental channels from the per-year, per-channel CSVs exported by `gee/`. |
| `Join_Normalize.r` | The whole feature pipeline: `log1p`, winsorisation at the 1st and 99th percentiles, `apply_global_minmax()` per channel, and target encoding of the five categoricals with additive smoothing. Every bound, min, max and encoding mean is estimated on `Year %in% c(1, 2)` and applied unchanged to year 3. |
| `6_Build_SAI_file.r` | Adds the 16 `norm_SAI_*` columns, scaled exactly as the main pipeline scales everything else. Produces the 11-channel file. |
| `SAI_NDVI_NDWI.r` | The screening test. Shows that the seasonal mean and max of a standardised anomaly sit near zero by construction while six of eight of its monthly columns clear the retention threshold. |

## model/

| File | Purpose |
|---|---|
| `5_HB_DLprec.r` | The original dual-branch training script, and the most important file in the repository for anyone checking the paper's central claim. Lines 95 and 100 apply `kernel_regularizer = regularizer_l2(l = wd_rate)` to both LSTM layers while leaving `recurrent_regularizer` unset; line 150 adds `clipnorm = 1.0`. That asymmetry — decay on the input kernel, none on the recurrent matrix — is the mechanism described in Section 4.3, and it is visible in three lines of ordinary Keras. A second defect sits in the same file: the tensor reshape at line 72 has no column permutation, so its time axis interleaves month with channel. Both are left uncorrected — the file is published as a record of what the original model did, not as code to reuse. |
| `7_ExpA_SAI_11ch.r` | 9 channels against 11: do sub-district standardised anomalies add anything that raw levels do not, once ADM3 identity is already in the model? |

## collapse/ — the diagnosis and the repair

| File | Purpose |
|---|---|
| `8_Diagnose_dead_branch.r` | Locates the failure: encoder or fusion. Reports the magnitude of the recurrent input kernel against the unregularised recurrent and bias matrices. |
| `9_ExpC_revive_branch.r` | The repair: drop the kernel regulariser, add an auxiliary head off the recurrent output, drop `clipnorm`, warm-start from a temporal-only model. |
| `MoAblation_StaticOnlyV2.r` | Modality ablation, static branch only. Refitting, as against neutralisation inside a fitted model. |
| `RiskCalendar.r` | Produces the per-channel, per-month attribution in `output/diagnostics/risk_calendar_collapsed/`. Run against the collapsed model; see that directory's note. |
| `STCRAAN_shuffle_month.r` | The shuffled-month control. |
| `sequence.r` | Scores a saved permutation. **Selects columns positionally** (`all_cols[42:113]`) — see `data/schema/codebook.md` before running it on anything but the original 9-channel file. |
| `month_perm.rds` | The permutation, so the control is reproducible rather than merely repeatable. |

## factorial/ — the main experiment

| File | Purpose |
|---|---|
| `12_Factorial7_config.R` | The only file to edit. Feature blocks, the eight arms, the five families, every hyper-parameter. Carries `CFG$config_version` so a stale copy is detectable. |
| `12_Factorial7_run.R` | 5 families x 8 feature sets. Finished cells are skipped, so it resumes after a stop. |
| `12_Factorial7_partition.R` | Settles by measurement whether each target encoding is coarser than, equal to, finer than, or crosscutting with respect to the ADM3 partition. This is what makes `SPA` a defined object rather than an assumption, and therefore what makes the falsification test a test. |
| `12_Factorial7_report.R` | Reads the results file and prints the paper's tables. Reads only; safe to run in a second terminal while the grid is going. |

## ceiling/

| File | Purpose |
|---|---|
| `11_Level_diagnostics.r` | Intracluster correlation, design effect, effective sample size, and the leave-one-out oracle bound on (ADM3, Year). The self-inclusion correction is worth 0.015 of AUC and is not optional. |

## evaluation/

| File | Purpose |
|---|---|
| `XGB.r` | Compares two separately fitted models at **matched alert volume** rather than at a fixed probability threshold. Twenty lines, and the reason an earlier reported advantage of 13.23 percentage points did not survive. |

## gee/ — environmental extraction

Earth Engine JavaScript. See `gee/README.md`.

## superseded/

| File | Why it is here |
|---|---|
| `10_Factorial_EO.r` | The earlier four-family factorial, replaced by `factorial/`. Kept for provenance. It fixes an alert rate of 0.2535 and a class weight of 100/6.575, both tied to an operating point the manuscript no longer uses. Do not read its constants as current. |
