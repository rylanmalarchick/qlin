"""Controller cycles of the fast-path dispatch on the QubiC distributed
processor (RTL simulation of one core, no qubits).

Run: cargo build --release, then
     uv run --project bench python bench/run_qubic.py
Needs a clone of gitlab.com/LBL-QubiC/distributed_processor at QUBIC_PATH
(default ~/dev/oss/qubic-distproc) with a venv at QUBIC_PATH/.venv
(cocotb, distproc), and Verilator on PATH.

For each benchmark and budget t, the first dispatch group of `qlin
fastpath` becomes three programs (bench/qubic_dispatch.py): the source ifs,
the switch as a compare chain, and the switch as a binary search tree. The
testbench bench/qubic/dispatch_qlin_tb.py counts clock cycles from the
arrival of the syndrome to the end of the group, for every syndrome value.
The expected cycles weight each value by its exact probability from `qlin
records`. A least-squares fit over every (program, value) gives the cycles
of each instruction kind. Writes results/qubic_dispatch.json and .md.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

import qubic_dispatch as qd
from qlin_qiskit import ROOT, qlin

RESULTS = ROOT / "results"
QUBIC = Path(os.environ.get("QUBIC_PATH", Path.home() / "dev/oss/qubic-distproc"))
TB = ROOT / "bench" / "qubic"
NS_PER_CYCLE = 2.0   # QubiC 2.0 processor clock, 500 MHz (arXiv:2309.10333)
VARIANTS = ["source", "chain", "tree"]
KINDS = ["cond_taken", "cond_not", "jump", "mark"]
# (benchmark, noise qubit): decoders with one dispatch group on the syndrome.
BENCHES = [
    ("dynamarq/repetition3_1_noisy", 5),
    ("dynamarq/repetition5_0_noisy", 9),
    ("dynamarq/repetition5_1_noisy", 9),
    ("dynamarq/five_qubit_code_noisy", 11),
]
BUDGETS = [1, 2]


def group(path: Path, t: int, noise: int) -> qd.Group:
    text = qlin("fastpath", "--t", str(t), "--noise-qubits", str(noise), str(path))
    with tempfile.NamedTemporaryFile("w", suffix=".qlin") as f:
        f.write(text)
        f.flush()
        return qd.group_of(json.loads(qlin("json", f.name)))


def syndrome_probs(path: Path, bits: list[int]) -> dict[int, float]:
    """P(s) over the group bits, from the exact outcome records."""
    probs: dict[int, float] = {}
    for r in json.loads(qlin("records", str(path))):
        outs = [r["outcomes"][str(b)] for b in bits]
        if any(len(o) != 1 for o in outs):
            raise ValueError(f"{path}: a group bit is measured more than once")
        s = sum(int(o[0]) << i for i, o in enumerate(outs))
        probs[s] = probs.get(s, 0.0) + r["prob"]
    return probs


def simulate(progs: list[dict]) -> dict[tuple[str, int], int]:
    with tempfile.TemporaryDirectory() as d:
        fin, fout = Path(d) / "in.json", Path(d) / "out.json"
        fin.write_text(json.dumps(progs))
        env = dict(os.environ, QLIN_DISPATCH_IN=str(fin), QLIN_DISPATCH_OUT=str(fout),
                   QUBIC_PATH=str(QUBIC), PATH=f"{QUBIC / '.venv' / 'bin'}:{os.environ['PATH']}")
        # `uv run` points VIRTUAL_ENV at the bench venv; cocotb must use QubiC's.
        env.pop("VIRTUAL_ENV", None)
        r = subprocess.run(["make", "-s"], cwd=TB, env=env, capture_output=True, text=True)
        if r.returncode != 0 or not fout.exists():
            raise SystemExit(f"cocotb run failed:\n{r.stdout[-3000:]}\n{r.stderr[-3000:]}")
        return {(r["key"], r["s"]): r["cycles"] for r in json.loads(fout.read_text())}


def main() -> int:
    RESULTS.mkdir(exist_ok=True)
    rows, progs = [], []
    for bench, noise in BENCHES:
        path = ROOT / "benchmarks" / f"{bench}.qlin"
        for t in BUDGETS:
            g = group(path, t, noise)
            probs = syndrome_probs(path, g.bits)
            values = list(range(1 << len(g.bits)))
            for v in VARIANTS:
                code = qd.program(g, v)
                for s in values:
                    if qd.run(code, s)[0] != qd.selected(g, s):
                        raise SystemExit(f"{bench} t={t} {v} s={s}: wrong arms")
                key = f"{bench}|{t}|{v}"
                progs.append({"key": key, "code": [list(i) for i in code], "values": values})
                rows.append({"benchmark": bench, "t": t, "variant": v, "bits": len(g.bits),
                             "cases": len(g.cases), "ifs": len(g.ifs), "code": code,
                             "probs": probs, "values": values})
    cyc = simulate(progs)
    points, out = [], []
    for r in rows:
        key = f"{r['benchmark']}|{r['t']}|{r['variant']}"
        per = []
        for s in r["values"]:
            _, counts = qd.trace(r["code"], s)
            per.append({"s": s, "p": r["probs"].get(s, 0.0), "cycles": cyc[(key, s)], **counts})
            points.append(([counts[k] for k in KINDS] + [1], cyc[(key, s)]))
        e_cyc = sum(x["p"] * x["cycles"] for x in per)
        e_dec = sum(x["p"] * (x["cond_taken"] + x["cond_not"]) for x in per)
        out.append({k: r[k] for k in ("benchmark", "t", "variant", "bits", "cases", "ifs")}
                   | {"expected_cycles": e_cyc, "expected_decisions": e_dec,
                      "worst_cycles": max(x["cycles"] for x in per), "per_value": per})
    a = np.array([p[0] for p in points], dtype=float)
    y = np.array([p[1] for p in points], dtype=float)
    coef, *_ = np.linalg.lstsq(a, y, rcond=None)
    resid = y - a @ coef
    fit = {"cycles_per": dict(zip(KINDS + ["base"], coef.tolist())),
           "max_abs_residual": float(np.max(np.abs(resid))), "points": len(y)}
    (RESULTS / "qubic_dispatch.json").write_text(json.dumps({"fit": fit, "rows": out}, indent=1))
    _write_md(out, fit)
    return 0


def _write_md(out: list[dict], fit: dict) -> None:
    lines = [
        "# QubiC dispatch cycles (RTL simulation, one core, no qubits)",
        "",
        "QubiC distributed processor, Verilator. Cycles from the arrival of the",
        "syndrome (function-processor read) to the end of the dispatch group,",
        f"for every syndrome value; {NS_PER_CYCLE:g} ns per cycle at 500 MHz.",
        "Expected values weight each syndrome by its exact probability (qlin",
        "records). source: the group's ifs; chain, tree: the fast-path switch.",
        "",
        "## Cycles per instruction kind (least squares over every program and value)",
        "",
        "| kind | cycles |",
        "|---|---|",
    ] + [f"| {k} | {v:.3f} |" for k, v in fit["cycles_per"].items()] + [
        "",
        f"{fit['points']} points, largest absolute residual {fit['max_abs_residual']:.3f} cycles.",
        "",
        "## Expected and worst-case cycles",
        "",
        "| benchmark | t | bits | cases | variant | expected cycles | expected ns | expected decisions | worst cycles |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for r in out:
        lines.append(f"| {r['benchmark']} | {r['t']} | {r['bits']} | {r['cases']} | {r['variant']} | "
                     f"{r['expected_cycles']:.2f} | {NS_PER_CYCLE * r['expected_cycles']:.1f} | "
                     f"{r['expected_decisions']:.2f} | {r['worst_cycles']} |")
    (RESULTS / "qubic_dispatch.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    sys.exit(main())
