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
REPEATS = 3
# Branch-cost probe: k sequential if_else blocks on one measured bit.
PROBE_KS = [0, 1, 2, 4, 8]
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
        "sink_only": qlin("fastpath", "--t", "0", "--size", "0", "--sink", path),
        "fast_t1": qlin("fastpath", "--t", "1", path),
        "sink_fast_t1": qlin("fastpath", "--t", "1", "--sink", path),
    }


def ibm_violation(circ, inside: bool = False) -> str | None:
    """The first IBM dynamic-circuit rule the circuit breaks, or None.
    Rules (IBM docs, execute-dynamic-circuits): no nested conditionals, no
    measure or reset inside a conditional, no for, while, or switch."""
    for inst in circ.data:
        op = inst.operation
        if op.name in ("for_loop", "while_loop", "switch_case"):
            return f"{op.name} is not supported"
        if inside and op.name in ("measure", "reset"):
            return f"{op.name} inside a conditional"
        if op.name == "if_else":
            if inside:
                return "nested conditional"
            for block in op.blocks:
                why = ibm_violation(block, inside=True)
                if why:
                    return why
    return None


def branch_probe(k: int):
    """h, measure c0, then k if_else blocks on c0 (each flips q1), measure q1."""
    from qiskit import QuantumCircuit
    qc = QuantumCircuit(2, 2)
    qc.h(0)
    qc.measure(0, 0)
    for _ in range(k):
        with qc.if_test((qc.clbits[0], 1)):
            qc.x(1)
    qc.measure(1, 1)
    return qc


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
    rows: list[dict] = []

    def budget_left() -> bool:
        if dry:
            return False
        used = service.usage().get("usage_consumed_seconds", 0) - start_consumed
        return used < BUDGET_S

    def measure(circ) -> tuple[list[float], list[str], str | None]:
        """Per-shot ns for each repeat, the job ids, and a failure reason."""
        from qiskit_ibm_runtime import SamplerV2
        from qiskit_ibm_runtime.exceptions import RuntimeJobFailureError
        times, ids = [], []
        for _ in range(REPEATS):
            if not budget_left():
                return times, ids, "budget reached"
            job = SamplerV2(mode=backend).run([circ], shots=SHOTS)
            ids.append(job.job_id())
            try:
                res = job.result()
            except RuntimeJobFailureError as e:
                return times, ids, str(e).splitlines()[0][:200]
            spans = res.metadata["execution"]["execution_spans"]
            times.append(sum((sp.stop - sp.start).total_seconds() for sp in spans) / SHOTS * 1e9)
        return times, ids, None

    def save() -> None:
        _write(rows, backend.name, cal, dry)

    for k in PROBE_KS:
        circ = transpile(branch_probe(k), backend=backend, optimization_level=1, seed_transpiler=0)
        row = {"benchmark": "branch_probe", "variant": f"k={k}", "k": k, "ideal_ns": None,
               "block_ns": None, "depth": circ.depth(), "times": [], "jobs": [], "why": None}
        if not dry:
            row["times"], row["jobs"], row["why"] = measure(circ)
        rows.append(row)
        save()
        print("probe", k, row["times"], row["why"], flush=True)

    for path in BENCHES:
        for name, qtext in variants(str(ROOT / path), flags).items():
            # The circuit the device runs, back in qlin form for the model.
            circ0 = to_qiskit(json.loads(qlin_text(qtext, "json")), switch_as_if=True)
            text = from_qiskit(circ0)
            ideal = json.loads(qlin_text(text, "lat", *flags))["mean"]
            block = json.loads(qlin_text(text, "lat", *flags, "--model", "block"))["mean"]
            row = {"benchmark": path, "variant": name, "ideal_ns": ideal, "block_ns": block,
                   "depth": None, "times": [], "jobs": [], "why": ibm_violation(circ0)}
            if row["why"] is None:
                circ = transpile(circ0, backend=backend, optimization_level=1, seed_transpiler=0)
                row["depth"] = circ.depth()
                if not dry:
                    row["times"], row["jobs"], row["why"] = measure(circ)
            rows.append(row)
            save()
            print(path, name, ideal, block, row["times"], row["why"], flush=True)
    return 0


def _mean_sd(xs: list[float]) -> tuple[float, float] | None:
    if not xs:
        return None
    return st.mean(xs), (st.stdev(xs) if len(xs) > 1 else 0.0)


def _write(rows, backend_name, cal, dry) -> None:
    label = "dry run, nothing measured" if dry else "measured"
    lines = [f"# Phase 4 IBM run ({label})", "", f"Backend {backend_name}, {date.today()}.",
             f"Model durations from the backend target (ns): {cal}, t_ff 600.",
             f"{SHOTS} shots per job, {REPEATS} jobs per circuit. Measured time per shot is the",
             "execution-span total over the shots, so it includes the repetition delay,",
             "which is the same for every circuit.", ""]
    probe = [(r["k"], _mean_sd(r["times"])) for r in rows if r["benchmark"] == "branch_probe"]
    pts = [(k, m[0]) for k, m in probe if m]
    lines += ["## Branch-cost probe", "", "| if_else blocks | per shot (us), mean +- sd |", "|---|---|"]
    lines += [f"| {k} | {m[0] / 1000:.2f} +- {m[1] / 1000:.2f} |" if m else f"| {k} | - |" for k, m in probe]
    if len(pts) >= 2:
        n = len(pts)
        mx, my = sum(k for k, _ in pts) / n, sum(v for _, v in pts) / n
        slope = sum((k - mx) * (v - my) for k, v in pts) / sum((k - mx) ** 2 for k, _ in pts)
        lines += ["", f"Least-squares slope: {slope / 1000:.2f} us per if_else block."]
    lines += ["", "## Benchmark variants", "",
              "| benchmark | variant | model ideal (ns) | model block (ns) | measured per shot (us) | note |",
              "|---|---|---|---|---|---|"]
    for r in rows:
        if r["benchmark"] == "branch_probe":
            continue
        m = _mean_sd(r["times"])
        ms = f"{m[0] / 1000:.2f} +- {m[1] / 1000:.2f}" if m else "-"
        lines.append(f"| {r['benchmark']} | {r['variant']} | {r['ideal_ns']:.0f} | "
                     f"{r['block_ns']:.0f} | {ms} | {r['why'] or ''} |")
    if not dry:
        lines += ["", "## Rank correlation (Spearman, per benchmark, measured means)", ""]
        for b in sorted({r["benchmark"] for r in rows} - {"branch_probe"}):
            rs = [r for r in rows if r["benchmark"] == b and r["times"]]
            if len(rs) >= 3:
                meas = [st.mean(r["times"]) for r in rs]
                lines.append(f"- {b}: ideal {spearman([r['ideal_ns'] for r in rs], meas):+.2f}, "
                             f"block {spearman([r['block_ns'] for r in rs], meas):+.2f} (n = {len(rs)})")
            else:
                lines.append(f"- {b}: {len(rs)} variants measured, too few for a rank correlation")
    name = "phase4_ibm_dryrun.md" if dry else "phase4_ibm.md"
    (RESULTS / name).write_text("\n".join(lines) + "\n")
    (RESULTS / name.replace(".md", ".json")).write_text(json.dumps(rows, indent=1))


if __name__ == "__main__":
    sys.exit(main("--dry-run" in sys.argv))
