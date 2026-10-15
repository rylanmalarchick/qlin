"""The Lean checker accepts qlin's own outputs and rejects planted errors.

bench/tv_planted.json holds five hand-made jobs: a valid hoist, a hoist of
an op that one arm lacks, a valid fold, a valid dispatch, and a dispatch
whose case body drops the arm its value selects.
"""

import subprocess

from qlin_qiskit import ROOT, qlin


def check(path) -> list[str]:
    run = subprocess.run(["lake", "env", "lean", "--run", "QlinCheck.lean", str(path)],
                         cwd=ROOT / "lean", capture_output=True, text=True, check=False)
    return run.stdout.strip().splitlines()


def test_planted_errors_are_rejected():
    lines = check(ROOT / "bench" / "tv_planted.json")
    assert lines[:5] == ["ok   hoist", "FAIL bad-hoist", "ok   fold", "ok   switch",
                         "FAIL bad-switch"]


def test_own_output_is_accepted():
    jobs = ROOT / "target" / "tv_test_jobs.json"
    jobs.write_text(qlin("tv-export", "--t", "2", "benchmarks/hand/repetition3.qlin"))
    assert check(jobs)[-1] == "4 of 4 jobs checked"
