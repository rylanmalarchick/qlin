"""Run the Phase 3 fast-path sweep and write the G3 table.

Run: cargo build --release, then
     uv run --project bench python bench/run_phase3.py

Model: block sync (HERON_LIKE, t_ff 600 ns), t_branch swept. For each
benchmark with at most 12 qubits, every variant is scored on its own exact
outcome records:
  ours      fast path (t = 0..min(m, 6)) with and without the Pauli sink
  baselines source, M0, best defer (Phase 2 search re-run in this model),
            bqcp and Qiskit O3 outputs (only where the Phase 1 guard matched)
The gain of a benchmark is (best baseline - best of ours) / best baseline.
"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

from qlin_qiskit import ROOT, bit_names, from_qiskit, load_qiskit, qlin, qlin_text
from run_baselines import bqcp, dist, qiskit_o3, same_distribution

RESULTS = ROOT / "results"
TBRANCH = [0.0, 200.0, 1000.0]
DECISION_TBRANCH = 0.0
MAX_T = 6
SIZE = 4096
SIM_QUBITS = 12
GAIN_BAR = 0.10


def model(tb: float) -> list[str]:
    return ["--model", "block", "--tff", "600", "--tbranch", str(tb)]


def baseline_texts(path: Path) -> dict[str, str | None]:
    """bqcp and Qiskit O3 outputs as .qlin, or None if they fail or differ."""
    circ, prog = load_qiskit(path)
    src = qlin("fmt", str(path))
    out: dict[str, str | None] = {}
    for name, run in (("bqcp", bqcp), ("qiskit_o3", qiskit_o3)):
        try:
            text = from_qiskit(run(circ.copy()), names=bit_names(circ))
        # A baseline pass can raise many exception types. The row records
        # the baseline as missing.
        except Exception:  # noqa: BLE001
            out[name] = None
            continue
        ok, _ = same_distribution(dist(src), dist(text))
        out[name] = text if ok else None
    return out


def main() -> int:
    RESULTS.mkdir(exist_ok=True)
    rows, skipped, g2 = [], [], {"rows": 0, "violations": 0, "mismatches": 0}
    checked = 0
    for path in sorted((ROOT / "benchmarks").rglob("*.qlin")):
        bench = str(path.relative_to(ROOT / "benchmarks").with_suffix(""))
        prog = json.loads(qlin("json", str(path)))
        if prog["n_qubits"] > SIM_QUBITS:
            skipped.append(f"{bench}: {prog['n_qubits']} qubits")
            continue
        noise = ["--noise-qubits", str(prog["n_qubits"] - 1)] if path.stem.endswith("_noisy") else []
        bases = baseline_texts(path)
        for tb in TBRANCH:
            m = model(tb)
            row = {"benchmark": bench, "tbranch": tb}
            probe = json.loads(qlin("fastpath", "--t", "0", *m, *noise, "--json", str(path)))
            row["source"] = probe["source"]["mean"]
            row["m0"] = probe["m0"]["mean"]
            row["m"] = probe["fastpath"]["group_bits"]
            opt = json.loads(qlin("opt", *m, *noise, "--json", str(path)))
            row["best_defer"] = opt["bnb"]["best"]["mean"]
            ex = opt["exhaustive"]
            if "skipped" not in ex:
                g2["rows"] += 1
                g2["violations"] += ex["bound_violations"]
                g2["mismatches"] += abs(ex["best"]["mean"] - opt["bnb"]["best"]["mean"]) > 1e-9
            for name, text in bases.items():
                row[name] = (json.loads(qlin_text(text, "lat", *m, *noise))["mean"]
                             if text is not None else None)
            best_ours, best_desc = None, ""
            for sink in (False, True):
                for t in range(0, min(row["m"], MAX_T) + 1):
                    flags = ["--sink"] if sink else []
                    # The program does not depend on t_branch: check it once.
                    if tb == TBRANCH[0]:
                        flags.append("--check")
                    r = json.loads(qlin("fastpath", "--t", str(t), "--size", str(SIZE), *flags,
                                        *m, *noise, "--json", str(path)))
                    checked += r["checked"]
                    key = f"{'sink_' if sink else ''}fast_t{t}"
                    row[key] = r["fast"]["mean"]
                    row[key + "_size"] = r["fastpath"]["size"]
                    row[key + "_exit"] = r["fastpath"]["exit_prob"]
                    if sink and t == 0:
                        row["sink_only"] = r["base"]["mean"]
                        row["sink_moved"] = r["sink_moved"]
                    if best_ours is None or r["fast"]["mean"] < best_ours:
                        best_ours, best_desc = r["fast"]["mean"], key
            if row.get("sink_only") is not None and row["sink_only"] < best_ours:
                best_ours, best_desc = row["sink_only"], "sink_only"
            baselines = {k: row[k] for k in ("source", "m0", "best_defer", "bqcp", "qiskit_o3")
                         if row.get(k) is not None}
            bname = min(baselines, key=baselines.get)
            row.update({
                "best_baseline": baselines[bname], "best_baseline_is": bname,
                "best_ours": best_ours, "best_ours_is": best_desc,
                "gain": (baselines[bname] - best_ours) / baselines[bname],
            })
            rows.append(row)
        print(bench, flush=True)
    g2["checked"] = checked
    _write(rows, skipped, g2)
    return 0


def _write(rows, skipped, g2) -> None:
    cols = sorted({k for r in rows for k in r}, key=lambda k: (k not in ("benchmark", "tbranch"), k))
    with open(RESULTS / "phase3.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    dec = [r for r in rows if r["tbranch"] == DECISION_TBRANCH]
    winners = [r for r in dec if r["gain"] >= GAIN_BAR]
    lines = [
        "# Phase 3 results",
        "",
        "Model: block sync, HERON_LIKE (assumed values), t_ff = 600 ns. Latency is",
        "expected makespan (ns) over exact outcome probabilities from |0...0>.",
        "",
        "## G3",
        "",
        f"- Phase 2 search under block sync: {g2['rows']} certified rows, "
        f"{g2['violations']} bound violations, {g2['mismatches']} B&B mismatches.",
        f"- Every fast-path and sink variant in this sweep passed the simulation check: "
        f"{g2['checked']} variants (a failure stops the run). Also tests/fastpath.rs and "
        "tests/sink.rs (full job).",
        f"- Pitch decision at t_branch = {DECISION_TBRANCH:g}: {len(winners)} benchmarks with gain "
        f">= {GAIN_BAR:.0%} against the best baseline "
        f"({'method + gain' if len(winners) >= 2 else 'method + bound + soundness'}).",
        "",
    ]
    for tb in TBRANCH:
        lines += [
            f"## t_branch = {tb:g} ns",
            "",
            "| benchmark | best baseline | which | best ours | which | gain |",
            "|---|---|---|---|---|---|",
        ]
        for r in rows:
            if r["tbranch"] == tb and r["gain"] > 1e-9:
                lines.append(
                    f"| {r['benchmark']} | {r['best_baseline']:.0f} | {r['best_baseline_is']} | "
                    f"{r['best_ours']:.0f} | {r['best_ours_is']} | {r['gain']:.1%} |")
        lines.append("")
        lines.append(f"Rows with no gain at this t_branch: "
                     f"{sum(1 for r in rows if r['tbranch'] == tb and r['gain'] <= 1e-9)}.")
        lines.append("")
    lines += ["## Skipped", ""] + [f"- {s}" for s in skipped]
    (RESULTS / "phase3.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    sys.exit(main())
