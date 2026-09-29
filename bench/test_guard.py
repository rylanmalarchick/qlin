"""The semantics guard must reject a wrong program."""

from qlin_qiskit import ROOT, qlin
from run_baselines import dist, same_distribution

TELEPORT = (ROOT / "benchmarks" / "jeff" / "teleportation.qlin").read_text()


def test_guard_accepts_the_same_program():
    ok, worst = same_distribution(dist(TELEPORT), dist(qlin("fmt", str(ROOT / "benchmarks/jeff/teleportation.qlin"))))
    assert ok and worst < 1e-12


def test_guard_rejects_a_missing_correction():
    # Without `z q2` under c0, the final bit c2 is no longer always 0.
    broken = TELEPORT.replace("if c0 {\n  z q2\n}\n", "")
    assert broken != TELEPORT
    ok, worst = same_distribution(dist(TELEPORT), dist(broken))
    assert not ok and worst > 0.1
