# Changelog

## v1.1.1 — empty cells filled; the rolling-origin ST-CRAAN gain examined

- MLP and ST-CRAAN fitted on the EO-only and SP-only arms of the grouped
  refit (Table S6) and of the rolling-origin check (Table 10), which v1.1.0 left
  empty. On its own, EO stays at chance on 2022 (0.489 and 0.511) and reaches
  0.515 and 0.528 on 2021, no better than logistic regression on flattened
  columns (0.542).
- The single-fit gain of ST-CRAAN from EO on the rolling split (+0.0254 on
  FIN + SP) does not survive refitting. Over that fit and seeds 101, 202 and 303
  the change is +0.0254, −0.0075, +0.0204 and +0.0055. With the architecture held
  fixed, neutralising EO in a refitted two-branch model lowers 2021 AUC by
  0.0002. The gain belongs to the change from one branch to two, not to EO.
- Added `R/revision/12_Factorial7_run_rolling_diag.R` and `bat/run_fill_all.bat`.
- Conclusions unchanged.

## v1.1.0 — revision round 1 (October 2026)

Code and results added to answer the reviewers of the *Forecasting* submission
(forecasting-4611303). The 2022 season is still used only for scoring: no script
in this release fits, tunes or selects anything on it.

### Added

- `R/revision/` — four scripts, each a copy of a published script with one stated
  change: borrower-grouped validation with out-of-fold target encodings
  (`12_Factorial7_run_grouped.R`), a rolling-origin check that fits on 2020 and
  scores 2021 (`12_Factorial7_run_rolling.R`), the ablation of the branch revival
  and the planted-signal simulation (`13_R1_ablation_sim.R`), and branch-health
  diagnostics for the factorial's ST-CRAAN (`12_Factorial7_run_diag.R`).
  `R/revision/README.md` describes each one.
- `python/revision/` — post-processing of saved 2022 scores: the exact areal
  bound, the sub-district-clustered bootstrap, intervals pooled over refits, and
  the table of contrasts over runs. Nothing in it fits a model.
- `output/revision/` — every result file the revised manuscript cites. All are
  aggregates; none has a row per borrower or per sub-district.
- `bat/` — the six launchers used to run the above on Windows.

### Changed

- `R/factorial/12_Factorial7_run.R` accepts `seed=<n>` and `arms=<a,b,...>` and
  writes each seed to its own directory, which is how the refits behind Table 9
  were produced. With neither argument it behaves exactly as in v1.0.0.
- **The areal bound.** v1.0.0 reported the leave-one-out statistic, 0.66223, as
  the bound and called the self-inclusive cell-rate ranking inflated. That was
  backwards. A score that is constant within a cell, with within-cell ties
  counted ½, gives the exact upper bound for any such predictor, 0.67721; the
  leave-one-out score places each defaulter below the non-defaulters of its own
  cell and of neighbouring cells with nearly equal rates, so it understates the
  bound. `R/ceiling/11_Level_diagnostics.r` computed both numbers all along; only
  its labels change. Every family still stays below the bound, now by 0.029 to
  0.031.
- **The mechanism of the collapse.** v1.0.0 attributed the collapse to weight
  decay on the recurrent input kernel together with gradient starvation. The
  ablation shows that starvation is the cause. Removing the penalty alone keeps
  the kernel at the order of its initialisation, yet 62 of 64 hidden units stay
  constant. Only the auxiliary head revives the branch on its own. Weight decay
  completes the collapse by shrinking a kernel that no longer receives gradient.
- **The diagnostics.** The input-kernel magnitude is a symptom, not a test: it
  can look normal in an inert branch. The decisive quantities are the
  across-borrower SD of the branch representation and the mean |Δ logit| under
  neutralisation. Proposed thresholds: inert below 10⁻³, in use above 10⁻², and
  contributing only if neutralisation lowers test AUC by more than its paired
  bootstrap standard error (about 10⁻⁴ here; 0.001 as a practical threshold).

### Unchanged

The conclusion. Over refits, EO lowers test AUC in every fit of the three
tabular families and gives the two neural families no reliable gain; added to
areal repayment history it lowers test AUC in every fit of every family; and the
factorial's ST-CRAAN reads its EO input without benefiting from it.

## v1.0.0 — the state the manuscript describes

First public release. Contains the analysis code for the factorial, the collapse
diagnostics, the areal-ceiling calculation, the matched-alert-volume comparison,
the published result files, and a synthetic panel generator.

### What changed relative to the work described in the Zenodo preprint

This release supersedes an earlier version of the study, and the differences are
not refinements. They reverse three of its conclusions.

- **The environmental branch was inert.** Weight decay on the recurrent input
  kernel, together with gradient starvation under late fusion, had driven that
  kernel to approximately 1e-7 of its initialisation while the unregularised
  recurrent and bias matrices stayed at ordinary magnitude. Replacing the entire
  environmental tensor with its population mean changed test AUC by 0.00000.
  `R/collapse/8_Diagnose_dead_branch.r` is the diagnosis;
  `R/collapse/9_ExpC_revive_branch.r` is the repair.

- **The reported advantage over gradient boosting was a calibration artefact.**
  It came from comparing two separately fitted models at a fixed probability
  threshold. Compared at matched alert volume, it does not survive.
  `R/evaluation/XGB.r` is twenty lines and is what settled it.

- **The reported modality gain came from a missing class weight in one ablation
  script**, not from the environmental data.

The earlier per-channel attribution files are published in
`output/diagnostics/risk_calendar_collapsed/` as evidence of the first item,
not as attribution for a working model.

### Known gaps in this release

See "Known issues" in the README. Nothing in them affects a published number;
they are stated because a reader will meet them.
