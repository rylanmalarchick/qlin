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


def analyze(path: str) -> dict:
    """The fixed analysis of notes/c6b-prereg.txt, as numbers."""
    rows = {r["variant"]: r for r in json.load(open(path))}
    times = {(v, k): [t / 1000.0 for t in rows[f"{v}_x{k}"]["times"]]
             for v in ("source", "best_defer") for k in KS}
    rounds = min(len(ts) for ts in times.values())
    med = {cell: st.median(ts[:rounds]) for cell, ts in times.items()}
    dropped, gaps = [], []
    for r in range(rounds):
        sl = {}
        for v in ("source", "best_defer"):
            pts = []
            for k in KS:
                t = times[(v, k)][r]
                if t - med[(v, k)] > OUTLIER_US:
                    dropped.append((v, k, r))
                else:
                    pts.append((k, t))
            sl[v] = slope(pts)
        if sl["source"] is not None and sl["best_defer"] is not None:
            gaps.append(sl["source"] - sl["best_defer"])
    # Descriptive, not part of the fixed analysis: one least-squares slope per
    # variant over every kept job of the complete rounds.
    pooled = {v: slope([(k, times[(v, k)][r]) for k in KS for r in range(rounds)
                        if (v, k, r) not in dropped]) for v in ("source", "best_defer")}
    m, se = st.mean(gaps), stats.sem(gaps)
    lo, hi = stats.t.interval(0.95, len(gaps) - 1, loc=m, scale=se)
    t19 = stats.ttest_1samp(gaps, MODEL_US)
    w = stats.wilcoxon(gaps)
    sw = stats.shapiro(gaps) if len(gaps) >= 3 else None
    verdict = ("model ranking confirmed (CI above 0)" if lo > 0
               else "model size rejected" if t19.pvalue < 0.05 else "not resolved")
    return {"rounds": rounds, "both": len(gaps), "dropped": len(dropped),
            "dropped_jobs": dropped, "gaps": gaps, "pooled": pooled,
            "mean": m, "se": se, "lo": lo, "hi": hi, "t19_t": t19.statistic,
            "t19_p": t19.pvalue, "wilcoxon_p": w.pvalue,
            "sw_p": sw.pvalue if sw else None, "verdict": verdict}


def main(path: str) -> None:
    a = analyze(path)
    print(f"complete rounds {a['rounds']}, rounds with both slopes {a['both']}, "
          f"jobs dropped {a['dropped']}")
    print(f"1. gap slope {a['mean']:.2f} us/copy, SE {a['se']:.2f}, "
          f"95% CI {a['lo']:.2f} to {a['hi']:.2f}")
    print(f"2. t test against {MODEL_US}: t {a['t19_t']:.2f}, p {a['t19_p']:.4f}")
    print(f"3. Wilcoxon against 0: p {a['wilcoxon_p']:.4f}")
    if a["sw_p"] is not None:
        print(f"Shapiro-Wilk: p {a['sw_p']:.4f}")
    print(f"verdict: {a['verdict']}")


if __name__ == "__main__":
    main(sys.argv[1])
