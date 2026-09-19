# output/ — result files accompanying the manuscript

Everything here is an **aggregate model result or diagnostic**. No borrower-level record,
and no sub-district-level default statistic, is published in this repository. See
`EXCLUDED.md` for what was deliberately left out and why.

## results/

| File | Contents | Used in |
|---|---|---|
| `factorial7_results.csv` | The full factorial: 5 model families x 8 feature sets = 40 cells. Development and withheld-season AUC, sample and feature counts, fit time, and recall / false negatives at matched alert volumes of 10, 20 and 30 percent. The `note` column records the fitted L2 magnitudes of the recurrent input kernel and the recurrent matrix for each ST-CRAAN cell, which is the branch-health check described in Section 3.4. | Tables 4-7, Sections 4.1-4.8 |
| `factorial7_matrix_testAUC.csv` | The same withheld-season AUC values pivoted to family x arm. Derived from the file above; kept for convenience. | Table 4 |
| `cluster_structure_summary.csv` | Aggregate cluster structure of the panel: number of ADM3-year cells, cell-size distribution, intracluster correlation of default, design effect, effective sample size. Aggregates only - no row identifies a sub-district. | Section 2, Table 1 |

## diagnostics/

| File | Contents |
|---|---|
| `rpb_static.csv` | Point-biserial correlation with default for each of the 48 financial and administrative covariates. |
| `rpb_sequential.csv` | Point-biserial correlation with default for each of the 9 retained environmental channels, by month (May-December). |
| `ChannelResponse_quantile.csv` | Mean shift in predicted log-odds when each environmental channel in turn is fixed at successive quantiles of its own distribution, all other inputs at their observed values. |
| `risk_calendar_collapsed/` | Per-channel, per-month attribution of the **collapsed** network, before the recurrent branch was revived, together with a month-permutation control on the same network. See the note below. |

### risk_calendar_collapsed/ — what these files are, and are not

These five files were produced by the dual-branch network in the state described in
Section 4.3, in which weight decay applied to the recurrent input kernel had driven that
kernel to approximately 1e-7 of its initialisation while the unregularised recurrent and
bias matrices remained at ordinary magnitude. The environmental branch was emitting a
constant. They are published as **evidence of that condition**, not as attribution for a
working model.

Read that way they are informative, and the reason we publish them: the AUC drop on
removing any single environmental channel is of order 1e-7
(`RiskCalendar_AUCdrop.csv`), the per-month log-odds contributions are of order 1e-4
(`RiskCalendar_absLogOdds.csv`, `_absLogOddsV2.csv`, `_signed.csv`), and the shuffled-position
control (`RiskCalendar_SHUFFLE_absLogOdds.csv`) is of the same order as the unpermuted
attribution rather than smaller than it. A channel-attribution report of this shape is the
signature of an inert branch, and had we read these numbers as a finding about seasonality
rather than as a symptom, we would have reported a month-by-month risk calendar derived
from a network that was not reading the environmental tensor at all.

On that last file: it is a **scoring-time** permutation, not a network retrained on
scrambled months. The production model's own months were reordered at inference and its
per-position attribution recomputed. A network genuinely reading a time series should
respond to that; this one did not, because the branch feeding it was emitting a constant.
`R/collapse/sequence.r` names the model it loads at the top of the file and prints it at
run time, so this cannot be mistaken again.

No attribution files are published for the revived network. Section 4.12 explains why
per-channel attribution is not a quantity we are willing to report once neutralisation and
refitting are known to disagree in sign.

## Reproducing these files

Every file here is written by the scripts in `R/`; the traceability table in the repository
README maps each published number to the script that produces it. The pipeline runs end to
end on the synthetic panel in `data/synthetic/`, which reproduces the cluster structure of
the real panel but contains no real records.
