# Files deliberately not published

## cluster_summary_ADM3_Year.csv

Per-cell counts for all 18,647 sub-district-year cells: sub-district code, year, number
of borrowers (`n`), number of defaults (`k`), default rate (`p`).

Excluded for two independent reasons.

**Proprietary.** The table is a sub-district-level default-rate map of the lender's
agricultural portfolio, derived directly from the restricted borrower records. It is the
Bank for Agriculture and Agricultural Cooperatives' commercial information, not a public
statistic, and the Data Availability Statement does not cover it.

**Disclosive at small cell sizes.** 1,878 cells contain fewer than ten borrowers, 451
contain exactly one, and 254 cells with five or fewer borrowers record at least one
default. For those cells the table states, for a named sub-district and a known year, that
a specific borrower or a group of at most five defaulted. No suppression rule recovers the
file's analytical value while removing that, because the analyses that need it - the
leave-one-out areal bound in particular - depend on the small cells.

**What is published instead.** `output/results/cluster_structure_summary.csv` reports the
aggregate quantities the manuscript cites (cell count, cell-size distribution,
intracluster correlation, design effect, effective sample size), and `R/32_areal_ceiling_loo.R`
computes the bound from the restricted table for anyone holding an equivalent panel of
their own.

## Fitted model weights

Not published. The networks are fitted on 1,496,721 individual borrower histories, and
released weights are a re-identification surface that the Data Availability Statement does
not address. Architectures, hyperparameters and random seeds are in `R/` and are sufficient
to reproduce the models from an equivalent panel.

## Target-encoding maps

Not published, for the same reason as `cluster_summary_ADM3_Year.csv`: a fitted target
encoding of the sub-district identifier is a smoothed default-rate map of the portfolio.
The fitting code is in `R/03_target_encoding.R`.
