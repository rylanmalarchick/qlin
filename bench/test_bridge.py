"""Round trip qlin -> Qiskit -> qlin on every benchmark."""

from pathlib import Path

import pytest

from qlin_qiskit import ROOT, from_qiskit, load_qiskit, qlin

FILES = sorted((ROOT / "benchmarks").rglob("*.qlin"))


def test_benchmarks_exist():
    assert len(FILES) >= 31


@pytest.mark.parametrize("path", FILES, ids=lambda p: str(p.relative_to(ROOT)))
def test_round_trip_is_exact(path: Path):
    circ, prog = load_qiskit(path)
    loop_max = _loop_max(prog["body"])
    assert from_qiskit(circ, loop_max=loop_max) == qlin("fmt", str(path))


def _loop_max(block) -> int:
    for op in block:
        (kind, a), = op.items()
        if kind == "Loop":
            return a["max_iters"]
        for key in ("then_", "else_", "body"):
            if key in a:
                inner = _loop_max(a[key])
                if inner:
                    return inner
    return 0


FASTPATH = ["benchmarks/hand/repetition3.qlin", "benchmarks/dynamarq/repetition5_0_noisy.qlin",
            "benchmarks/dynamarq/five_qubit_code.qlin"]


@pytest.mark.parametrize("rel", FASTPATH)
def test_switch_round_trip(rel: str):
    from qlin_qiskit import qlin_text, to_qiskit
    import json
    path = ROOT / rel
    prog = json.loads(qlin("json", str(path)))
    noise = ["--noise-qubits", str(prog["n_qubits"] - 1)] if "noisy" in rel else []
    text = qlin("fastpath", "--t", "2", *noise, str(path))
    assert "switch" in text
    circ = to_qiskit(json.loads(qlin_text(text, "json")))
    assert from_qiskit(circ) == qlin_text(text, "fmt")
