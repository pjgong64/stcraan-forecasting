# data/

There is no real data in this repository, and there will not be.

The borrower records are proprietary to the Bank for Agriculture and
Agricultural Cooperatives (BAAC) and cannot be released. That restriction is not
a formality. The panel is 1,496,721 individual credit histories, and the
sub-district aggregates derived from it are, at the small cells, statements
about identifiable people — see `../output/EXCLUDED.md`, which lists what was
withheld and why.

The Earth observation inputs are open archives. Every product, version and band
is named in `schema/eo_channels.csv`, and `../gee/` contains the extraction code,
so that side of the panel is reconstructible by anyone.

## What is here instead

| Path | What it is |
|---|---|
| `schema/financial_columns.csv` | All 48 static covariates: block, kind, transform, marginal correlation with default |
| `schema/eo_channels.csv` | All 11 environmental channels: product, band, whether derived, whether retained |
| `schema/codebook.md` | File format, outcome definition, year coding, block definitions, and the exact column order |
| `synthetic/make_synthetic.R` | Generates a synthetic panel with the same structure |
| `synthetic/smoke_data.xlsx` | A three-row mock extract of the pre-normalisation financial panel, for checking that a reader's file is laid out the way the pipeline expects. The values are invented; no row corresponds to a real borrower. Its header is a run of column indices rather than names, and it carries 137 columns against the analysis file's 140 — fix both before relying on it as a fixture. |

## Running the pipeline without the real data

```
cd data/synthetic
Rscript make_synthetic.R            # ~1 minute, writes panel_synthetic.txt
SYNTH_SCALE=1.0 Rscript make_synthetic.R   # the real dimensions; several GB
```

The generated panel is **not committed** — `.gitignore` excludes
`panel_synthetic*.txt`, since even the default scale produces a file too large
for git. Generate it once after cloning. `synthetic_manifest.txt` records what
the run produced and how close it landed to the published values.

At `SYNTH_SCALE=1.0` the generator reproduces the published cluster structure:

| Quantity | Real panel | Synthetic |
|---|---|---|
| Rows | 4,490,163 | 4,481,015 |
| Cells | 18,647 | 18,708 |
| Mean / median cell size | 240.8 / 197 | 239.5 / 196 |
| Cells with fewer than 10 borrowers | 10.1% | 10.2% |
| Default rate | 0.0782 | 0.0789 |
| Intracluster correlation | 0.0517 | 0.0518 |
| Design effect | 13.41 | 13.35 |
| Effective sample size | 334,910 | 335,576 |

What it does **not** reproduce is the joint dependence among the financial
covariates. Each is calibrated to its own marginal correlation with default and
is otherwise independent, so a model fitted on the synthetic panel will not
reach the AUC values in the paper. The point is that the code runs and that its
structural results — the areal bound, the constancy of the environmental tensor
within a cell, the inertness of a collapsed branch — are visible and testable.
Nothing about the synthetic panel should be reported as a finding.

## Reading the column names

The convention is regular: `norm_log_X` is the natural log of X then min–max
scaled, `norm_win_X` is X winsorised at the 1st and 99th percentiles then scaled,
`norm_nX` is a count, a trailing `b` marks a beginning-of-year balance against
the year-end one (`Depb`/`Dep`, `CLb`/`CL`, `Outb`/`Out`), a leading `e` marks an
estimated quantity, and `IDRV_k` is a dummy for rice variety k. The convention
tells you the transform, not the quantity, so every column carries a gloss in
`schema/financial_columns.csv`, and the fifteen derived ratios carry their
formula as well.

Monetary variables are in Thai baht; areas are in rai (1 rai = 1,600 m² =
0.16 ha); yields are in metric tonnes.
