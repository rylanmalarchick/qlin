"""Run the Phase 2 defer search on every benchmark and write the G2 table.

Run: cargo build --release, then
     uv run --project bench python bench/run_phase2.py

For each benchmark with at most 12 qubits and each t_ff in the sweep,
`qlin opt --json` gives E[lat] for the source, the M0 normal form, the best
defer choice, and the floor (every candidate relaxed). At the preset t_ff,
every leaf that branch and bound scores is also checked by simulation.
"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

from qlin_qiskit import ROOT, qlin

RESULTS = ROOT / "results"
TFF = [0.0, 150.0, 600.0, 2400.0]
CHECK_TFF = 600.0
SIM_QUBITS = 12
EPS = 1e-9
COLS = [
    "benchmark", "tff", "status", "reason", "candidates", "records",
    "source", "m0", "best", "floor", "deferred", "added_2q", "added_qubits",
    "bnb_nodes", "bnb_leaves", "tree_nodes", "ex_leaves", "bound_violations",
    "bnb_matches", "pareto", "leaves_checked", "leaves_unchecked",
]


def run(path: Path, tff: float, noise: list[int]) -> dict:
    args = ["opt", "--json", "--tff", str(tff)]
    if noise:
        args += ["--noise-qubits", ",".join(map(str, noise))]
    if tff == CHECK_TFF:
        args.append("--check")
    return json.loads(qlin(*args, str(path)))


def main() -> int:
    RESULTS.mkdir(exist_ok=True)
    rows = []
    for path in sorted((ROOT / "benchmarks").rglob("*.qlin")):
        bench = str(path.relative_to(ROOT / "benchmarks").with_suffix(""))
        prog = json.loads(qlin("json", str(path)))
        if prog["n_qubits"] > SIM_QUBITS:
            rows.append({"benchmark": bench, "status": "skipped",
                         "reason": f"{prog['n_qubits']} qubits > {SIM_QUBITS}"})
            continue
        noise = [prog["n_qubits"] - 1] if path.stem.endswith("_noisy") else []
        for tff in TFF:
            r = run(path, tff, noise)
            k = r["candidates"]
            ex = r["exhaustive"]
            best = r["bnb"]["best"]
            row = {
                "benchmark": bench, "tff": tff, "status": "ok", "reason": "",
                "candidates": k, "records": r["records"],
                "source": r["source"]["mean"], "m0": r["m0"]["mean"],
                "best": best["mean"], "floor": r["floor"],
                "deferred": sum(best["defer"]), "added_2q": best["added_2q"],
                "added_qubits": best["added_qubits"],
                "bnb_nodes": r["bnb"]["nodes"], "bnb_leaves": r["bnb"]["leaves"],
                "tree_nodes": 2 ** (k + 1) - 1,
                "leaves_checked": r["leaves_checked"],
                "leaves_unchecked": r["leaves_unchecked"],
            }
            if "skipped" in ex:
                row.update({"reason": f"exhaustive skipped: {ex['skipped']}", "bnb_matches": "n/a"})
            else:
                row.update({
                    "ex_leaves": ex["leaves"], "bound_violations": ex["bound_violations"],
                    "bnb_matches": abs(ex["best"]["mean"] - best["mean"]) <= EPS,
                    "pareto": len(ex["pareto"]),
                })
            rows.append(row)
        print(bench, flush=True)
    with open(RESULTS / "phase2.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=COLS)
        w.writeheader()
        for r in rows:
            w.writerow({c: r.get(c, "") for c in COLS})
    _summary(rows)
    return 0


def _summary(rows: list[dict]) -> None:
    ok = [r for r in rows if r["status"] == "ok"]
    certified = [r for r in ok if r.get("bnb_matches") is not None and r.get("bnb_matches") != "n/a"]
    lines = [
        "# Phase 2 results",
        "",
        "Cost model HERON_LIKE (starting values, not measured), t_ff swept.",
        "Latencies are expected makespans in ns under the ideal-controller model,",
        "over exact outcome probabilities from |0...0>.",
        "",
        "## G2 counts",
        "",
        f"- benchmark x t_ff rows: {len(ok)}; skipped benchmarks: "
        f"{sum(r['status'] == 'skipped' for r in rows)}",
        f"- rows with exhaustive certification: {len(certified)}",
        f"- B&B optimum = exhaustive optimum: {sum(r['bnb_matches'] is True for r in certified)}"
        f" of {len(certified)}",
        f"- bound violations: {sum(int(r['bound_violations']) for r in certified)}",
        f"- search leaves checked by simulation (t_ff = {CHECK_TFF:g}, exhaustive and B&B): "
        f"{sum(r['leaves_checked'] for r in ok)} passed (a failure stops the run), "
        f"{sum(r['leaves_unchecked'] for r in ok)} over {SIM_QUBITS} qubits not checked",
        "- M0 normal form optimal among prefix applications: see tests/m0.rs",
        "",
        "## Rows with candidates",
        "",
        "| benchmark | t_ff | k | source | M0 | best | floor | deferred | +2q | +q | B&B nodes / tree |",
        "|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for r in ok:
        if r["candidates"] == 0:
            continue
        lines.append(
            f"| {r['benchmark']} | {r['tff']:g} | {r['candidates']} | {r['source']:.0f} | "
            f"{r['m0']:.0f} | {r['best']:.0f} | {r['floor']:.0f} | {r['deferred']} | "
            f"{r['added_2q']} | {r['added_qubits']} | {r['bnb_nodes']} / {r['tree_nodes']} |"
        )
    skipped = [r for r in rows if r["status"] == "skipped"]
    lines += ["", "## Skipped", ""] + [f"- {r['benchmark']}: {r['reason']}" for r in skipped]
    (RESULTS / "phase2.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    sys.exit(main())
