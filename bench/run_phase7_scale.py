"""Phase 7.2: the Phase 3 sweep on the benchmarks past 12 qubits.

Run: cargo build --release, then
     uv run --project bench python bench/run_phase7_scale.py

Same model, variants, and gain as bench/run_phase3.py (block sync,
HERON_LIKE, t_ff 600 ns, t_branch 0, 200, 1000). Records come from the
stabilizer backend. Every fast-path and sink variant runs with --check,
which uses the stabilizer check past 12 qubits. bqcp and Qiskit O3 outputs
count only when `qlin check --random 0` finds them equal to the source
from |0...0>, the input the Phase 1 guard uses. Programs that
the stabilizer backend does not run are listed as skipped.
"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

from qlin_qiskit import ROOT, bit_names, from_qiskit, load_qiskit, qlin
from run_baselines import bqcp, qiskit_o3
from run_phase3 import MAX_T, SIM_QUBITS, SIZE, TBRANCH, model

RESULTS = ROOT / "results"
TMP = ROOT / "target"


def guarded(path: Path, text: str) -> tuple[str | None, str]:
    """`text` if `qlin check` finds it equal to the source, with the reason."""
    tmp = TMP / "phase7_baseline.qlin"
    tmp.write_text(text)
    # From |0...0> only, as the Phase 1 guard: bqcp propagates constants
    # from that input and is not meant to agree on others.
    r = json.loads(qlin("check", "--random", "0", str(path), str(tmp)))
    if r.get("equal") is True:
        return text, "checked"
    return None, r.get("why") or r.get("unsupported") or "not equal"


def baseline_texts(path: Path) -> dict[str, tuple[str | None, str]]:
    circ, _ = load_qiskit(path)
    out = {}
    for name, run in (("bqcp", bqcp), ("qiskit_o3", qiskit_o3)):
        try:
            text = from_qiskit(run(circ.copy()), names=bit_names(circ))
        # A baseline pass can raise many exception types. The row records
        # the baseline as missing.
        except Exception as e:  # noqa: BLE001
            out[name] = (None, f"failed: {type(e).__name__}")
            continue
        out[name] = guarded(path, text)
    return out


def main() -> int:
    RESULTS.mkdir(exist_ok=True)
    rows, skipped, notes = [], [], []
    checked = 0
    for path in sorted((ROOT / "benchmarks").rglob("*.qlin")):
        bench = str(path.relative_to(ROOT / "benchmarks").with_suffix(""))
        prog = json.loads(qlin("json", str(path)))
        if prog["n_qubits"] <= SIM_QUBITS:
            continue
        noise = ["--noise-qubits", str(prog["n_qubits"] - 1)] if path.stem.endswith("_noisy") else []
        try:
            qlin("lat", *noise, str(path))
        except RuntimeError as e:
            skipped.append(f"{bench}: {e}")
            continue
        bases = baseline_texts(path)
        for name, (_, why) in bases.items():
            notes.append(f"{bench} {name}: {why}")
        for tb in TBRANCH:
            m = model(tb)
            row = {"benchmark": bench, "tbranch": tb, "qubits": prog["n_qubits"]}
            probe = json.loads(qlin("fastpath", "--t", "0", *m, *noise, "--json", str(path)))
            row["source"] = probe["source"]["mean"]
            row["m0"] = probe["m0"]["mean"]
            row["m"] = probe["fastpath"]["group_bits"]
            opt = json.loads(qlin("opt", *m, *noise, "--json", str(path)))
            row["best_defer"] = opt["bnb"]["best"]["mean"]
            for name, (text, _) in bases.items():
                if text is None:
                    row[name] = None
                    continue
                tmp = TMP / "phase7_baseline.qlin"
                tmp.write_text(text)
                row[name] = json.loads(qlin("lat", *m, *noise, str(tmp)))["mean"]
            best_ours, best_desc = None, ""
            for sink in (False, True):
                for t in range(0, min(row["m"], MAX_T) + 1):
                    flags = ["--sink"] if sink else []
                    if tb == TBRANCH[0]:
                        flags.append("--check")
                    r = json.loads(qlin("fastpath", "--t", str(t), "--size", str(SIZE), *flags,
                                        *m, *noise, "--json", str(path)))
                    if tb == TBRANCH[0] and not r["checked"]:
                        raise SystemExit(f"{bench} t={t}: fast path not checked")
                    checked += r["checked"]
                    key = f"{'sink_' if sink else ''}fast_t{t}"
                    row[key] = r["fast"]["mean"]
                    row[key + "_size"] = r["fastpath"]["size"]
                    row[key + "_exit"] = r["fastpath"]["exit_prob"]
                    if best_ours is None or r["fast"]["mean"] < best_ours:
                        best_ours, best_desc = r["fast"]["mean"], key
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
    _write(rows, skipped, notes, checked)
    return 0


def _write(rows, skipped, notes, checked) -> None:
    cols = sorted({k for r in rows for k in r}, key=lambda k: (k not in ("benchmark", "tbranch"), k))
    with open(RESULTS / "phase7_scale.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    lines = [
        "# Phase 7.2 results: benchmarks past 12 qubits",
        "",
        "Model: block sync, HERON_LIKE (assumed values), t_ff = 600 ns. Latency is",
        "expected makespan (ns) over exact outcome probabilities from |0...0>, from",
        "the stabilizer backend. Every fast-path and sink variant passed the",
        f"stabilizer check: {checked} variants (a failure stops the run).",
        "",
    ]
    for tb in TBRANCH:
        lines += [
            f"## t_branch = {tb:g} ns",
            "",
            "| benchmark | qubits | best baseline | which | best ours | which | gain |",
            "|---|---|---|---|---|---|---|",
        ]
        for r in rows:
            if r["tbranch"] == tb:
                lines.append(
                    f"| {r['benchmark']} | {r['qubits']} | {r['best_baseline']:.0f} | "
                    f"{r['best_baseline_is']} | {r['best_ours']:.0f} | {r['best_ours_is']} | "
                    f"{r['gain']:.1%} |")
        lines.append("")
    lines += ["## Baselines (guarded by qlin check from |0...0>)", ""] + [f"- {n}" for n in notes] + [""]
    lines += ["## Skipped", ""] + [f"- {s}" for s in skipped]
    (RESULTS / "phase7_scale.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    sys.exit(main())
