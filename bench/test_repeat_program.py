"""repeat_program keeps the output distribution and scales the op count."""

import json

from qlin_qiskit import ROOT, qlin, qlin_text
from run_phase4_ibm import repeat_program


def test_repeat_keeps_distribution():
    path = ROOT / "benchmarks" / "dynamarq" / "five_qubit_code.qlin"
    one = qlin("fmt", str(path))
    # k = 2 only: the dense simulator enumerates every copy's outcomes.
    for k in (2,):
        many = repeat_program(one, k)
        d_many = json.loads(qlin_text(many, "sim"))["dist"]
        d_one = json.loads(qlin_text(one, "sim"))["dist"]
        assert d_many.keys() == d_one.keys()
        assert all(abs(d_many[b] - d_one[b]) < 1e-12 for b in d_one)
        n_one = len(one.strip().splitlines()) - 2
        n_many = len(many.strip().splitlines()) - 2
        assert n_many == k * n_one + (k - 1) * 11
