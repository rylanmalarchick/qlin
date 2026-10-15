"""Write repetition codes past dynamarq's sizes (it supports d = 3, 5) as
.qlin files in benchmarks/qec/, in dynamarq's construction: encode |1> or
|+> into d data qubits, measure the d - 1 neighbor parities on ancillas,
apply a lookup-table correction, unencode (for |+>), read out.

The lookup table is the minimum-weight correction for every nonzero
syndrome. For d = 3 and 5 it equals dynamarq's tables (checked by
test_gen_repetition.py). The _noisy variants use export_dynamarq.with_noise.

Run: uv run --project bench python bench/gen_repetition.py
"""

import sys

from qiskit import ClassicalRegister, QuantumCircuit, QuantumRegister

from export_dynamarq import with_noise
from qlin_qiskit import ROOT, from_qiskit

OUT = ROOT / "benchmarks" / "qec"
DISTANCES = [7, 9, 11]


def corrections(d: int) -> list[tuple[int, tuple[int, ...]]]:
    """(syndrome value, data qubits to flip) for each nonzero syndrome.
    Syndrome bit i is data i xor data i+1, bit i of the value."""
    best: dict[int, tuple[int, ...]] = {}
    for e in range(1 << d):
        s = sum((((e >> i) ^ (e >> (i + 1))) & 1) << i for i in range(d - 1))
        flips = tuple(i for i in range(d) if e >> i & 1)
        if s and (s not in best or len(flips) < len(best[s])):
            best[s] = flips
    return sorted(best.items())


def circuit(d: int, init: str) -> QuantumCircuit:
    data = QuantumRegister(d, "data")
    anc = QuantumRegister(d - 1, "anc")
    meas = ClassicalRegister(d, "meas")
    syn = ClassicalRegister(d - 1, "syn")
    c = QuantumCircuit(data, anc, meas, syn)
    if init == "1":
        c.x(data[0])
    else:
        c.h(data[0])
    for i in range(1, d):
        c.cx(data[i - 1], data[i])
    for i in range(d - 1):
        c.cx(data[i], anc[i])
        c.cx(data[i + 1], anc[i])
    for i in range(d - 1):
        c.measure(anc[i], syn[i])
    for value, flips in corrections(d):
        with c.if_test((syn, value)):
            for q in flips:
                c.x(data[q])
    if init == "+":
        for i in range(d - 1, 0, -1):
            c.cx(data[i - 1], data[i])
        c.h(data[0])
    c.measure(data, meas)
    return c


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    for d in DISTANCES:
        for k, init in enumerate(["1", "+"]):
            c = circuit(d, init)
            name = f"repetition{d}_{k}"
            (OUT / f"{name}.qlin").write_text(from_qiskit(c))
            noisy = with_noise(c)
            (OUT / f"{name}_noisy.qlin").write_text(from_qiskit(noisy))
            print(f"{name}: {c.num_qubits} qubits, {len(corrections(d))} corrections; "
                  f"noisy {noisy.num_qubits} qubits")
    return 0


if __name__ == "__main__":
    sys.exit(main())
