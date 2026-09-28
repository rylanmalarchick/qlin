"""Phase 4 IBM run: measured time per variant against the model's ranking.

Run: cargo build --release, then
     uv run --project bench python bench/run_phase4_ibm.py            # submits jobs
     uv run --project bench python bench/run_phase4_ibm.py --dry-run  # offline

The model's durations come from the backend target (calibration medians).
t_ff is 600 ns (arXiv:2604.03360). Each variant runs as its own SamplerV2
job with SHOTS shots, so the job's execution spans time that variant alone.
Measured time per shot includes the repetition delay, the same for every
variant of a benchmark, so only the ranking and the differences compare.
IBM backends have if_else but not switch_case, so each Switch runs as a
nested if/else chain, and the model scores that same chain. It runs on
ibm_kingston, only on an Open Plan instance (checked before any job), and
stops once IBM's usage counter shows BUDGET_S seconds used by this run. The dry
run transpiles for FakeKingston and submits nothing.
"""

from __future__ import annotations

import json
import statistics as st
import sys
from datetime import date

from qiskit import transpile

from qlin_qiskit import ROOT, from_qiskit, qlin, qlin_text, to_qiskit

RESULTS = ROOT / "results"
BENCHES = ["benchmarks/jeff/teleportation.qlin", "benchmarks/dynamarq/five_qubit_code.qlin",
           "benchmarks/dynamarq/repetition5_0.qlin"]
SHOTS = 1000
BUDGET_S = 300
MIN_REMAINING_S = 60
# The device the HERON_KINGSTON preset comes from.
BACKEND = "ibm_kingston"


def calibration(backend) -> dict[str, float]:
    """Median durations (ns) from the backend target."""
    t = backend.target

    def med(op: str) -> float:
        return round(st.median(p.duration for p in t[op].values() if p and p.duration) * 1e9, 1)

    two = "cz" if "cz" in t.operation_names else "ecr"
    meas = "measure_2" if "measure_2" in t.operation_names else "measure"
    return {"t1q": med("sx"), "t2q": med(two), "tmeas": med(meas), "treset": med("reset")}


def model_flags(cal: dict[str, float]) -> list[str]:
    return ["--preset", "heron_kingston", "--tff", "600",
            "--t1q", str(cal["t1q"]), "--t2q", str(cal["t2q"]),
            "--tmeas", str(cal["tmeas"]), "--treset", str(cal["treset"])]


def variants(path: str, flags: list[str]) -> dict[str, str]:
    return {
        "source": qlin("fmt", path),
        "best_defer": qlin("opt", *flags, path),
        "fast_t1": qlin("fastpath", "--t", "1", path),
        "sink_fast_t1": qlin("fastpath", "--t", "1", "--sink", path),
    }


def spearman(a: list[float], b: list[float]) -> float:
    def ranks(x):
        order = sorted(range(len(x)), key=lambda i: x[i])
        r = [0.0] * len(x)
        for k, i in enumerate(order):
            r[i] = float(k)
        return r
    ra, rb = ranks(a), ranks(b)
    n = len(a)
    return 1 - 6 * sum((x - y) ** 2 for x, y in zip(ra, rb)) / (n * (n * n - 1))


def main(dry: bool) -> int:
    RESULTS.mkdir(exist_ok=True)
    if dry:
        from qiskit_ibm_runtime.fake_provider import FakeKingston
        backend, service = FakeKingston(), None
    else:
        from qiskit_ibm_runtime import QiskitRuntimeService
        from qiskit_ibm_runtime.accounts.exceptions import InvalidAccountError
        try:
            service = QiskitRuntimeService()
        except InvalidAccountError as e:
            (RESULTS / "phase4_ibm.md").write_text(
                f"# Phase 4 IBM run\n\nNot run ({date.today()}): login failed: {e}\n")
            print("login failed:", e)
            return 0
        # Only ever run on the free Open Plan instance.
        active = service.active_instance()
        plans = {i["crn"]: i.get("plan") for i in service.instances()}
        if plans.get(active) != "open":
            raise SystemExit(f"active instance plan is {plans.get(active)!r}, not 'open'. Not running.")
        usage = service.usage()
        remaining = usage.get("usage_remaining_seconds")
        if remaining is None or remaining < MIN_REMAINING_S:
            (RESULTS / "phase4_ibm.md").write_text(
                f"# Phase 4 IBM run\n\nNot run ({date.today()}): {remaining} s of plan time left.\n")
            return 0
        start_consumed = usage.get("usage_consumed_seconds", 0)
        backend = service.backend(BACKEND)
    cal = calibration(backend)
    flags = model_flags(cal)
    rows, used_s = [], 0.0
    for path in BENCHES:
        for name, qtext in variants(str(ROOT / path), flags).items():
            # The circuit the device runs, back in qlin form for the model.
            circ0 = to_qiskit(json.loads(qlin_text(qtext, "json")), switch_as_if=True)
            text = from_qiskit(circ0)
            ideal = json.loads(qlin_text(text, "lat", *flags))["mean"]
            block = json.loads(qlin_text(text, "lat", *flags, "--model", "block"))["mean"]
            circ = transpile(circ0, backend=backend, optimization_level=1, seed_transpiler=0)
            row = {"benchmark": path, "variant": name, "ideal_ns": ideal, "block_ns": block,
                   "depth": circ.depth(), "measured_ns_per_shot": None}
            if not dry:
                # IBM's own usage counter, checked before every job.
                used_s = service.usage().get("usage_consumed_seconds", 0) - start_consumed
            if not dry and used_s < BUDGET_S:
                from qiskit_ibm_runtime import SamplerV2
                job = SamplerV2(mode=backend).run([circ], shots=SHOTS)
                res = job.result()
                spans = res.metadata["execution"]["execution_spans"]
                total = sum((s.stop - s.start).total_seconds() for s in spans)
                row["measured_ns_per_shot"] = total / SHOTS * 1e9
                row["job"] = job.job_id()
            rows.append(row)
            print(path, name, row["ideal_ns"], row["block_ns"], row["measured_ns_per_shot"], flush=True)
    _write(rows, backend.name, cal, dry)
    return 0


def _write(rows, backend_name, cal, dry) -> None:
    label = "dry run, nothing measured" if dry else "measured"
    lines = [f"# Phase 4 IBM run ({label})", "", f"Backend {backend_name}, {date.today()}.",
             f"Model durations from the backend target (ns): {cal}, t_ff 600.", "",
             "| benchmark | variant | model ideal | model block | depth | measured per shot |",
             "|---|---|---|---|---|---|"]
    for r in rows:
        m = f"{r['measured_ns_per_shot']:.0f}" if r["measured_ns_per_shot"] else "-"
        lines.append(f"| {r['benchmark']} | {r['variant']} | {r['ideal_ns']:.0f} | "
                     f"{r['block_ns']:.0f} | {r['depth']} | {m} |")
    if not dry:
        lines += ["", "## Rank correlation (Spearman, per benchmark)", ""]
        for b in sorted({r["benchmark"] for r in rows}):
            rs = [r for r in rows if r["benchmark"] == b and r["measured_ns_per_shot"]]
            if len(rs) >= 3:
                meas = [r["measured_ns_per_shot"] for r in rs]
                lines.append(f"- {b}: ideal {spearman([r['ideal_ns'] for r in rs], meas):+.2f}, "
                             f"block {spearman([r['block_ns'] for r in rs], meas):+.2f}")
    name = "phase4_ibm_dryrun.md" if dry else "phase4_ibm.md"
    (RESULTS / name).write_text("\n".join(lines) + "\n")
    (RESULTS / name.replace(".md", ".json")).write_text(json.dumps(rows, indent=1))


if __name__ == "__main__":
    sys.exit(main("--dry-run" in sys.argv))
