"""C6 analysis, as fixed in notes/c6-prereg.txt before the run.

Run: uv run --project bench python bench/analyze_c6.py results/phase4_ibm_five_qubit_n60.json
Prints the primary analysis on this run's pairs, then the pooled result
with the 2026-09-29 run (secondary). Times are per shot, in us.
"""

import json
import sys

from scipy import stats

OUTLIER_US = 1000.0  # drop a pair when |d| exceeds this (fixed before the run)
MODEL_US = 19.0      # block model at the measured branch cost


def pairs(path: str) -> list[float]:
    rows = {r["variant"]: r for r in json.load(open(path)) if r["benchmark"].endswith("five_qubit_code.qlin")}
    src, dfr = rows["source"]["times"], rows["best_defer"]["times"]
    n = min(len(src), len(dfr))  # complete rounds only
    return [(src[i] - dfr[i]) / 1000.0 for i in range(n)]


def report(name: str, d: list[float]) -> None:
    kept = [x for x in d if abs(x) <= OUTLIER_US]
    m = stats.tmean(kept)
    se = stats.sem(kept)
    lo, hi = stats.t.interval(0.95, len(kept) - 1, loc=m, scale=se)
    t19 = stats.ttest_1samp(kept, MODEL_US)
    w = stats.wilcoxon(d)
    sw = stats.shapiro(kept)
    if lo > 0:
        verdict = "model ranking confirmed (CI above 0)"
    elif t19.pvalue < 0.05:
        verdict = "model size rejected (t test against 19 us, p < 0.05)"
    else:
        verdict = "not resolved"
    print(f"== {name}")
    print(f"pairs {len(d)}, dropped by |d| > {OUTLIER_US:.0f} us: {len(d) - len(kept)}")
    print(f"1. mean {m:.2f} us, SE {se:.2f}, 95% CI {lo:.2f} to {hi:.2f}")
    print(f"2. t test against {MODEL_US} us: t {t19.statistic:.2f}, p {t19.pvalue:.4f}")
    print(f"3. Wilcoxon all pairs against 0: median {stats.scoreatpercentile(d, 50):.2f} us, p {w.pvalue:.4f}")
    print(f"Shapiro-Wilk on kept: p {sw.pvalue:.4f}")
    print(f"verdict: {verdict}")


if __name__ == "__main__":
    new = pairs(sys.argv[1])
    report("primary: this run", new)
    old = pairs("results/phase4_ibm_five_qubit_n27.json")
    report("secondary: pooled with the 2026-09-29 run", old + new)
