"""
R4 (revision, reviewer 2 comment M3): confidence intervals that carry BOTH
sources of uncertainty for an AUC contrast:
  (a) test-sample uncertainty  -> sub-district (ADM3) clustered bootstrap of 2022;
  (b) training variability     -> repeated fits under different seeds
                                  (plus non-bitwise-reproducible GPU / threads).

For each replicate b one set of sub-district multiplicities is drawn and applied
to EVERY run and model, so differences are paired across arms and runs.
For a contrast (arm0 -> arm1) and family f:
  per run r : delta_r(b) = AUC_r(f, arm1; w_b) - AUC_r(f, arm0; w_b)
  pooled    : the R x B draws {delta_r(b)} are pooled, i.e. a run is drawn at
              random and then a test resample; the 2.5/97.5 percentiles of the
              pooled draws give a 95% interval that widens with seed spread.
Also reported: mean and SD of the point deltas across runs, min/max, and the
share of pooled draws below zero.

Only saved 2022 test scores are read. Nothing is fitted, tuned or selected.

Usage:
  python r4_seed_pooled_ci.py <keys_test.rds> <out_prefix> <B> label=dir [label=dir ...]
"""
import sys, os, time
import numpy as np
import pandas as pd
import pyreadr

ARMS = ["F", "F_EO", "F_SP", "F_SP_EO", "SPA", "EO_SPA"]
FAMS = ["LR", "RF", "XGB", "MLP", "STCRAAN"]
CONTRASTS = [
    ("EO given FIN+SP (F+SP -> F+SP+EO)", "F_SP", "F_SP_EO"),
    ("EO given FIN (F -> F+EO)", "F", "F_EO"),
    ("EO given SPA (SPA -> EO+SPA)", "SPA", "EO_SPA"),
]


class WeightedAUC:
    def __init__(self, score, y):
        _, self.gid = np.unique(score, return_inverse=True)
        self.G = self.gid.max() + 1
        self.y = y.astype(float)

    def __call__(self, w):
        pos = np.bincount(self.gid, weights=w * self.y, minlength=self.G)
        neg = np.bincount(self.gid, weights=w * (1 - self.y), minlength=self.G)
        return float((pos * (np.cumsum(neg) - 0.5 * neg)).sum() / (pos.sum() * neg.sum()))


def main(keys_path, out_prefix, B, runs, seed=20261010):
    keys = list(pyreadr.read_r(keys_path).values())[0]
    y = keys["y"].to_numpy().astype(int)
    _, cl = np.unique(keys["adm3"].to_numpy(), return_inverse=True)
    C = cl.max() + 1
    models = {}
    for lab, d in runs:
        for f in FAMS:
            for a in ARMS:
                p = os.path.join(d, f"pred_{f}__{a}.rds")
                if os.path.exists(p):
                    s = list(pyreadr.read_r(p).values())[0].iloc[:, 0].to_numpy(float)
                    assert len(s) == len(y), p
                    models[(lab, f, a)] = WeightedAUC(s, y)
    print(f"{len(models)} models from {len(runs)} runs; B = {B}", flush=True)
    ones = np.ones(len(y))
    point = {k: m(ones) for k, m in models.items()}
    draws = {k: np.empty(B) for k in models}
    rng = np.random.default_rng(seed); t0 = time.time()
    for b in range(B):
        w = np.bincount(rng.integers(0, C, C), minlength=C).astype(float)[cl]
        for k, m in models.items():
            draws[k][b] = m(w)
        if (b + 1) % 100 == 0:
            print(f"  {b+1}/{B} ({time.time()-t0:.0f}s)", flush=True)

    per_run, pooled = [], []
    for lab_c, a0, a1 in CONTRASTS:
        for f in FAMS:
            labs = [lab for lab, _ in runs if (lab, f, a0) in models and (lab, f, a1) in models]
            if not labs:
                continue
            allp, pts = [], []
            for lab in labs:
                d = draws[(lab, f, a1)] - draws[(lab, f, a0)]
                pt = point[(lab, f, a1)] - point[(lab, f, a0)]
                lo, hi = np.percentile(d, [2.5, 97.5])
                per_run.append(dict(contrast=lab_c, family=f, run=lab, delta=pt,
                                    ci_lo=lo, ci_hi=hi))
                allp.append(d); pts.append(pt)
            allp = np.concatenate(allp); pts = np.array(pts)
            lo, hi = np.percentile(allp, [2.5, 97.5])
            pooled.append(dict(contrast=lab_c, family=f, n_runs=len(labs),
                               mean_delta=pts.mean(),
                               sd_runs=pts.std(ddof=1) if len(pts) > 1 else np.nan,
                               min_delta=pts.min(), max_delta=pts.max(),
                               pooled_lo=lo, pooled_hi=hi,
                               share_below_0=(allp < 0).mean()))
    pr = pd.DataFrame(per_run); po = pd.DataFrame(pooled)
    pr.to_csv(out_prefix + "_per_run.csv", index=False)
    po.to_csv(out_prefix + "_pooled.csv", index=False)
    pd.set_option("display.float_format", lambda v: f"{v:.5f}"); pd.set_option("display.width", 220)
    print(pr.to_string(index=False)); print(); print(po.to_string(index=False))


if __name__ == "__main__":
    a = sys.argv
    runs = [tuple(x.split("=", 1)) for x in a[4:]]
    main(a[1], a[2], int(a[3]), runs)
