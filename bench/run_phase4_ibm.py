"""Phase 4 IBM run: measured time per variant against the model's ranking.

Run: cargo build --release, then
     uv run --project bench python bench/run_phase4_ibm.py            # submits jobs (30 s cap)
     uv run --project bench python bench/run_phase4_ibm.py --budget 60 # raise the cap
     uv run --project bench python bench/run_phase4_ibm.py --probe     # also rerun the branch probe
     ... --bench five_qubit --variants source,best_defer              # a subset only
     ... --repeats 27 --interleave   # N jobs per variant, one per variant per round
Before any device job, each transpiled circuit is simulated on Aer and must
match qlin's output distribution (an offline smoke test).
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

from qlin_qiskit import ROOT, Unsupported, from_qiskit, qlin, qlin_text, to_qiskit

RESULTS = ROOT / "results"
BENCHES = ["benchmarks/jeff/teleportation.qlin", "benchmarks/dynamarq/five_qubit_code.qlin",
           "benchmarks/dynamarq/repetition5_0.qlin"]
SHOTS = 1000
REPEATS = 3
# Branch-cost probe: k sequential if_else blocks on one measured bit.
PROBE_KS = [0, 1, 2, 4, 8]
BUDGET_S = 30  # per run; raise only with --budget SECONDS
SMOKE_SHOTS = 100
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


def aer_matches(circ, qtext: str) -> str | None:
    """Offline smoke test: the transpiled circuit on Aer (noiseless) gives
    the qlin output distribution (bench/dist_check.py). Returns a reason on
    mismatch."""
    from qiskit_aer import AerSimulator
    from dist_check import compare
    from run_baselines import dist
    shots = 4000
    counts = AerSimulator().run(circ, shots=shots, seed_simulator=7).result().get_counts()
    order = circ.metadata["qlin_bits"]
    mapped: dict[str, int] = {}
    for key, n in counts.items():
        flat = key.replace(" ", "")[::-1]  # clbit 0 first
        bits = ["0"] * len(order)
        for pos, b in enumerate(order):
            bits[b] = flat[pos]
        mapped["".join(bits)] = mapped.get("".join(bits), 0) + n
    why = compare(dist(qtext)["dist"], mapped)
    return f"Aer smoke test failed: {why}" if why else None


def main(dry: bool, probe: bool = False, bench: str | None = None,
         only: set[str] | None = None, out: str | None = None,
         interleave: bool = False) -> int:
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

    spent = {"last": start_consumed, "used": 0}

    def budget_left() -> bool:
        """IBM's counter restarts at 0 when the plan period ends. A drop
        counts as a reset, and the new value is time spent since then."""
        if dry:
            return False
        now = service.usage().get("usage_consumed_seconds", 0)
        spent["used"] += now - spent["last"] if now >= spent["last"] else now
        spent["last"] = now
        return spent["used"] < BUDGET_S

    smoked: set[str] = set()

    def one_job(circ, shots: int) -> tuple[float | None, str, str | None]:
        """Per-shot ns from the execution spans, the job id, and a failure reason."""
        from qiskit_ibm_runtime import SamplerV2
        from qiskit_ibm_runtime.exceptions import RuntimeJobFailureError
        job = SamplerV2(mode=backend).run([circ], shots=shots)
        try:
            res = job.result()
        except RuntimeJobFailureError as e:
            return None, job.job_id(), str(e).splitlines()[0][:200]
        spans = res.metadata["execution"]["execution_spans"]
        return sum((sp.stop - sp.start).total_seconds() for sp in spans) / shots * 1e9, job.job_id(), None

    def smoke(circ, bench_path: str, row: dict) -> str | None:
        """The first circuit of each benchmark runs a SMOKE_SHOTS job first."""
        if bench_path in smoked:
            return None
        if not budget_left():
            return "budget reached"
        _, jid, why = one_job(circ, SMOKE_SHOTS)
        row["jobs"].append(jid)
        if why:
            return "smoke job failed: " + why[:180]
        smoked.add(bench_path)
        return None

    def measure(circ, bench_path: str, row: dict) -> str | None:
        """Runs the smoke job if needed, then REPEATS jobs into row. Returns a failure reason."""
        why = smoke(circ, bench_path, row)
        for _ in range(REPEATS) if why is None else []:
            if not budget_left():
                return "budget reached"
            t, jid, why = one_job(circ, SHOTS)
            row["jobs"].append(jid)
            if why:
                return why
            row["times"].append(t)
        return why

    def measure_interleaved(pending: list[tuple[dict, object]], bench_path: str) -> None:
        """REPEATS rounds, one job per circuit per round, so device drift
        affects every circuit alike."""
        live = []
        for row, circ in pending:
            row["why"] = smoke(circ, bench_path, row)
            if row["why"] is None:
                live.append((row, circ))
        for _ in range(REPEATS):
            for row, circ in live:
                if row["why"] is not None:
                    continue
                if not budget_left():
                    row["why"] = "budget reached"
                    continue
                t, jid, why = one_job(circ, SHOTS)
                row["jobs"].append(jid)
                row["why"] = why
                if why is None:
                    row["times"].append(t)
            save()
            print("round", [len(r["times"]) for r, _ in live], flush=True)

    def save() -> None:
        _write(rows, backend.name, cal, dry, out)

    # The branch-cost probe is opt-in (--probe): it was measured on
    # 2026-09-27 and costs device time on every run.
    for k in PROBE_KS if probe else []:
        circ = transpile(branch_probe(k), backend=backend, optimization_level=1, seed_transpiler=0)
        row = {"benchmark": "branch_probe", "variant": f"k={k}", "k": k, "ideal_ns": None,
               "block_ns": None, "depth": circ.depth(), "times": [], "jobs": [], "why": None}
        if not dry:
            row["why"] = measure(circ, "branch_probe", row)
        rows.append(row)
        save()
        print("probe", k, row["times"], row["why"], flush=True)

    for path in [b for b in BENCHES if bench is None or bench in b]:
        failed = None
        pending: list[tuple[dict, object]] = []
        for name, qtext in variants(str(ROOT / path), flags).items():
            if only is not None and name not in only:
                continue
            # The circuit the device runs, back in qlin form for the model.
            try:
                circ0 = to_qiskit(json.loads(qlin_text(qtext, "json")), switch_as_if=True,
                                  no_alias=True)
            except Unsupported as e:
                rows.append({"benchmark": path, "variant": name, "ideal_ns": float("nan"),
                             "block_ns": float("nan"), "depth": None, "times": [], "jobs": [],
                             "why": f"bridge: {e}"})
                save()
                continue
            text = from_qiskit(circ0)
            ideal = json.loads(qlin_text(text, "lat", *flags))["mean"]
            block = json.loads(qlin_text(text, "lat", *flags, "--model", "block"))["mean"]
            row = {"benchmark": path, "variant": name, "ideal_ns": ideal, "block_ns": block,
                   "depth": None, "times": [], "jobs": [], "why": ibm_violation(circ0)}
            if row["why"] is None and failed:
                row["why"] = f"skipped: {failed}"
            if row["why"] is None:
                circ = transpile(circ0, backend=backend, optimization_level=1, seed_transpiler=0)
                circ.metadata = circ0.metadata
                row["depth"] = circ.depth()
                row["why"] = aer_matches(circ, qtext)
            if row["why"] is None and not dry and interleave:
                pending.append((row, circ))
            elif row["why"] is None and not dry:
                row["why"] = measure(circ, path, row)
                if row["why"] and row["why"].startswith("smoke"):
                    # One failure class per benchmark: do not repeat it on siblings.
                    failed = f"{name} failed the smoke job"
            rows.append(row)
            save()
            print(path, name, ideal, block, row["times"], row["why"], flush=True)
        if pending:
            measure_interleaved(pending, path)
    return 0


def _mean_sd(xs: list[float]) -> tuple[float, float] | None:
    if not xs:
        return None
    return st.mean(xs), (st.stdev(xs) if len(xs) > 1 else 0.0)


def _write(rows, backend_name, cal, dry, out: str | None = None) -> None:
    label = "dry run, nothing measured" if dry else "measured"
    lines = [f"# Phase 4 IBM run ({label})", "", f"Backend {backend_name}, {date.today()}.",
             f"Model durations from the backend target (ns): {cal}, t_ff 600.",
             f"{SHOTS} shots per job, up to {REPEATS} jobs per circuit. Measured time per shot is the",
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
    name = "phase4_ibm_dryrun.md" if dry else f"{out or 'phase4_ibm'}.md"
    (RESULTS / name).write_text("\n".join(lines) + "\n")
    (RESULTS / name.replace(".md", ".json")).write_text(json.dumps(rows, indent=1))


if __name__ == "__main__":
    if "--budget" in sys.argv:
        BUDGET_S = int(sys.argv[sys.argv.index("--budget") + 1])
    if "--repeats" in sys.argv:
        REPEATS = int(sys.argv[sys.argv.index("--repeats") + 1])
    arg = lambda flag: sys.argv[sys.argv.index(flag) + 1] if flag in sys.argv else None
    only = set(arg("--variants").split(",")) if arg("--variants") else None
    sys.exit(main("--dry-run" in sys.argv, probe="--probe" in sys.argv,
                  bench=arg("--bench"), only=only, out=arg("--out"),
                  interleave="--interleave" in sys.argv))
