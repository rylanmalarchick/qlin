"""Phase 7.3: translation validation of every benchmark output in Lean.

Run: cargo build --release, then
     uv run --project bench python bench/run_tv.py

For each benchmark: `qlin tv-export` writes the M0 job (source to normal
form) and the fast-path jobs (t = 0, 1, 2), once from the normal form and
once from its Pauli sink. lean/QlinCheck.lean runs the checkers on all
jobs. A passing job is covered by checkBlock_sound or checkFP_sound.
Programs whose records cannot be computed (non-Clifford past 12 qubits)
are listed as skipped.
"""

from __future__ import annotations

import json
import subprocess
import sys

from qlin_qiskit import ROOT, qlin

RESULTS = ROOT / "results"
JOBS = ROOT / "target" / "tv_jobs.json"


def main() -> int:
    jobs, skipped = [], []
    for path in sorted((ROOT / "benchmarks").rglob("*.qlin")):
        bench = str(path.relative_to(ROOT))
        prog = json.loads(qlin("json", str(path)))
        noise = (["--noise-qubits", str(prog["n_qubits"] - 1)]
                 if path.stem.endswith("_noisy") else [])
        for sink in ([], ["--sink"]):
            try:
                out = qlin("tv-export", "--t", "2", *sink, *noise, bench)
            except RuntimeError as e:
                skipped.append(f"{bench} {' '.join(sink)}: {str(e).splitlines()[-1][:120]}")
                continue
            batch = json.loads(out)
            if len(batch) == 1:
                skipped.append(f"{bench} {' '.join(sink)}: fast path not exported "
                               "(no outcome records); M0 job only")
            # The M0 job is the same with and without the sink.
            jobs += batch if not sink else batch[1:]
    JOBS.write_text(json.dumps(jobs))
    run = subprocess.run(["lake", "env", "lean", "--run", "QlinCheck.lean", str(JOBS)],
                         cwd=ROOT / "lean", capture_output=True, text=True, check=False)
    lines = run.stdout.strip().splitlines()
    fails = [ln for ln in lines if not ln.startswith("ok")][:-1]
    out = [
        "# Phase 7.3 results: translation validation in Lean",
        "",
        "Every job runs a Lean checker of lean/Qlin/Check.lean. checkBlock checks",
        "source to M0 normal form. checkFP checks normal form (or its sink) to",
        "fast path, for t = 0, 1, 2. checkBlock_sound and checkFP_sound cover a",
        "passing job (standard axioms only). Simulation checks the sink step",
        "itself, not this run.",
        "",
        f"- {lines[-1]}",
        f"- Jobs not passing: {len(fails)}",
        "",
    ]
    out += [f"  - {f}" for f in fails]
    out += ["", "## Skipped", ""] + [f"- {s}" for s in skipped]
    (RESULTS / "phase7_tv.md").write_text("\n".join(out) + "\n")
    print(lines[-1])
    return 0 if run.returncode == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
