"""Paper figures (PDF), computed from results/.

Run: uv run --project bench python bench/paper_figures.py [OUT_DIR]
OUT_DIR defaults to paper/generated. Writes figures/*.pdf:
- fastpath.pdf: fast-path expected latency against the budget t,
  normalized to the source program, at t_branch = 0 and 1000 ns (phase3.csv).
- probe.pdf: IBM branch-cost probe, per-shot time against if_else
  blocks, with the least-squares fit and its 95% confidence band.
- pairs.pdf: the 27 paired IBM differences, source minus best defer,
  with the kept-pairs mean and CI and the modeled 19 us gap.
Colors: the validated categorical palette of the dataviz skill (slots 1-4),
with a distinct marker per series for grayscale print.
"""

from __future__ import annotations

import csv
import json
import os
import statistics as st
import sys
from pathlib import Path

import matplotlib

matplotlib.use("pdf")
import matplotlib.pyplot as plt  # noqa: E402
from scipy import stats  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
RESULTS = Path(os.environ.get("QLIN_RESULTS", ROOT / "results"))
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"]
MARKERS = ["o", "s", "^", "D"]
INK, MUTED, GRID = "#0b0b0b", "#52514e", "#dddcd7"
FAST = ["dynamarq/five_qubit_code", "dynamarq/repetition5_0_noisy",
        "dynamarq/repetition5_1_noisy", "dynamarq/repetition3_1_noisy"]
MODEL_GAP_US = 19.0  # modeled source - best_defer gap at t_branch 3.45 us (phase4_ibm_five_qubit.md)

plt.rcParams.update({
    "font.size": 8, "axes.labelsize": 8, "axes.titlesize": 8, "legend.fontsize": 7,
    "xtick.labelsize": 7, "ytick.labelsize": 7, "axes.edgecolor": MUTED,
    "axes.labelcolor": INK, "xtick.color": MUTED, "ytick.color": MUTED,
    "axes.spines.top": False, "axes.spines.right": False, "lines.linewidth": 1.5,
    "pdf.fonttype": 42,
})


def grid(ax) -> None:
    ax.grid(True, color=GRID, linewidth=0.5)
    ax.set_axisbelow(True)


def fastpath(out: Path) -> None:
    data = {(r["benchmark"], float(r["tbranch"])): r
            for r in csv.DictReader(open(RESULTS / "phase3.csv"))}
    fig, axes = plt.subplots(1, 2, figsize=(6.2, 2.3), sharey=True)
    for ax, tb in zip(axes, (0.0, 1000.0)):
        for i, b in enumerate(FAST):
            r = data[(b, tb)]
            pts = [(t, float(r[f"fast_t{t}"]) / float(r["source"]))
                   for t in range(7) if r.get(f"fast_t{t}")]
            ax.plot([t for t, _ in pts], [y for _, y in pts], color=SERIES[i],
                    marker=MARKERS[i], markersize=4, label=b.split("/")[1].replace("_", " "))
        ax.axhline(1.0, color=MUTED, linewidth=0.8, linestyle="--")
        ax.set_title(f"$t_\\mathrm{{branch}}$ = {tb:.0f} ns (modeled)", color=INK)
        ax.set_xlabel("budget $t$")
        grid(ax)
    axes[0].set_ylabel("latency / source")
    axes[1].legend(frameon=False, loc="center right")
    fig.tight_layout()
    fig.savefig(out / "fastpath.pdf")
    plt.close(fig)


def probe(out: Path) -> None:
    rows = [r for r in json.loads((RESULTS / "phase4_ibm.json").read_text())
            if r["benchmark"] == "branch_probe"]
    ks = [r["k"] for r in rows for _ in r["times"]]
    ys = [t / 1000 for r in rows for t in r["times"]]
    fit = stats.linregress(ks, ys)
    n, q = len(ks), stats.t.ppf(0.975, len(ks) - 2)
    kbar = st.mean(ks)
    sxx = sum((k - kbar) ** 2 for k in ks)
    s = (sum((y - fit.intercept - fit.slope * k) ** 2 for k, y in zip(ks, ys)) / (n - 2)) ** 0.5
    xs = [x / 10 for x in range(0, 81)]
    mid = [fit.intercept + fit.slope * x for x in xs]
    half = [q * s * (1 / n + (x - kbar) ** 2 / sxx) ** 0.5 for x in xs]
    fig, ax = plt.subplots(figsize=(3.2, 2.3))
    ax.fill_between(xs, [m - h for m, h in zip(mid, half)], [m + h for m, h in zip(mid, half)],
                    color=SERIES[0], alpha=0.18, linewidth=0, label="95% CI of the fit")
    ax.plot(xs, mid, color=SERIES[0], label=f"fit: {fit.slope:.2f} $\\mu$s per block")
    ax.plot(ks, ys, linestyle="none", marker="o", markersize=4, color=INK, label="job (1000 shots)")
    ax.set_xlabel("if_else blocks $k$")
    ax.set_ylabel("time per shot ($\\mu$s, measured)")
    ax.legend(frameon=False, loc="upper left")
    grid(ax)
    fig.tight_layout()
    fig.savefig(out / "probe.pdf")
    plt.close(fig)


def pairs(out: Path) -> None:
    n27 = {r["variant"]: [t / 1000 for t in r["times"]]
           for r in json.loads((RESULTS / "phase4_ibm_five_qubit_n27.json").read_text())}
    d = [a - b for a, b in zip(n27["source"], n27["best_defer"])]
    keep = [(i, x) for i, x in enumerate(d) if abs(x) < 1000]
    out_ = [(i, x) for i, x in enumerate(d) if abs(x) >= 1000]
    xs = [x for _, x in keep]
    m, se = st.mean(xs), st.stdev(xs) / len(xs) ** 0.5
    h = stats.t.ppf(0.975, len(xs) - 1) * se
    fig, ax = plt.subplots(figsize=(3.2, 2.3))
    ax.axhspan(m - h, m + h, color=SERIES[0], alpha=0.18, linewidth=0,
               label=f"mean of {len(xs)} kept, 95% CI")
    ax.axhline(m, color=SERIES[0])
    ax.axhline(MODEL_GAP_US, color=SERIES[1], linestyle="--", label="model: 19 $\\mu$s")
    ax.axhline(0, color=MUTED, linewidth=0.8)
    ax.plot([i + 1 for i, _ in keep], xs, linestyle="none", marker="o", markersize=4, color=INK,
            label="pair (1000 shots each)")
    top = 170
    for i, x in out_:
        ax.annotate(f"{x:.0f}", xy=(i + 1, top), xytext=(i + 1, top - 45), ha="center",
                    fontsize=6, color=MUTED, arrowprops={"arrowstyle": "->", "color": MUTED})
    ax.set_ylim(-180, top)
    ax.set_xlabel("round")
    ax.set_ylabel("source $-$ defer ($\\mu$s per shot)")
    ax.legend(frameon=False, loc="lower left", fontsize=6)
    grid(ax)
    fig.tight_layout()
    fig.savefig(out / "pairs.pdf")
    plt.close(fig)


def main(out: Path) -> None:
    fig_dir = out / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)
    fastpath(fig_dir)
    probe(fig_dir)
    pairs(fig_dir)
    print(f"wrote {fig_dir}/fastpath.pdf, probe.pdf, pairs.pdf")


if __name__ == "__main__":
    main(Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "paper" / "generated")
