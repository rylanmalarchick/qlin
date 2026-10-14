"""C6b analysis, as fixed in notes/c6b-prereg.txt before the run.

Run: uv run --project bench python bench/analyze_c6b.py results/phase7_c6b.json
"""

import json
import statistics as st
import sys

from scipy import stats

OUTLIER_US = 1000.0
MODEL_US = 19.22
KS = (1, 2, 4, 8)


def slope(points: list[tuple[int, float]]) -> float | None:
    if len({k for k, _ in points}) < 2:
        return None
    kb = st.mean(k for k, _ in points)
    vb = st.mean(v for _, v in points)
    return sum((k - kb) * (v - vb) for k, v in points) / sum((k - kb) ** 2 for k, _ in points)


def main(path: str) -> None:
    rows = {r["variant"]: r for r in json.load(open(path))}
    times = {(v, k): [t / 1000.0 for t in rows[f"{v}_x{k}"]["times"]]
             for v in ("source", "best_defer") for k in KS}
    rounds = min(len(ts) for ts in times.values())
    med = {cell: st.median(ts[:rounds]) for cell, ts in times.items()}
    dropped, gaps = 0, []
    for r in range(rounds):
        sl = {}
        for v in ("source", "best_defer"):
            pts = []
            for k in KS:
                t = times[(v, k)][r]
                if t - med[(v, k)] > OUTLIER_US:
                    dropped += 1
                else:
                    pts.append((k, t))
            sl[v] = slope(pts)
        if sl["source"] is not None and sl["best_defer"] is not None:
            gaps.append(sl["source"] - sl["best_defer"])
    m, se = st.mean(gaps), stats.sem(gaps)
    lo, hi = stats.t.interval(0.95, len(gaps) - 1, loc=m, scale=se)
    t19 = stats.ttest_1samp(gaps, MODEL_US)
    w = stats.wilcoxon(gaps)
    sw = stats.shapiro(gaps) if len(gaps) >= 3 else None
    verdict = ("model ranking confirmed (CI above 0)" if lo > 0
               else "model size rejected" if t19.pvalue < 0.05 else "not resolved")
    print(f"complete rounds {rounds}, rounds with both slopes {len(gaps)}, jobs dropped {dropped}")
    print(f"1. gap slope {m:.2f} us/copy, SE {se:.2f}, 95% CI {lo:.2f} to {hi:.2f}")
    print(f"2. t test against {MODEL_US}: t {t19.statistic:.2f}, p {t19.pvalue:.4f}")
    print(f"3. Wilcoxon against 0: p {w.pvalue:.4f}")
    if sw:
        print(f"Shapiro-Wilk: p {sw.pvalue:.4f}")
    print(f"verdict: {verdict}")


if __name__ == "__main__":
    main(sys.argv[1])
