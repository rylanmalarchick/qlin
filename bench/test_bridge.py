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
