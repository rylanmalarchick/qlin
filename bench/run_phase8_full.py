"""Full-switch ablation of the Phase 8.1 sweep.

Run: cargo build --release, then
     uv run --project bench python bench/run_phase8_full.py

For every row of results/phase8_switch.csv, builds the fast path with
t = m (the number of group bits), with and without the sink. Then every
outcome has a case and the exit edge is never taken, so the program has
the switch but no speculation. The row's baselines and its fast-path
variants for t < m come from results/phase8_switch.csv, so the two
results use the same model and the same records. Writes
results/phase8_full.csv and results/phase8_full.md.
"""

from __future__ import annotations

import csv
import json
import math
import sys

from qlin_qiskit import ROOT, qlin
from run_phase3 import GAIN_BAR, MAX_T, SIZE

RESULTS = ROOT / "results"
EXIT_TOL = 1e-12


def full_switch(row: dict) -> dict:
    path = ROOT / "benchmarks" / f"{row['benchmark']}.qlin"
    m = int(row["m"])
    noise = (["--noise-qubits", str(int(row["qubits"]) - 1)]
             if path.stem.endswith("_noisy") else [])
    model = ["--model", "block", "--tff", "600", "--tbranch", row["tbranch"],
             "--switch-cost", row["switch"]]
    out = {}
    for sink in (False, True):
        flags = ["--sink"] if sink else []
        key = "sink_full" if sink else "full"
        # The sink changes the dispatch groups, so the sink variant takes its
        # own number of group bits.
        mk = m
        if sink:
            probe = json.loads(qlin("fastpath", "--t", "0", "--size", str(SIZE), *flags,
                                    *model, *noise, "--json", str(path)))
            mk = probe["fastpath"]["group_bits"]
        r = json.loads(qlin("fastpath", "--t", str(mk), "--size", str(SIZE), *flags,
                            *model, *noise, "--json", str(path)))
        out[key] = r["fast"]["mean"]
        out[f"{key}_m"] = mk
        out[f"{key}_exit_prob"] = r["fastpath"]["exit_prob"]
        out[f"{key}_generic_groups"] = r["fastpath"]["generic_groups"]
        out[f"{key}_covered"] = (abs(r["fastpath"]["exit_prob"]) <= EXIT_TOL
                                 and r["fastpath"]["generic_groups"] == 0)
    return out


RAW = ["benchmark", "qubits", "class", "tbranch", "switch", "m"] + [
    f"{k}{f}" for k in ("full", "sink_full")
    for f in ("", "_m", "_exit_prob", "_generic_groups", "_covered")]


def best_below(row: dict, prefix: str, limit: int) -> tuple[float | None, int | None]:
    """Best `prefix`t variant of a phase8_switch row with t < limit."""
    best, which = None, None
    for t in range(0, min(limit - 1, MAX_T) + 1):
        v = row.get(f"{prefix}{t}")
        if v not in (None, "") and (best is None or float(v) < best):
            best, which = float(v), t
    return best, which


def num(x):
    return None if x in (None, "") else float(x)


def derive(raw: dict, sw: dict) -> dict:
    """Paired comparison: each full switch against the speculative variants
    of the same kind (no sink with no sink, sink with sink)."""
    base = float(sw["best_baseline"])
    yes = lambda v: v in (True, "True")  # noqa: E731
    out = {"best_baseline": base, "best_baseline_is": sw["best_baseline_is"]}
    for kind, prefix, m_key in (("nosink", "fast_t", "full_m"), ("sink", "sink_fast_t", "sink_full_m")):
        fkey = "full" if kind == "nosink" else "sink_full"
        full = num(raw[fkey]) if yes(raw[f"{fkey}_covered"]) else None
        spec, t = best_below(sw, prefix, int(num(raw[m_key])))
        out[f"{kind}_full"] = full
        out[f"{kind}_spec"] = spec
        out[f"{kind}_spec_t"] = t
        out[f"{kind}_gain_full"] = None if full is None else (base - full) / base
        out[f"{kind}_gain_spec"] = None if spec is None else (base - spec) / base
        out[f"{kind}_margin"] = (None if full is None or spec is None
                                 else (full - spec) / full)
    return out


def main() -> int:
    with open(RESULTS / "phase8_switch.csv") as f:
        sweep = {(r["benchmark"], r["class"], r["switch"]): r for r in csv.DictReader(f)}
    if "--report" in sys.argv[1:]:
        with open(RESULTS / "phase8_full.csv") as f:
            raws = [{k: r[k] for k in RAW} for r in csv.DictReader(f)]
    else:
        raws = []
        for row in sweep.values():
            if int(row["m"]) == 0:
                continue
            raws.append({"benchmark": row["benchmark"], "qubits": int(row["qubits"]),
                         "class": row["class"], "tbranch": float(row["tbranch"]),
                         "switch": row["switch"], "m": int(row["m"]), **full_switch(row)})
            print(row["benchmark"], row["class"], row["switch"], flush=True)
    out = [raw | derive(raw, sweep[(raw["benchmark"], raw["class"], raw["switch"])])
           for raw in raws]
    _write(out)
    return 0


def _pct(x) -> str:
    return "" if x is None else f"{x:.1%}"


def _write(out: list[dict]) -> None:
    with open(RESULTS / "phase8_full.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0]))
        w.writeheader()
        w.writerows(out)
    points = sorted({(r["class"], float(r["tbranch"]), r["switch"]) for r in out},
                    key=lambda p: (p[1], p[2]))
    lines = [
        "# Full-switch ablation of the Phase 8.1 sweep",
        "",
        "full: the fast path with t = m, where m is the number of group bits of",
        "that variant (the sink changes the groups, so the sink variant has its",
        "own m). A full switch counts only if it covers every outcome: exit",
        f"probability <= {EXIT_TOL:g} and no generic group under the size limit",
        f"S = {SIZE}. spec: the best variant of the same kind with t < m",
        f"(t <= {MAX_T}), from results/phase8_switch.csv. Pairs: no sink with no",
        "sink, sink with sink. margin = (full - spec) / full; positive means",
        "the speculative budget beats the full switch of the same kind. Same",
        "model as phase8_switch: block sync, HERON_LIKE (assumed values),",
        "t_ff = 600 ns, exact outcome records. Rows with m = 0 are left out.",
        "",
        "## Summary",
        "",
        f"Columns per kind: pairs (full covered and spec present), full gains >= {GAIN_BAR:.0%},",
        f"spec gains >= {GAIN_BAR:.0%}, spec beats full by > 1%, largest margin.",
        "",
        "| class | t_branch (ns) | switch | no sink: pairs | full >= 10% | spec >= 10% | spec > full + 1% | max margin "
        "| sink: pairs | full >= 10% | spec >= 10% | spec > full + 1% | max margin |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for cls, tb, sw in points:
        rs = [r for r in out if (r["class"], r["switch"]) == (cls, sw)]
        cells = []
        for kind in ("nosink", "sink"):
            pr = [r for r in rs if r[f"{kind}_margin"] is not None]
            top = max(pr, key=lambda r: r[f"{kind}_margin"]) if pr else None
            cells += [str(len(pr)),
                      str(sum(r[f"{kind}_gain_full"] >= GAIN_BAR for r in pr)),
                      str(sum(r[f"{kind}_gain_spec"] >= GAIN_BAR for r in pr)),
                      str(sum(r[f"{kind}_margin"] > 0.01 for r in pr)),
                      f"{top[f'{kind}_margin']:.1%} ({top['benchmark']})" if top else "none"]
        lines.append(f"| {cls} | {tb:g} | {sw} | " + " | ".join(cells) + " |")
    lines += ["", "## Pairs where a full or spec variant gains at least 1%", "",
              "| benchmark | class | switch | best baseline | no sink: full | spec (t) | margin "
              "| sink: full | spec (t) | margin |",
              "|---|---|---|---|---|---|---|---|---|---|"]
    for r in out:
        gains = [r[f"{k}_gain_{v}"] for k in ("nosink", "sink") for v in ("full", "spec")]
        if any(g is not None and g >= 0.01 for g in gains):
            row = [r["benchmark"], r["class"], r["switch"], f"{r['best_baseline']:.0f}"]
            for kind in ("nosink", "sink"):
                fu, sp, t = r[f"{kind}_full"], r[f"{kind}_spec"], r[f"{kind}_spec_t"]
                row += ["" if fu is None else f"{fu:.0f}",
                        "" if sp is None else f"{sp:.0f} ({t})", _pct(r[f"{kind}_margin"])]
            lines.append("| " + " | ".join(row) + " |")
    lines += _budget_section(out)
    (RESULTS / "phase8_full.md").write_text("\n".join(lines) + "\n")


def _budget_section(out: list[dict], cls: str = "qick", sw: str = "tree") -> list[str]:
    """Gain of the no-sink fast path against t, for the programs whose full
    switch gains GAIN_BAR or more at one sweep point."""
    with open(RESULTS / "phase8_switch.csv") as f:
        sweep = {(r["benchmark"], r["class"], r["switch"]): r for r in csv.DictReader(f)}
    lines = ["", f"## Gain against the budget t ({cls}, {sw}, no sink)", "",
             "cases: sum over k <= t of C(m, k), the number of switch cases of a",
             "program with one dispatch group. Each program below has one group",
             "(`qlin fastpath --json` reports groups = 1 and this size).", "",
             "| benchmark | m | full gain (2^m cases) | gain at t (cases) |", "|---|---|---|---|"]
    for r in out:
        if (r["class"], r["switch"]) != (cls, sw):
            continue
        g = r["nosink_gain_full"]
        if g is None or g < GAIN_BAR:
            continue
        row = sweep[(r["benchmark"], cls, sw)]
        m, base = int(r["m"]), r["best_baseline"]
        cells = []
        for t in range(0, min(m - 1, MAX_T) + 1):
            v = row.get(f"fast_t{t}")
            if v not in (None, ""):
                cases = sum(math.comb(m, k) for k in range(t + 1))
                cells.append(f"t={t}: {(base - float(v)) / base:.1%} ({cases})")
        lines.append(f"| {r['benchmark']} | {m} | {g:.1%} ({2 ** m}) | " + ", ".join(cells) + " |")
    return lines


if __name__ == "__main__":
    sys.exit(main())
