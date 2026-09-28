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


def test_switch_as_if_chain_keeps_semantics():
    from qlin_qiskit import qlin_text, to_qiskit
    from run_baselines import dist, same_distribution
    import json
    path = ROOT / "benchmarks/dynamarq/repetition3_0_noisy.qlin"
    text = qlin("fastpath", "--t", "2", "--noise-qubits", "5", str(path))
    chain = from_qiskit(to_qiskit(json.loads(qlin_text(text, "json")), switch_as_if=True))
    assert "switch" not in chain and "if " in chain
    ok, worst = same_distribution(dist(text), dist(chain))
    assert ok, worst


@pytest.mark.parametrize("rel", ["benchmarks/dynamarq/five_qubit_code.qlin",
                                 "benchmarks/dynamarq/repetition5_0_noisy.qlin",
                                 "benchmarks/jeff/teleportation.qlin"])
def test_no_alias_layout_keeps_semantics(rel: str):
    """Every clbit is in one register, and the output distribution matches
    qlin sim after mapping clbits back to qlin bits."""
    from qlin_qiskit import qlin_text, to_qiskit
    from run_baselines import dist
    import json
    path = ROOT / rel
    prog = json.loads(qlin("json", str(path)))
    circ = to_qiskit(prog, no_alias=True)
    owners = {}
    for r in circ.cregs:
        for bit in r:
            owners[bit] = owners.get(bit, 0) + 1
    assert all(n == 1 for n in owners.values()) and len(owners) == circ.num_clbits
    text = from_qiskit(circ)
    order = circ.metadata["qlin_bits"]
    got = dist(text)["dist"]
    mapped = {}
    for key, p in got.items():
        bits = ["0"] * len(order)
        for pos, b in enumerate(order):
            bits[b] = key[pos]
        mapped["".join(bits)] = mapped.get("".join(bits), 0.0) + p
    want = dist(qlin("fmt", str(path)))["dist"]
    for k in set(want) | set(mapped):
        assert abs(want.get(k, 0.0) - mapped.get(k, 0.0)) < 1e-9, k
