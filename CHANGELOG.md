# Changelog

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
