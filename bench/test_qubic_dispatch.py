"""qubic_dispatch: the programs for QubiC run the arms that qlin's own
semantics selects, for every syndrome value, and `qlin records` gives the
exact syndrome probabilities."""

import json
import tempfile
from pathlib import Path

import pytest

import qubic_dispatch as qd
from qlin_qiskit import ROOT, qlin

REP3 = ROOT / "benchmarks" / "dynamarq" / "repetition3_1_noisy.qlin"
FIVE = ROOT / "benchmarks" / "dynamarq" / "five_qubit_code_noisy.qlin"


def fast_group(path: Path, t: int, noise: int) -> qd.Group:
    text = qlin("fastpath", "--t", str(t), "--noise-qubits", str(noise), str(path))
    with tempfile.NamedTemporaryFile("w", suffix=".qlin") as f:
        f.write(text)
        f.flush()
        return qd.group_of(json.loads(qlin("json", f.name)))


def test_records_give_exact_syndrome_probabilities():
    # X errors at rate 0.05 on q0, q1, q2 before the syndrome (c3, c4).
    # (c3, c4) = (1, 0) when q0 alone or q1 and q2 flip:
    # 0.05 * 0.95^2 + 0.95 * 0.05^2 = 0.0475.
    recs = json.loads(qlin("records", str(REP3)))
    assert sum(r["prob"] for r in recs) == pytest.approx(1.0, rel=1e-12)
    p10 = sum(r["prob"] for r in recs if r["outcomes"]["3"] == [True] and r["outcomes"]["4"] == [False])
    assert p10 == pytest.approx(0.0475, rel=1e-12)


@pytest.mark.parametrize("path,noise", [(REP3, 5), (FIVE, 11)])
@pytest.mark.parametrize("variant", ["source", "chain", "tree"])
def test_every_variant_runs_the_selected_arms(path, noise, variant):
    g = fast_group(path, 1, noise)
    code = qd.program(g, variant)
    for s in range(1 << len(g.bits)):
        marks, _ = qd.run(code, s)
        assert marks == qd.selected(g, s), (variant, s)


def test_decision_counts_on_repetition3():
    # t = 1 around syndrome 0: cases {0, 1, 2}; 3 goes to the default.
    g = fast_group(REP3, 1, 5)
    assert sorted(g.cases) == [0, 1, 2]
    dec = {v: [qd.run(qd.program(g, v), s)[1] for s in range(4)] for v in ("source", "chain", "tree")}
    # Three ifs, one true value each: one EQ per if, every time.
    assert dec["source"] == [3, 3, 3, 3]
    # Tree: LE on 0, then one EQ on the left or EQ 1, EQ 2 on the right;
    # s = 3 falls through both EQs to the default (3 more).
    assert dec["tree"] == [2, 2, 3, 3 + 3]
    # Chain: the k-th case takes k + 1 compares; the default takes all 3, then 3.
    order = g.cases
    assert dec["chain"] == [order.index(s) + 1 if s in order else len(order) + 3 for s in range(4)]
