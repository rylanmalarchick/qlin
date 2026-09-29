"""Phase 4 sensitivity: which Phase 2 and 3 conclusions hold over the
sourced parameter ranges.

Run: cargo build --release, then
     uv run --project bench python bench/run_phase4_sensitivity.py

Base preset HERON_KINGSTON (notes/cost-sources.txt). Grid:
  t_meas   1760, 2280 ns (FakeKingston snapshot: measure_2, measure),
           3000, 4000 ns (arXiv:2504.07258, Heron measure + reset range)
  t_ff     224 ns (Quantum Machines OPX+, vendor page), 600 ns
           (arXiv:2604.03360), 700 ns (arXiv:2605.22433, "under 700 ns")
  t_branch 0, 200, 1000 ns (assumed: no source)
Conclusions per benchmark:
  D  defer wins: best defer < M0 (Ideal model)
  F  fast path gain >= 10%: best of fast path / sink variants against the
     best of {source, M0, best defer} (Block model), per t_branch
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from qlin_qiskit import ROOT, qlin

RESULTS = ROOT / "results"
TMEAS = [1760, 2280, 3000, 4000]
TFF = [224, 600, 700]
TBRANCH = [0, 200, 1000]
SIM_QUBITS = 12
EPS = 1e-9
BAR = 0.10


def ours(scores: dict) -> float:
    keys = [k for k in scores if k.startswith(("fast_t", "sink_fast_t")) or k == "sink_only"]
    return min(scores[k] for k in keys)


def main() -> int:
    RESULTS.mkdir(exist_ok=True)
    rows, skipped = [], []
    for path in sorted((ROOT / "benchmarks").rglob("*.qlin")):
        bench = str(path.relative_to(ROOT / "benchmarks").with_suffix(""))
        prog = json.loads(qlin("json", str(path)))
        if prog["n_qubits"] > SIM_QUBITS:
            skipped.append(f"{bench}: {prog['n_qubits']} qubits")
            continue
        noise = ["--noise-qubits", str(prog["n_qubits"] - 1)] if path.stem.endswith("_noisy") else []
        d = json.loads(qlin("sweep", "--preset", "heron_kingston",
                            "--tmeas-list", ",".join(map(str, TMEAS)),
                            "--tff-list", ",".join(map(str, TFF)),
                            "--tbranch-list", ",".join(map(str, TBRANCH)),
                            *noise, str(path)))
        row = {"benchmark": bench, "candidates": d["candidates"], "group_bits": d["group_bits"]}
        # D: Ideal model ignores t_branch, so use the t_branch = 0 points.
        ideal = [p for p in d["points"] if p["sync"] == "Ideal" and p["t_branch"] == 0]
        wins = [p for p in ideal if p["scores"]["best_defer"] < p["scores"]["m0"] - EPS]
        row["D_holds"] = f"{len(wins)}/{len(ideal)}"
        row["D_where"] = sorted({(p["t_meas"], p["t_ff"]) for p in wins})
        gains = {}
        for tb in TBRANCH:
            pts = [p for p in d["points"] if p["sync"] == "Block" and p["t_branch"] == tb]
            g = []
            for p in pts:
                s = p["scores"]
                base = min(s["source"], s["m0"], s["best_defer"])
                g.append((base - ours(s)) / base)
            gains[tb] = (min(g), max(g))
            row[f"F_tb{tb}"] = f"{sum(x >= BAR for x in g)}/{len(g)}"
        row["gain_range"] = gains
        rows.append(row)
        print(bench, flush=True)
    (RESULTS / "phase4_sensitivity.json").write_text(json.dumps(rows, indent=1))
    _write(rows, skipped)
    return 0


def _write(rows, skipped) -> None:
    n_pts = len(TMEAS) * len(TFF)
    lines = [
        "# Phase 4 sensitivity",
        "",
        "Base preset HERON_KINGSTON. Grid (sources in bench/run_phase4_sensitivity.py and",
        f"notes/cost-sources.txt): t_meas {TMEAS} ns, t_ff {TFF} ns, t_branch {TBRANCH} ns",
        "(t_branch assumed). All numbers modeled.",
        "",
        f"D = defer beats M0 (Ideal model), counted over the {n_pts} (t_meas, t_ff) points.",
        f"F = fast path or sink gains >= {BAR:.0%} over the best of source, M0, best defer",
        f"(Block model), counted over the {n_pts} points, per t_branch.",
        "",
        "| benchmark | k | m | D | F tb=0 | F tb=200 | F tb=1000 | gain range tb=0 | gain range tb=1000 |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for r in rows:
        if r["candidates"] == 0 and r["group_bits"] == 0:
            continue
        g0, g1 = r["gain_range"][0], r["gain_range"][1000]
        lines.append(
            f"| {r['benchmark']} | {r['candidates']} | {r['group_bits']} | {r['D_holds']} | "
            f"{r['F_tb0']} | {r['F_tb200']} | {r['F_tb1000']} | "
            f"{g0[0]:+.1%} .. {g0[1]:+.1%} | {g1[0]:+.1%} .. {g1[1]:+.1%} |")
    none = [r["benchmark"] for r in rows if r["candidates"] == 0 and r["group_bits"] == 0]
    lines += ["", f"No candidates and no dispatch groups (not shown): {len(none)} benchmarks.",
              "", "## Skipped", ""] + [f"- {s}" for s in skipped]
    (RESULTS / "phase4_sensitivity.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    sys.exit(main())
