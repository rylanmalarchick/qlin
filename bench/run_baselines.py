"""Run every baseline on every benchmark and write the Phase 1 table.

Run: uv run --project bench python bench/run_baselines.py
Needs a release build of qlin (`cargo build --release`) and a bqcp clone
at $BQCP_PATH (default ~/dev/oss/bqcp).

Every pipeline output is converted back to .qlin, and `qlin stats` computes
its metrics, so one implementation measures every tool. For programs with
at most 12 qubits, `qlin sim` checks that the output distribution from
|0...0> matches the source.
"""

from __future__ import annotations

import csv
import json
import os
import sys
import time
from pathlib import Path

from qiskit import transpile

from qlin_qiskit import ROOT, Unsupported, bit_names, from_qiskit, load_qiskit, qlin, qlin_text

sys.path.insert(0, str(Path(os.environ.get("BQCP_PATH", Path.home() / "dev/oss/bqcp")) / "src"))
from ConstantPropagation import ConstantPropagation  # noqa: E402

from pytket.extensions.qiskit import qiskit_to_tk, tk_to_qiskit  # noqa: E402
from pytket.passes import FullPeepholeOptimise  # noqa: E402

RESULTS = ROOT / "results"
BASIS = ["rz", "sx", "x", "cx"]
SIM_QUBITS = 12
# Distribution values are sums of branch probabilities, so they are exact
# up to float rounding. The guard also allows the mass of loop runs that
# hit max_iters, where the two programs may stop at different points.
GUARD_TOL = 1e-9
METRICS = [
    "qubits", "measurements", "gates", "gates_2q", "dynamic_ops",
    "feedforward", "core_branch", "core_loop", "movable", "dead",
]


def bqcp(circ):
    return ConstantPropagation.optimize(circ, max_amplitudes=512, max_branches=4)


def qiskit_o0(circ):
    return transpile(circ, basis_gates=BASIS, optimization_level=0, seed_transpiler=0)


def qiskit_o3(circ):
    return transpile(circ, basis_gates=BASIS, optimization_level=3, seed_transpiler=0)


def tket(circ):
    tk = qiskit_to_tk(circ)
    FullPeepholeOptimise(allow_swaps=False).apply(tk)
    return tk_to_qiskit(tk)


PIPELINES = [("bqcp", bqcp), ("qiskit_o0", qiskit_o0), ("qiskit_o3", qiskit_o3), ("tket", tket)]


def dist(text: str) -> dict:
    return json.loads(qlin_text(text, "sim"))


def same_distribution(a: dict, b: dict) -> tuple[bool, float]:
    keys = set(a["dist"]) | set(b["dist"])
    worst = max(abs(a["dist"].get(k, 0.0) - b["dist"].get(k, 0.0)) for k in keys)
    allowed = GUARD_TOL + a["truncated_prob"] + b["truncated_prob"]
    return worst <= allowed, worst


def main() -> int:
    RESULTS.mkdir(exist_ok=True)
    files = sorted((ROOT / "benchmarks").rglob("*.qlin"))
    rows = []
    mismatches = []
    for path in files:
        bench = str(path.relative_to(ROOT / "benchmarks").with_suffix(""))
        circ, prog = load_qiskit(path)
        loop_max = _loop_max(prog["body"]) or 8
        source = qlin("fmt", str(path))
        small = prog["n_qubits"] <= SIM_QUBITS
        src_dist = dist(source) if small else None
        rows.append(_row(bench, "source", source, "", 0.0, "reference" if small else "too many qubits"))
        for name, run in PIPELINES:
            start = time.perf_counter()
            try:
                text = from_qiskit(run(circ.copy()), loop_max=loop_max, names=bit_names(circ))
                reason = ""
            except Unsupported as e:
                text, reason = None, f"bridge: {e}"
            # Third-party passes and converters raise many exception types.
            # Each failure is recorded in the table with its message, not hidden.
            except Exception as e:  # noqa: BLE001
                text, reason = None, f"{type(e).__name__}: {str(e).splitlines()[0][:120] if str(e) else ''}"
            seconds = time.perf_counter() - start
            guard = "too many qubits"
            if text is not None and small:
                ok, worst = same_distribution(src_dist, dist(text))
                guard = "match" if ok else f"MISMATCH (max diff {worst:.3g})"
                if not ok:
                    mismatches.append(f"{bench} / {name}")
            rows.append(_row(bench, name, text, reason, seconds, guard if text else ""))
        print(bench, flush=True)
    _write(rows, mismatches)
    print(f"{len(files)} benchmarks, {len(rows)} rows, {len(mismatches)} mismatches")
    return 0


def _row(bench, pipeline, text, reason, seconds, guard) -> dict:
    r = {"benchmark": bench, "pipeline": pipeline, "status": "ok" if text is not None else "n/a",
         "reason": reason, "guard": guard, "seconds": f"{seconds:.3f}"}
    if text is not None:
        s = json.loads(qlin_text(text, "stats", "--json"))
        r.update({k: s[k] for k in METRICS})
    return r


def _loop_max(block) -> int:
    for op in block:
        (kind, a), = op.items()
        if kind == "Loop":
            return a["max_iters"]
        for key in ("then_", "else_", "body"):
            if key in a and (inner := _loop_max(a[key])):
                return inner
    return 0


def _write(rows, mismatches) -> None:
    cols = ["benchmark", "pipeline", "status", *METRICS, "guard", "seconds", "reason"]
    with open(RESULTS / "phase1.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for r in rows:
            w.writerow({c: r.get(c, "") for c in cols})
    short = {"measurements": "m", "gates_2q": "2q", "dynamic_ops": "dyn", "feedforward": "ff",
             "core_branch": "core_b", "core_loop": "core_l", "movable": "mov"}
    shown = ["benchmark", "pipeline", *METRICS, "guard"]
    lines = ["| " + " | ".join(short.get(c, c) for c in shown) + " |",
             "|" + "---|" * len(shown)]
    for r in rows:
        if r["status"] == "ok":
            cells = [str(r.get(c, "")) for c in shown]
        else:
            cells = [r["benchmark"], r["pipeline"], f"n/a: {r['reason']}"] + [""] * (len(shown) - 3)
        lines.append("| " + " | ".join(cells) + " |")
    (RESULTS / "phase1_table.md").write_text("\n".join(lines) + "\n")
    (RESULTS / "phase1_mismatches.txt").write_text("\n".join(mismatches) + ("\n" if mismatches else ""))


if __name__ == "__main__":
    sys.exit(main())
