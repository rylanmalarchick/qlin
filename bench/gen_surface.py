"""Write the rotated distance-3 surface code ([[9,1,3]]) as .qlin files in
benchmarks/qec/, in the construction of dynamarq's Steane code: encode
|1> or |+>, measure the four Z checks (on xanc, they detect X errors) and
the four X checks (on zanc, they detect Z errors) once, apply a lookup
correction for each nonzero syndrome, decode, and read the logical
operator out on one more qubit.

The encoder is synthesized from the stabilizer list by Qiskit
(StabilizerState), not written by hand. The lookup tables are the
minimum-weight correction for every nonzero syndrome. test_gen_surface.py
checks the checks, the logical operators, and the decoding of every
weight-1 error. The _noisy variants use export_dynamarq.with_noise.

Run: uv run --project bench python bench/gen_surface.py
"""

import sys

from qiskit import ClassicalRegister, QuantumCircuit, QuantumRegister
from qiskit.quantum_info import StabilizerState

from export_dynamarq import with_noise
from qlin_qiskit import ROOT, from_qiskit

OUT = ROOT / "benchmarks" / "qec"
N = 9
# Data qubit r * 3 + c on a 3 x 3 grid. Weight-4 checks on the faces,
# weight-2 checks on the boundary.
X_CHECKS = [(0, 1, 3, 4), (4, 5, 7, 8), (1, 2), (6, 7)]
Z_CHECKS = [(1, 2, 4, 5), (3, 4, 6, 7), (0, 3), (5, 8)]
X_LOGICAL = (0, 3, 6)
Z_LOGICAL = (0, 1, 2)


def pauli(kind: str, support: tuple[int, ...]) -> str:
    """Qiskit Pauli label (qubit 0 rightmost) with `kind` on `support`."""
    return "".join(kind if q in support else "I" for q in reversed(range(N)))


def syndrome(checks: list[tuple[int, ...]], error: int) -> int:
    """Bit i is the parity of `error` (a bit mask of data qubits) on check i."""
    return sum((bin(error & sum(1 << q for q in c)).count("1") & 1) << i
               for i, c in enumerate(checks))


def corrections(checks: list[tuple[int, ...]]) -> list[tuple[int, tuple[int, ...]]]:
    """(syndrome value, data qubits to flip) for each nonzero syndrome."""
    best: dict[int, tuple[int, ...]] = {}
    for e in range(1 << N):
        s = syndrome(checks, e)
        flips = tuple(q for q in range(N) if e >> q & 1)
        if s and (s not in best or len(flips) < len(best[s])):
            best[s] = flips
    return sorted(best.items())


def encoder(init: str) -> QuantumCircuit:
    """Clifford circuit that takes |0...0> to logical |0> or |+>."""
    gens = [pauli("X", c) for c in X_CHECKS] + [pauli("Z", c) for c in Z_CHECKS]
    gens.append(pauli("X", X_LOGICAL) if init == "+" else pauli("Z", Z_LOGICAL))
    return StabilizerState.from_stabilizer_list(gens).clifford.to_circuit()


def circuit(init: str, error: tuple[str, int] | None = None) -> QuantumCircuit:
    """The benchmark. `error` = (kind, qubit) puts one X or Z on a data
    qubit before the syndrome round (used by the tests)."""
    data = QuantumRegister(N, "data")
    xanc = QuantumRegister(len(Z_CHECKS), "xanc")
    zanc = QuantumRegister(len(X_CHECKS), "zanc")
    op = QuantumRegister(1, "log")
    result = ClassicalRegister(1, "result")
    meas = ClassicalRegister(N, "meas")
    xsyn = ClassicalRegister(len(Z_CHECKS), "xsyn")
    zsyn = ClassicalRegister(len(X_CHECKS), "zsyn")
    c = QuantumCircuit(data, xanc, zanc, op, result, meas, xsyn, zsyn)
    c.compose(encoder(init), qubits=list(data), inplace=True)
    if init == "1":
        c.x([data[q] for q in X_LOGICAL])
    if error is not None:
        (c.x if error[0] == "X" else c.z)(data[error[1]])
    # Z checks detect X errors.
    for i, chk in enumerate(Z_CHECKS):
        for q in chk:
            c.cx(data[q], xanc[i])
    # X checks detect Z errors.
    for i, chk in enumerate(X_CHECKS):
        c.h(zanc[i])
        for q in chk:
            c.cx(zanc[i], data[q])
        c.h(zanc[i])
    c.measure(xanc, xsyn)
    c.measure(zanc, zsyn)
    for value, flips in corrections(Z_CHECKS):
        with c.if_test((xsyn, value)):
            for q in flips:
                c.x(data[q])
    for value, flips in corrections(X_CHECKS):
        with c.if_test((zsyn, value)):
            for q in flips:
                c.z(data[q])
    # Read the logical operator of the prepared state (Z_L after undoing
    # X_L for |1>, X_L for |+>) on `log`: 0 means no logical error.
    if init == "1":
        c.x([data[q] for q in X_LOGICAL])
        c.h(op[0])
        for q in Z_LOGICAL:
            c.cz(data[q], op[0])
        c.h(op[0])
    else:
        c.h(op[0])
        for q in X_LOGICAL:
            c.cx(op[0], data[q])
        c.h(op[0])
    c.measure(op[0], result[0])
    c.measure(data, meas)
    return c


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    for k, init in enumerate(["1", "+"]):
        c = circuit(init)
        name = f"surface3_{k}"
        (OUT / f"{name}.qlin").write_text(from_qiskit(c))
        noisy = with_noise(c)
        (OUT / f"{name}_noisy.qlin").write_text(from_qiskit(noisy))
        print(f"{name}: {c.num_qubits} qubits, "
              f"{len(corrections(Z_CHECKS)) + len(corrections(X_CHECKS))} corrections; "
              f"noisy {noisy.num_qubits} qubits")
    return 0


if __name__ == "__main__":
    sys.exit(main())
