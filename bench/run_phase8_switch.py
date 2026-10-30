"""Phase 8.1: the fast-path sweep under three switch costs and sourced t_branch.

Run: cargo build --release, then
     uv run --project bench python bench/run_phase8_switch.py

Same variants, baselines, and gain as bench/run_phase3.py (up to 12
qubits, baselines guarded by the output distribution) and
bench/run_phase7_scale.py (past 12 qubits, baselines guarded by `qlin
check`). Model: block sync, HERON_LIKE, t_ff 600 ns. Grid: t_branch 0
(where the switch cost has no effect), then each T_BRANCH line of
notes/cost-sources.txt under --switch-cost table, tree, and chain. The
fast-path and sink programs do not depend on the cost model, and the
phase 3 and phase 7 runs checked every one of them, so this run only
scores them. Writes results/phase8_switch.csv and results/phase8_switch.md.
"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

from qlin_qiskit import ROOT, qlin, qlin_text
from run_phase3 import GAIN_BAR, MAX_T, SIM_QUBITS, SIZE
from run_phase3 import baseline_texts as small_baselines
from run_phase7_scale import baseline_texts as large_baselines

RESULTS = ROOT / "results"
SWITCH = ["table", "tree", "chain"]


def t_branch_classes() -> dict[str, float]:
    """name -> t_branch (ns), from the T_BRANCH lines of notes/cost-sources.txt."""
    out = {}
    for line in (ROOT / "notes" / "cost-sources.txt").read_text().splitlines():
        if line.startswith("T_BRANCH."):
            key, rest = line.split(" = ", 1)
            out[key.removeprefix("T_BRANCH.")] = float(rest.split(" | ")[0])
    return out


def grid() -> list[tuple[str, float, str]]:
    """(class, t_branch, switch cost) points, t_branch 0 once."""
    classes = sorted(t_branch_classes().items(), key=lambda kv: kv[1])
    return [("none", 0.0, "table")] + [(c, tb, sw) for c, tb in classes for sw in SWITCH]


def score(path: Path, bench: str, n_qubits: int, bases: dict[str, str | None],
          cls: str, tb: float, sw: str) -> dict:
    noise = ["--noise-qubits", str(n_qubits - 1)] if path.stem.endswith("_noisy") else []
    m = ["--model", "block", "--tff", "600", "--tbranch", str(tb), "--switch-cost", sw]
    row = {"benchmark": bench, "qubits": n_qubits, "class": cls, "tbranch": tb, "switch": sw}
    probe = json.loads(qlin("fastpath", "--t", "0", *m, *noise, "--json", str(path)))
    row["source"] = probe["source"]["mean"]
    row["m0"] = probe["m0"]["mean"]
    row["m"] = probe["fastpath"]["group_bits"]
    row["best_defer"] = json.loads(qlin("opt", *m, *noise, "--json", str(path)))["bnb"]["best"]["mean"]
    for name, text in bases.items():
        row[name] = json.loads(qlin_text(text, "lat", *m, *noise))["mean"] if text else None
    best_ours, best_desc = None, ""
    for sink in (False, True):
        for t in range(0, min(row["m"], MAX_T) + 1):
            flags = ["--sink"] if sink else []
            r = json.loads(qlin("fastpath", "--t", str(t), "--size", str(SIZE), *flags,
                                *m, *noise, "--json", str(path)))
            key = f"{'sink_' if sink else ''}fast_t{t}"
            row[key] = r["fast"]["mean"]
            if sink and t == 0:
                row["sink_only"] = r["base"]["mean"]
            if best_ours is None or r["fast"]["mean"] < best_ours:
                best_ours, best_desc = r["fast"]["mean"], key
    if row.get("sink_only") is not None and row["sink_only"] < best_ours:
        best_ours, best_desc = row["sink_only"], "sink_only"
    baselines = {k: row[k] for k in ("source", "m0", "best_defer", "bqcp", "qiskit_o3")
                 if row.get(k) is not None}
    bname = min(baselines, key=baselines.get)
    row.update({"best_baseline": baselines[bname], "best_baseline_is": bname,
                "best_ours": best_ours, "best_ours_is": best_desc,
                "gain": (baselines[bname] - best_ours) / baselines[bname]})
    return row


def main() -> int:
    RESULTS.mkdir(exist_ok=True)
    rows, skipped = [], []
    points = grid()
    for path in sorted((ROOT / "benchmarks").rglob("*.qlin")):
        bench = str(path.relative_to(ROOT / "benchmarks").with_suffix(""))
        n = json.loads(qlin("json", str(path)))["n_qubits"]
        if n <= SIM_QUBITS:
            bases = small_baselines(path)
        else:
            noise = ["--noise-qubits", str(n - 1)] if path.stem.endswith("_noisy") else []
            try:
                qlin("lat", *noise, str(path))
            except RuntimeError as e:
                skipped.append(f"{bench}: {e}")
                continue
            bases = {k: text for k, (text, _) in large_baselines(path).items()}
        for cls, tb, sw in points:
            rows.append(score(path, bench, n, bases, cls, tb, sw))
        print(bench, flush=True)
    _write(rows, skipped, points)
    return 0


def _write(rows, skipped, points) -> None:
    cols = sorted({k for r in rows for k in r},
                  key=lambda k: (k not in ("benchmark", "class", "tbranch", "switch"), k))
    with open(RESULTS / "phase8_switch.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    benches = sorted({r["benchmark"] for r in rows})
    lines = [
        "# Phase 8.1 results: switch cost and sourced t_branch",
        "",
        "Model: block sync, HERON_LIKE (assumed values), t_ff = 600 ns. Latency is",
        "expected makespan (ns) over exact outcome probabilities from |0...0>",
        "(dense up to 12 qubits, stabilizer past that). t_branch classes come",
        "from notes/cost-sources.txt. Switch cost: table = 1 decision per",
        "switch, tree = 1 per switch bit, chain = 1 per compare.",
        f"{len(benches)} benchmarks.",
        "",
        "## Summary",
        "",
        f"| class | t_branch (ns) | switch | gain > 0 | gain >= {GAIN_BAR:.0%} | largest gain |",
        "|---|---|---|---|---|---|",
    ]
    for cls, tb, sw in points:
        rs = [r for r in rows if (r["class"], r["switch"]) == (cls, sw)]
        top = max(rs, key=lambda r: r["gain"])
        lines.append(f"| {cls} | {tb:g} | {sw} | {sum(r['gain'] > 1e-9 for r in rs)} | "
                     f"{sum(r['gain'] >= GAIN_BAR for r in rs)} | "
                     f"{top['gain']:.1%} ({top['benchmark']}) |")
    lines.append("")
    for cls, tb, sw in points:
        lines += [f"## {cls}, t_branch = {tb:g} ns, switch = {sw}", "",
                  "| benchmark | qubits | best baseline | which | best ours | which | gain |",
                  "|---|---|---|---|---|---|---|"]
        for r in rows:
            if (r["class"], r["switch"]) == (cls, sw) and r["gain"] > 1e-9:
                lines.append(f"| {r['benchmark']} | {r['qubits']} | {r['best_baseline']:.0f} | "
                             f"{r['best_baseline_is']} | {r['best_ours']:.0f} | "
                             f"{r['best_ours_is']} | {r['gain']:.1%} |")
        lines.append("")
    lines += ["## Skipped", ""] + [f"- {s}" for s in skipped]
    (RESULTS / "phase8_switch.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    sys.exit(main())
