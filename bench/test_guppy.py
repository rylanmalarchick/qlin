"""The Guppy codegen gives the same output distribution as `qlin sim`.

Selene samples, so the comparison is statistical (bench/dist_check.py).
"""

import json
from collections import Counter
from pathlib import Path

import pytest

from dist_check import compare
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
    got = {"".join("1" if b else "0" for b in k): v for k, v in counts.items()}
    why = compare(exact, got)
    return why is None, why or ""


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


def test_broad_distribution_plant_is_caught():
    # five_qubit_code is uniform over 256 outcomes. An extra x q0 moves it
    # to a disjoint set. A per-outcome tolerance missed this. The TV and
    # support tests must not.
    path = ROOT / "benchmarks/dynamarq/five_qubit_code.qlin"
    text = qlin("fmt", str(path))
    lines = text.splitlines()
    wrong = json.loads(qlin_text_json("\n".join(lines[:2] + ["x q0"] + lines[2:]) + "\n"))
    ok, why = close(path, wrong)
    assert not ok, why


def qlin_text_json(text: str) -> str:
    from qlin_qiskit import qlin_text
    return qlin_text(text, "json")
