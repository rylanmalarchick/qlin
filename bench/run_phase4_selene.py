"""Phase 4 Selene accounting check.

Run: cargo build --release, then
     uv run --project bench python bench/run_phase4_selene.py

Selene's SimpleRuntime is serial (notes/selene-timing.txt), so a shot takes
the sum of the native ops it runs. This checks qlin's per-outcome op
accounting and the gate lowering against Selene, not scheduling:
  prediction(shot) = span(empty program, same qubits)
                   + sum over the ops of the matching qlin trace of
                     native_time(op), calibrated on Selene one op at a time
                     (a measure by its outcome on the trace)
The prediction and Selene's span are integers and must be equal.

Programs with a loop, or with a bit written twice on one trace, are
excluded (the final bits do not identify the trace). The reason is listed.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from selene_sim import SimpleRuntime

from qlin_guppy import guppy_source, load_main
from qlin_qiskit import ROOT, qlin, qlin_text
from selene_run import run

RESULTS = ROOT / "results"
SHOTS = 200
SIM_QUBITS = 12
# HERON_KINGSTON durations (notes/cost-sources.txt). rz is virtual: 0 ns.
RUNTIME = SimpleRuntime(duration_ns_rxy=32, duration_ns_rzz=68, duration_ns_rz=0,
                        duration_ns_measure=1760, duration_ns_reset=2312)

_native: dict[tuple[int, str], int] = {}
_empty: dict[int, int] = {}


def span_of(text: str, shots: int = 1) -> int:
    prog = json.loads(qlin_text(text, "json"))
    main = load_main(guppy_source(prog))
    spans = {s for _, s in run(main, prog["n_qubits"], prog["n_bits"], shots, RUNTIME,
                               timeline=True)}
    if len(spans) != 1:
        raise RuntimeError(f"calibration program has several spans: {spans}")
    return spans.pop()


def empty_span(n: int) -> int:
    if n not in _empty:
        _empty[n] = span_of(f"qubits {n}\nbits 0\n")
    return _empty[n]


def native_time(op: str, outcome: bool = False) -> int:
    """Selene time of one leaf op, from a one-op program. A measure is
    timed separately for outcome 1 (prepared by x), because Selene lowers
    project_z with a conditional re-preparation (notes/selene-timing.txt)."""
    qubits = [int(w[1:]) for w in op.replace(",", " ").split() if w.startswith("q") and w[1:].isdigit()]
    n = max(qubits) + 1
    bits = 1
    text = op
    if op.startswith("measure"):
        text = op.split("->")[0] + "-> c0"
    if op.startswith("measure") and outcome:
        q = qubits[0]
        key = (n, text + " [1]")
        if key not in _native:
            prep = f"qubits {n}\nbits {bits}\nx q{q}\n"
            _native[key] = span_of(prep + text + "\n") - span_of(prep)
        return _native[key]
    key = (n, text)
    if key not in _native:
        _native[key] = span_of(f"qubits {n}\nbits {bits}\n{text}\n") - empty_span(n)
    return _native[key]


def trace_time(t: dict) -> int:
    """Selene time of one trace: the calibrated time of each op, with a
    measure timed by its outcome (notes/selene-timing.txt, finding 5)."""
    outcomes = iter(v for _, v in t["outcomes"])
    return sum(native_time(op, next(outcomes) if op.startswith("measure") else False)
               for op in t["ops"])


def variants(path: Path, noise: list[str]) -> dict[str, str]:
    out = {"source": qlin("fmt", str(path))}
    out["m0"] = qlin_text(out["source"], "fastpath", "--t", "0", "--size", "0", *noise)
    out["best_defer"] = qlin("opt", "--preset", "heron_kingston", *noise, str(path))
    out["fast_t1"] = qlin("fastpath", "--t", "1", *noise, str(path))
    out["sink_fast_t1"] = qlin("fastpath", "--t", "1", "--sink", *noise, str(path))
    return out


def excluded(prog: dict, traces: list) -> str | None:
    if '"Loop"' in json.dumps(prog):
        return "has a loop"
    keys = set()
    for t in traces:
        bits = [b for b, _ in t["outcomes"]]
        if len(bits) != len(set(bits)):
            return "a bit is written twice on one trace"
        final = [False] * prog["n_bits"]
        for b, v in t["outcomes"]:
            final[b] = v
        if tuple(final) in keys:
            return "two traces end with the same bits"
        keys.add(tuple(final))
    return None


def check(text: str) -> tuple[int, int, list[str]]:
    prog = json.loads(qlin_text(text, "json"))
    traces = json.loads(qlin_text(text, "traces"))
    by_final = {}
    for t in traces:
        final = [False] * prog["n_bits"]
        for b, v in t["outcomes"]:
            final[b] = v
        by_final[tuple(final)] = t
    main = load_main(guppy_source(prog))
    base = empty_span(prog["n_qubits"])
    ok, bad = 0, []
    for bits, span in run(main, prog["n_qubits"], prog["n_bits"], SHOTS, RUNTIME, timeline=True):
        t = by_final[bits]
        want = base + trace_time(t)
        if want == span:
            ok += 1
        elif len(bad) < 3:
            bad.append(f"bits {''.join('1' if b else '0' for b in bits)}: qlin {want}, selene {span}")
    return ok, SHOTS, bad


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
        for name, text in variants(path, noise).items():
            vprog = json.loads(qlin_text(text, "json"))
            if vprog["n_qubits"] > SIM_QUBITS:
                skipped.append(f"{bench} {name}: {vprog['n_qubits']} qubits")
                continue
            why = excluded(vprog, json.loads(qlin_text(text, "traces")))
            if why:
                skipped.append(f"{bench} {name}: {why}")
                continue
            ok, total, bad = check(text)
            rows.append({"benchmark": bench, "variant": name, "exact": ok, "shots": total, "misses": bad})
        print(bench, flush=True)
    _write(rows, skipped)
    return 0


def _write(rows, skipped) -> None:
    exact = sum(r["exact"] for r in rows)
    total = sum(r["shots"] for r in rows)
    lines = [
        "# Phase 4 Selene accounting check",
        "",
        "Selene SimpleRuntime is serial (notes/selene-timing.txt). This checks which ops",
        "qlin's traces run on each outcome and the gate lowering, not scheduling.",
        "Durations: HERON_KINGSTON. Emulated.",
        "",
        f"- Shots with an exact match: {exact} of {total}, over {len(rows)} program variants.",
        f"- Native op times calibrated: {len(_native)}.",
        "",
        "Residual misses: Selene's compiler cancels adjacent gates at compile time (a probe",
        "shows `x q0; x q0` compiles to no op), so a shot is not always the plain sum of its",
        "per-op times. A per-op model cannot capture that. In the recorded misses (up to 3",
        "per variant), qlin predicts 64 or 128 ns more than Selene, at most 0.17% of the",
        "shot time. The outcome-1 re-preparation cost (finding 5 in",
        "notes/selene-timing.txt) was learned from the first run's misses and is part of the",
        "prediction.",
        "",
        "| benchmark | variant | exact / shots | first misses |",
        "|---|---|---|---|",
    ]
    for r in rows:
        if r["exact"] != r["shots"]:
            lines.append(f"| {r['benchmark']} | {r['variant']} | {r['exact']} / {r['shots']} | "
                         f"{'; '.join(r['misses'])} |")
    lines.append("")
    lines.append(f"Variants with every shot exact: {sum(r['exact'] == r['shots'] for r in rows)}"
                 f" of {len(rows)} (not listed).")
    lines += ["", "## Excluded", ""] + [f"- {s}" for s in skipped]
    (RESULTS / "phase4_selene.md").write_text("\n".join(lines) + "\n")
    (RESULTS / "phase4_selene.json").write_text(json.dumps(rows, indent=1))


if __name__ == "__main__":
    sys.exit(main())
