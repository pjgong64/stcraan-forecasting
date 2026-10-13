# R/revision/ — analyses added in revision round 1

These scripts answer the reviewers of the *Forecasting* submission
(forecasting-4611303). Each one is a copy of a published script with one stated
change, so the difference from the original can be read with a plain `diff`.

**One rule holds in every script: the 2022 season is never used to fit, tune or
select anything.** It is only scored.

| File | Reviewer comment | What it changes | Writes | Paper |
|---|---|---|---|---|
| `12_Factorial7_run_grouped.R` | M3(c), M5 | Two corrections together: the development-year target encodings are computed **out of fold** over five borrower folds, and the 15% early-stopping portion is drawn **by borrower**, so no borrower sits on both sides (224,507 borrowers held out). The 2022 encodings are rebuilt and asserted identical to the published ones. | `factorial7_out/grouped_val_oof/` | §4.16, Table S6 |
| `12_Factorial7_run_rolling.R` | M3(a) | Rolling origin: fit on 2020 alone, score 2021. 2022 is not read. Encodings for 2021 come from 2020 outcomes only; the 2020 ones are out of fold. Same grouped split as above. | `factorial7_out/rolling_2020_to_2021/` | §4.15, Table 10 |
| `13_R1_ablation_sim.R` | M4 | Configuration A (two-layer LSTM). `ablation`: ten fits that add each revival setting alone to the inherited model and remove each one alone from the revived model. `sim`: a known signal is planted in the labels of a 20% borrower subsample, with β ∈ {0, 0.5, 1.5}, and the inherited and revived models are refitted at each β. | `factorial7_out/r1_ablation_sim.csv` | §4.6.1, §4.6.2, Tables S7–S8 |
| `12_Factorial7_run_diag.R` | M1(d), M4 | After every fused ST-CRAAN fit (Configuration B), it records the branch-health diagnostics (across-borrower SD of the recurrent representation, dead units, fusion weight ratio) and neutralisation (test AUC and mean \|Δ logit\| with the EO tensor replaced by its column means). | `factorial7_out/diag_configB/configB_diag.csv` | §3.4, §4.9.2, §4.10, §4.12, Table S9 |

The repeated fits behind Table 9 do not need a separate script.
`R/factorial/12_Factorial7_run.R` (updated in v1.1.0) takes `seed=<n>` and
`arms=<a,b,...>` on the command line and writes each seed to
`factorial7_out/repeat_seed<n>/`.

## How to run

The scripts expect to sit in one folder with `12_Factorial7_config.R`,
`12_Factorial7_report.R` and the analysis file named in the config
(`data_hybrid2_prec_sai.txt`). The grouped and rolling variants also read the raw
administrative codes from `3_fin3y20_22.txt` to rebuild the encodings. That is the
layout the study ran in, and the launchers in `bat/` assume it too. Copy the
script and its launcher next to `R/factorial/` files, then:

```
Rscript 12_Factorial7_run_grouped.R auto                     # all families, all arms
Rscript 12_Factorial7_run_rolling.R auto
Rscript 13_R1_ablation_sim.R ablation
Rscript 13_R1_ablation_sim.R sim
Rscript 12_Factorial7_run_diag.R STCRAAN arms=F+EO,F+SP+EO,EO+SPA auto
Rscript 12_Factorial7_run.R MLP STCRAAN arms=F,F+EO,F+SP,F+SP+EO,SPA,EO+SPA seed=101 auto
```

Finished cells are skipped, so every script resumes after a stop. On Windows the
matching launchers are `bat/run_grouped_val.bat`, `bat/run_after_grouped.bat`
(rolling, then ablation, then simulation), `bat/run_ablation_sim.bat`,
`bat/run_diag_configB.bat`, `bat/run_repeat_fits.bat` (tabular seeds) and
`bat/run_repeat_deep.bat` (neural seeds).

On the study machine (RTX 4060, 8 GB; 32 GB RAM) a neural cell takes 38–45 minutes,
a fit of `13_R1_ablation_sim.R` 20–45 minutes.

## Python post-processing

`python/revision/` reads only saved result files and saved 2022 test scores.
It fits nothing. It needs `numpy`, `pandas`, `scipy` and `pyreadr`.

| File | Reviewer comment | Does | Writes |
|---|---|---|---|
| `r1_areal_ceiling.py` | M2 | Exact areal ceiling (Eq. S9: realised cell rate, ties ½) and the leave-one-out statistic, from `keys_test.rds` | `r1_areal_ceiling.csv` |
| `r3_cluster_bootstrap.py` | M3 | Sub-district-clustered bootstrap of test AUC, paired across models | `*_cells.csv`, `*_contrasts.csv` |
| `r4_seed_pooled_ci.py` | M3 | Pools bootstrap draws over refits (B = 1,000 per run for the tabular families, 400 for the neural ones), so the interval carries both test-sample and training variability | `seedci_*_per_run.csv`, `seedci_*_pooled.csv` |
| `r5_runs_table.py` | M3 | EO contrasts per run and their mean, SD and sign count | `r5_*.csv` |

```
python r1_areal_ceiling.py factorial7_out/pred/keys_test.rds r1_areal_ceiling.csv
python r3_cluster_bootstrap.py factorial7_out/pred boot_refit1 2000      # seed 20261010 by default
python r4_seed_pooled_ci.py factorial7_out/pred/keys_test.rds seedci_tabular 1000 refit1=factorial7_out/pred s101=factorial7_out/repeat_seed101/pred ...
python r4_seed_pooled_ci.py factorial7_out/pred/keys_test.rds seedci_neural 400 refit1=factorial7_out/pred s101=factorial7_out/repeat_seed101/pred ...
python r5_runs_table.py factorial7_out
```

`keys_test.rds` and the `pred/` score files hold one row per 2022 borrower and are
not published (see `output/EXCLUDED.md`). Their outputs are in `output/revision/`.
