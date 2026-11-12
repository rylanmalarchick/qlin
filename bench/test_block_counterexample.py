"""C1 fails in the block model for a hoisted branch (notes/block-counterexample)."""

import json

import pytest

from qlin_qiskit import ROOT, qlin

PROG = ROOT / "notes" / "block-counterexample" / "hoist_branch.qlin"


def means(model: str) -> tuple[float, float, float, float]:
    d = json.loads(qlin("fastpath", "--t", "0", "--model", model, "--tff", "600",
                        "--tbranch", "42", "--json", str(PROG)))
    return d["source"]["mean"], d["m0"]["mean"], d["source"]["worst"], d["m0"]["worst"]


def test_m0_keeps_the_latency_in_the_ideal_model():
    assert means("ideal") == pytest.approx((1886.0, 1886.0, 2432.0, 2432.0), abs=1e-6)


def test_m0_adds_latency_in_the_block_model():
    assert means("block") == pytest.approx((2078.0, 2208.0, 2474.0, 2708.0), abs=1e-6)
