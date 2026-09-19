# Codebook

What the analysis file looks like. The real file is restricted; this document
describes it precisely enough that `data/synthetic/make_synthetic.R` reproduces
its shape, and precisely enough that a reader holding an equivalent panel of
their own can put it into the same form.

## The file

Pipe-delimited (`sep = "|"`), UTF-8, one row per borrower-year, header row
present. Two versions exist and both are used:

| File | Channels | Sequence columns | Used by |
|---|---|---|---|
| `data_hybrid2_prec.txt` | 9 | 72 | the earlier sequential scripts |
| `data_hybrid2_prec_sai.txt` | 11 | 88 | `R/factorial/`, everything current |

`R/prep/6_Build_SAI_file.r` produces the second from the first.

## Outcome and keys

| Column | Type | Definition |
|---|---|---|
| `ID` | character | Anonymised borrower identifier. Stable across years. |
| `Year` | integer | `1` = 2020, `2` = 2021, `3` = 2022. Year 3 is the withheld season and is never used to estimate anything. |
| `Y` | 0/1 | Default. Basel III non-performing: more than ninety days past due within the crop year. |
| `ADM3` | integer | Thai sub-district code. 6,236 distinct values. |

`ADM3` together with `Year` defines the cell. Every borrower in a cell carries
an **identical** environmental sequence. That is not an artefact of the file
format; it is the property the manuscript is about.

## Static covariates

48 columns, listed with their block, transform and marginal correlation in
`financial_columns.csv`. The blocks matter because the factorial arms are
defined on them:

- **FIN** (44) — borrower-level. 43 numeric covariates plus `TE_IDDT`, the
  land-rights document class, which is a nationwide categorical rather than a
  place and so belongs here on the merits.
- **SPA** (2) — `TE_ADM3`, `TE_IDProv_rice`. Constant within every (ADM3, Year)
  cell, and therefore the only block the areal bound constrains.
- **SP** (4) — SPA plus `TE_ADM3RL` and `TE_IDProv_RL`, which split cells and
  are consequently **not** bounded by 0.66223. Testing `EO+SP` against that
  bound would be a category error; the falsification arm is `EO+SPA`.

All target encodings are fitted on years 1–2 only and applied unchanged to
year 3. No quantity anywhere in the evaluation is informed by the forecast year.

## Sequence columns

`<channel prefix><month>`, month running 5 to 12 (May to December), which spans
land preparation through harvest for main-season rice. With 11 channels that is
88 columns. Channels are listed in `eo_channels.csv`.

Example: `norm_NDVI5` … `norm_NDVI12`, then `norm_NDWI5` … and so on.

## Column order — read this before running the sequential scripts

The file is written in this order:

```
ID | Year | Y | ADM3 | <44 FIN> | <4 SP> | <88 EO>
```

`R/collapse/sequence.r` selects its sequence block **positionally**, as
`all_cols[42:113]`, and reshapes it as `matrix(nrow = 8, ncol = 9)` — eight
months by nine channels, month varying fastest. That index is correct for the
real 9-channel file and for nothing else. It will not error on a file whose
columns sit elsewhere; it will silently read the wrong columns and return a
plausible number.

Two consequences:

1. If you regenerate or reorder the analysis file, fix `sequence.r` to select by
   name before you run it. A `grep("^norm_", names(dt))` costs nothing and
   removes the failure mode entirely.
2. The synthetic panel does not have the same layout — its sequence block starts
   at column 53, and `synthetic_manifest.txt` records the index of the run that
   produced it.

## Auxiliary categoricals

Not in the analysis file, but needed to build the target encodings:

| Name | Levels | Note |
|---|---|---|
| Province (`IDProv`) | 77 | Coarser than ADM3 |
| Residential location (`RL`) | — | Crosses ADM3 boundaries |
| Land-document type (`DT`) | 64 | One level appears in 5,741 of 6,236 sub-districts |

`R/factorial/12_Factorial7_partition.R` settles by measurement, rather than by
assumption, whether each encoding is coarser than, equal to, finer than, or
crosscutting with respect to the ADM3 partition. Run it before trusting any
block assignment above on a panel that is not ours.

## Corrections to the published supplementary materials

Two entries in Table S1/S2 of the supplement do not match the code, and this
table is the correct one.

| Item | Supplement says | Correct |
|---|---|---|
| `eYie` units | metric tonnes | **kilograms** — which is why `Proxy_DSR` divides by 1000 |
| `Proxy_DSR` formula | `Out / eInc`, identical to `Debt_to_Income` | `Out / ((eYie / 1000) * ePrcton)` |

`eYierai` is correct as printed: tonnes per rai. Only `eYie` is misstated.

The second is the one that matters. As printed, `Proxy_DSR` and
`Debt_to_Income` are the same quantity, which would make one of them redundant.
They are not: `Debt_to_Income` divides by the recorded estimated-income field,
while `Proxy_DSR` divides by revenue reconstructed from yield and farm-gate
price. That is why their point-biserial correlations with default differ
(0.0511 against 0.0622) rather than being identical.

## Transforms, as `R/prep/Join_Normalize.r` applies them

| Prefix | Operation |
|---|---|
| `norm_log_` | `log1p(x)` — not `log(x)`; the distinction matters at zero balances, which are common here |
| `norm_win_` | winsorised at the 1st and 99th percentiles **of years 1-2**, then scaled |
| `norm_` on sequence columns | `apply_global_minmax()` per channel across all eight months, not per month |
| `TE_` | mean of the outcome within the level with additive smoothing, fitted on years 1-2 |

Every bound, every min and max, and every encoding mean is estimated on
`which(dt$Year %in% c(1, 2))` and applied unchanged to year 3.
