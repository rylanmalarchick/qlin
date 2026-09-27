"""The Guppy codegen gives the same output distribution as `qlin sim`.

Selene samples, so each bit-string probability is compared with the
exact one within 5 standard errors of the sampling estimate, plus 0.005.
"""

import json
from collections import Counter
from pathlib import Path

import pytest

from qlin_guppy import guppy_source, load_main
from qlin_qiskit import ROOT, qlin
from selene_run import run

SHOTS = 2000
FILES = [p for p in sorted((ROOT / "benchmarks").rglob("*.qlin"))
         if json.loads(qlin("json", str(p)))["n_qubits"] <= 12]


def close(path_or_prog, prog: dict) -> tuple[bool, str]:
    exact = json.loads(qlin("sim", str(path_or_prog)))["dist"]
    main = load_main(guppy_source(prog))
    counts = Counter(bits for bits, _ in run(main, prog["n_qubits"], prog["n_bits"], SHOTS))
    got = {"".join("1" if b else "0" for b in k): v / SHOTS for k, v in counts.items()}
    for key in set(exact) | set(got):
        p, q = exact.get(key, 0.0), got.get(key, 0.0)
        tol = 5 * (p * (1 - p) / SHOTS) ** 0.5 + 0.005
        if abs(p - q) > tol:
            return False, f"{key}: exact {p:.4f}, selene {q:.4f}, tol {tol:.4f}"
    return True, ""


@pytest.mark.parametrize("path", FILES, ids=lambda p: str(p.relative_to(ROOT)))
def test_distribution_matches(path: Path):
    ok, why = close(path, json.loads(qlin("json", str(path))))
    assert ok, why


def test_wrong_gate_mapping_is_caught():
    # The z correction written as x changes teleportation's output.
    path = ROOT / "benchmarks/jeff/teleportation.qlin"
    prog = json.loads(qlin("json", str(path)))
    wrong = json.loads(json.dumps(prog).replace('"gate": "z"', '"gate": "x"'))
    assert wrong != prog
    ok, _ = close(path, wrong)
    assert not ok
