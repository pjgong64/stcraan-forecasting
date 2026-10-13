"""
R3 (revision, reviewer 2 comment M3): sub-district-clustered bootstrap for test AUC.

Resampling unit = sub-district (ADM3) of the withheld 2022 season, because the
EO tensor and the areal encodings are constant within a sub-district, so the
effective number of independent units for those inputs is the number of cells,
not the number of borrowers.

For each replicate b = 1..B:
  draw C sub-districts with replacement from the C observed ones;
  every borrower inherits the multiplicity of its sub-district as a weight;
  compute the weighted (tie-aware) AUC of every model with the SAME weights,
  so differences between models are paired.
Reports, per model, the percentile 95% CI of AUC, and per contrast the
percentile 95% CI of the AUC difference and the share of replicates < 0.

Only saved 2022 test scores are used. Nothing is fitted, tuned or selected.

Usage: python r3_cluster_bootstrap.py <pred_dir> <out_prefix> [B] [seed]
"""
import sys, os, glob, time
import numpy as np
import pandas as pd
import pyreadr

ARMS = ["F", "F_EO", "F_SP", "F_SP_EO", "EO", "SP", "SPA", "EO_SPA"]
FAMS = ["LR", "RF", "XGB", "MLP", "STCRAAN"]
CONTRASTS = [  # (label, base arm, arm with EO)
    ("EO given FIN+SP  (F+SP -> F+SP+EO)", "F_SP", "F_SP_EO"),
    ("EO given FIN     (F -> F+EO)", "F", "F_EO"),
    ("EO given SPA     (SPA -> EO+SPA)", "SPA", "EO_SPA"),
    ("SP given FIN     (F -> F+SP)", "F", "F_SP"),
]


def read1(path):
    v = list(pyreadr.read_r(path).values())[0]
    return v.iloc[:, 0].to_numpy(dtype=float)


class WeightedAUC:
    """Pre-sorts one score vector so each weighted AUC costs two bincounts."""
    def __init__(self, score, y):
        uniq, gid = np.unique(score, return_inverse=True)  # ascending groups
        self.gid = gid; self.G = len(uniq); self.y = y.astype(float)

    def __call__(self, w):
        pos = np.bincount(self.gid, weights=w * self.y, minlength=self.G)
        neg = np.bincount(self.gid, weights=w * (1 - self.y), minlength=self.G)
        neg_below = np.cumsum(neg) - neg
        return float((pos * (neg_below + 0.5 * neg)).sum() / (pos.sum() * neg.sum()))


def main(pred_dir, out_prefix, B=2000, seed=20261010):
    keys = list(pyreadr.read_r(os.path.join(pred_dir, "keys_test.rds")).values())[0]
    y = keys["y"].to_numpy().astype(int)
    cl_codes, cl = np.unique(keys["adm3"].to_numpy(), return_inverse=True)
    C = len(cl_codes)
    models = {}
    for f in FAMS:
        for a in ARMS:
            p = os.path.join(pred_dir, f"pred_{f}__{a}.rds")
            if os.path.exists(p):
                s = read1(p); assert len(s) == len(y)
                models[(f, a)] = WeightedAUC(s, y)
    print(f"{len(models)} models, {len(y):,} borrowers, {C:,} sub-districts, B = {B}")

    ones = np.ones(len(y))
    point = {k: m(ones) for k, m in models.items()}
    rng = np.random.default_rng(seed)
    boot = {k: np.empty(B) for k in models}
    t0 = time.time()
    for b in range(B):
        mult = np.bincount(rng.integers(0, C, C), minlength=C).astype(float)
        w = mult[cl]
        for k, m in models.items():
            boot[k][b] = m(w)
        if (b + 1) % 200 == 0:
            print(f"  {b+1}/{B}  ({time.time()-t0:.0f}s)", flush=True)

    rows = []
    for (f, a), v in boot.items():
        lo, hi = np.percentile(v, [2.5, 97.5])
        rows.append(dict(family=f, arm=a, auc=point[(f, a)], ci_lo=lo, ci_hi=hi,
                         se=v.std(ddof=1)))
    cells = pd.DataFrame(rows)
    cells.to_csv(out_prefix + "_cells.csv", index=False)

    rows = []
    for lab, a0, a1 in CONTRASTS:
        for f in FAMS:
            if (f, a0) in boot and (f, a1) in boot:
                d = boot[(f, a1)] - boot[(f, a0)]
                lo, hi = np.percentile(d, [2.5, 97.5])
                rows.append(dict(contrast=lab, family=f,
                                 delta=point[(f, a1)] - point[(f, a0)],
                                 ci_lo=lo, ci_hi=hi, se=d.std(ddof=1),
                                 share_below_0=(d < 0).mean()))
    con = pd.DataFrame(rows)
    con.to_csv(out_prefix + "_contrasts.csv", index=False)
    np.savez_compressed(out_prefix + "_draws.npz",
                        **{f"{f}__{a}": v for (f, a), v in boot.items()})
    pd.set_option("display.float_format", lambda v: f"{v:.5f}")
    pd.set_option("display.width", 200)
    print(cells.to_string(index=False)); print(); print(con.to_string(index=False))


if __name__ == "__main__":
    a = sys.argv
    main(a[1], a[2], int(a[3]) if len(a) > 3 else 2000, int(a[4]) if len(a) > 4 else 20261010)
