"""Noise sensitivity of the fast-path gains.

Run: cargo build --release, then
     uv run --project bench python bench/run_phase8_noise.py

The `_noisy` benchmarks inject an X error on each data qubit with
probability p = 0.05 (benchmarks/SOURCES.txt): the noise qubit takes
ry(theta) with sin^2(theta / 2) = p. This run rewrites theta for each p of
PS and scores every variant as bench/run_phase8_switch.py does (same
baselines, same variants, same gain), at two points of its grid: no
controller time per branch, and the QICK cost with a decision tree. At
p = 0.05 the program text is unchanged, and the run stops if a row
differs from results/phase8_switch.csv. Writes results/phase8_noise.csv
and results/phase8_noise.md.
"""

from __future__ import annotations

import csv
import json
import math
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from qlin_qiskit import ROOT, qlin
from run_phase3 import GAIN_BAR, MAX_T, SIM_QUBITS
from run_phase3 import baseline_texts as small_baselines
from run_phase7_scale import baseline_texts as large_baselines
from run_phase8_switch import score

RESULTS = ROOT / "results"
PS = [0.001, 0.005, 0.01, 0.02, 0.05, 0.1]
P_SOURCE = 0.05
ANGLE = "0.4510268117962624"   # ry angle of the noise qubit in every _noisy benchmark
POINTS = [("none", 0.0, "table"), ("qick", 42.0, "tree")]
WORKERS = 6


def variant(path: Path, p: float, tmp: Path) -> Path:
    """The benchmark with error probability p, under the same file name."""
    text = path.read_text()
    if ANGLE not in text:
        raise ValueError(f"{path}: noise angle {ANGLE} not found")
    out = tmp / f"p{p}" / path.name
    out.parent.mkdir(parents=True, exist_ok=True)
    if p != P_SOURCE:
        text = text.replace(f"ry({ANGLE})", f"ry({2 * math.asin(math.sqrt(p))!r})")
    out.write_text(text)
    return out


def prepare(path: Path, p: float, tmp: Path) -> tuple:
    """The variant, its size, and its baseline programs (BQCP and Qiskit run
    in this process, so this step is not run in threads)."""
    bench = str(path.relative_to(ROOT / "benchmarks").with_suffix(""))
    var = variant(path, p, tmp)
    n = json.loads(qlin("json", str(var)))["n_qubits"]
    if n <= SIM_QUBITS:
        bases = small_baselines(var)
    else:
        bases = {k: text for k, (text, _) in large_baselines(var).items()}
    return var, bench, n, bases, p


def rows_for(job: tuple) -> list[dict]:
    var, bench, n, bases, p = job
    out = []
    for cls, tb, sw in POINTS:
        row = score(var, bench, n, bases, cls, tb, sw)
        fast = [row[f"fast_t{t}"] for t in range(0, min(row["m"], MAX_T) + 1)]
        row.update({"p": p, "gain_no_sink": (row["best_baseline"] - min(fast)) / row["best_baseline"],
                    "best_t_no_sink": fast.index(min(fast)),
                    "gain_t2": ((row["best_baseline"] - fast[2]) / row["best_baseline"]
                                if len(fast) > 2 else None)})
        out.append(row)
    print(bench, p, flush=True)
    return out


def check_source_rows(rows: list[dict]) -> None:
    """At p = 0.05 every row must equal its phase8_switch row."""
    with open(RESULTS / "phase8_switch.csv") as f:
        ref = {(r["benchmark"], r["class"], r["switch"]): r for r in csv.DictReader(f)}
    for r in rows:
        if r["p"] != P_SOURCE:
            continue
        want = ref[(r["benchmark"], r["class"], r["switch"])]
        for k in ("best_baseline", "best_ours", "gain"):
            if abs(float(want[k]) - r[k]) > 1e-9 * max(1.0, abs(r[k])):
                raise SystemExit(f"{r['benchmark']} {r['class']} {r['switch']} {k}: "
                                 f"{r[k]} differs from phase8_switch {want[k]}")


def main() -> int:
    RESULTS.mkdir(exist_ok=True)
    paths = sorted((ROOT / "benchmarks").rglob("*_noisy.qlin"))
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        jobs = [prepare(path, p, tmp) for path in paths for p in PS]
        with ThreadPoolExecutor(WORKERS) as pool:
            rows = [r for rs in pool.map(rows_for, jobs) for r in rs]
    check_source_rows(rows)
    _write(rows)
    return 0


def _write(rows: list[dict]) -> None:
    cols = ["benchmark", "qubits", "m", "p", "class", "tbranch", "switch", "best_baseline",
            "best_baseline_is", "best_ours", "best_ours_is", "gain", "gain_no_sink",
            "best_t_no_sink", "gain_t2"]
    with open(RESULTS / "phase8_noise.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    benches = sorted({r["benchmark"] for r in rows})
    lines = [
        "# Noise sensitivity of the fast-path gains",
        "",
        "Each `_noisy` benchmark with the error probability p of its data qubits",
        f"set to each value below (the benchmarks ship p = {P_SOURCE:g}). Model and",
        "variants as in results/phase8_switch.md: block sync, HERON_LIKE (assumed",
        "values), t_ff = 600 ns, exact outcome records. gain: best fast-path or",
        "sink variant against the best baseline (source, M0, best defer, BQCP,",
        "Qiskit O3). no sink: the best fast path alone, with its budget t.",
        "t = 2: the fast path alone at the fixed budget t = 2.",
        f"The p = {P_SOURCE:g} rows equal results/phase8_switch.csv (checked by the run).",
        f"{len(benches)} benchmarks.",
    ]
    for cls, tb, sw in POINTS:
        rs = {(r["benchmark"], r["p"]): r for r in rows if (r["class"], r["switch"]) == (cls, sw)}
        lines += ["", f"## {cls}, t_branch = {tb:g} ns, switch = {sw}", "",
                  "### Programs that gain at least " + f"{GAIN_BAR:.0%}", "",
                  "| p | " + " | ".join(f"{p:g}" for p in PS) + " |",
                  "|---|" + "---|" * len(PS),
                  "| programs | " + " | ".join(
                      str(sum(rs[(b, p)]["gain"] >= GAIN_BAR for b in benches)) for p in PS) + " |",
                  "", "### Gain (best variant); gain and budget t without the sink; gain at t = 2", "",
                  "| benchmark | m | " + " | ".join(f"p = {p:g}" for p in PS) + " |",
                  "|---|---|" + "---|" * len(PS)]
        for b in benches:
            cells = [f"{rs[(b, p)]['gain']:.1%}; {rs[(b, p)]['gain_no_sink']:.1%} "
                     f"(t={rs[(b, p)]['best_t_no_sink']}); "
                     + ("none" if rs[(b, p)]["gain_t2"] is None else f"{rs[(b, p)]['gain_t2']:.1%}")
                     for p in PS]
            lines.append(f"| {b} | {rs[(b, PS[0])]['m']} | " + " | ".join(cells) + " |")
    (RESULTS / "phase8_noise.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    sys.exit(main())
