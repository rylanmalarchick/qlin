"""The surface code generator: checks and logical operators commute as a
[[9,1,3]] code needs, the lookup tables correct every weight-1 error, and
the circuit reads logical 0 with no error and with any one X or Z error."""

import pytest
from qiskit_aer import AerSimulator

from gen_surface import N, X_CHECKS, X_LOGICAL, Z_CHECKS, Z_LOGICAL, circuit, corrections, syndrome


def mask(qubits) -> int:
    return sum(1 << q for q in qubits)


def overlap(a, b) -> int:
    return len(set(a) & set(b))


def test_checks_and_logicals_commute_as_a_code():
    for x in X_CHECKS:
        for z in Z_CHECKS:
            assert overlap(x, z) % 2 == 0, (x, z)
    assert all(overlap(X_LOGICAL, z) % 2 == 0 for z in Z_CHECKS)
    assert all(overlap(Z_LOGICAL, x) % 2 == 0 for x in X_CHECKS)
    assert overlap(X_LOGICAL, Z_LOGICAL) % 2 == 1


@pytest.mark.parametrize("checks,logical", [(Z_CHECKS, Z_LOGICAL), (X_CHECKS, X_LOGICAL)])
def test_every_weight1_error_is_corrected(checks, logical):
    # An X error is caught by the Z checks; its residual must not flip Z_L
    # (and the same for Z errors, X checks, and X_L).
    table = dict(corrections(checks))
    for q in range(N):
        e = 1 << q
        residual = e ^ mask(table[syndrome(checks, e)])
        assert syndrome(checks, residual) == 0, q
        assert bin(residual & mask(logical)).count("1") % 2 == 0, q


@pytest.mark.parametrize("init", ["1", "+"])
def test_circuit_reads_logical_zero(init):
    sim = AerSimulator(method="stabilizer")
    errors = [None] + [(k, q) for k in "XZ" for q in range(N)]
    for err in errors:
        counts = sim.run(circuit(init, err), shots=64).result().get_counts()
        # Registers print last-created first, so `result` is the last token.
        assert {key.split()[-1] for key in counts} == {"0"}, (init, err, counts)
