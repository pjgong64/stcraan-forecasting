"""
R1 (revision, reviewer 2 comment M2): exact areal ceiling on the withheld 2022 season.

Computes three cell-level rankings of 2022 borrowers, cell = (ADM3, Year):
  1. EXACT  : every borrower scored by the realised 2022 default rate of its own
              cell (Eq. S9). All borrowers in a cell share one score, so every
              within-cell defaulter/non-defaulter pair is a tie and counts 1/2.
              Cells with equal realised rates are also tied (count 1/2).
              This is the maximum AUC attainable by ANY score that is constant
              within a cell (the realised rate orders cells optimally in-sample).
  2. LOO    : the leave-one-out statistic r_i = (d_c - y_i)/(n_c - 1) used in the
              submitted Note S1 (Eq. S10). Not constant within a cell: defaulters
              get a strictly lower score than non-defaulters of the same cell.
  3. Within-cell ties check: share of defaulter/non-defaulter pairs inside a cell.

No model is fitted. 2022 outcomes are used only to evaluate a bound, as in the
submitted manuscript. Nothing here is used to fit, tune or select a model.

Input : keys_test.rds  (columns y, adm3, id; one row per 2022 borrower)
Output: printed table + CSV
"""
import sys
import numpy as np
import pandas as pd
import pyreadr
from scipy.stats import rankdata


def auc_midrank(score, y):
    """Mann-Whitney AUC with ties counted 1/2 (mid-ranks)."""
    y = np.asarray(y).astype(bool)
    r = rankdata(score)  # average ranks -> ties count 1/2
    n1 = y.sum(); n0 = (~y).sum()
    return (r[y].sum() - n1 * (n1 + 1) / 2) / (n1 * n0)


def main(keys_path, out_csv):
    k = list(pyreadr.read_r(keys_path).values())[0]
    y = k["y"].to_numpy().astype(int)
    cell = k["adm3"].to_numpy()
    df = pd.DataFrame({"y": y, "cell": cell})
    g = df.groupby("cell")["y"].agg(["sum", "count"])
    d = df["cell"].map(g["sum"]).to_numpy()
    n = df["cell"].map(g["count"]).to_numpy()

    P = y.sum(); N0 = len(y) - P
    exact = auc_midrank(d / n, y)

    # LOO (Eq. S10); singleton cells have no LOO rate -> give them the global rate
    with np.errstate(divide="ignore", invalid="ignore"):
        loo = np.where(n > 1, (d - y) / (n - 1), P / len(y))
    loo_auc = auc_midrank(loo, y)

    # share of D/ND pairs lying inside one cell
    within_pairs = (g["sum"] * (g["count"] - g["sum"])).sum()
    share_within = within_pairs / (P * N0)
    # if within-cell pairs counted 0 instead of 1/2, the exact value would drop by share/2
    rows = [
        ("borrowers", len(y)), ("defaulters", int(P)), ("cells (ADM3) in 2022", len(g)),
        ("singleton cells", int((g["count"] == 1).sum())),
        ("EXACT ceiling, realised cell rate, ties = 1/2 (Eq. S9)", exact),
        ("LOO statistic of submitted Note S1 (Eq. S10)", loo_auc),
        ("difference LOO - exact", loo_auc - exact),
        ("share of D/ND pairs inside a cell", share_within),
    ]
    out = pd.DataFrame(rows, columns=["quantity", "value"])
    pd.set_option("display.float_format", lambda v: f"{v:.6f}")
    print(out.to_string(index=False))
    out.to_csv(out_csv, index=False)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
