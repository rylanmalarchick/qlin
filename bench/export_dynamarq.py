"""Write dynamarq benchmark circuits as .qlin files in benchmarks/dynamarq/.

Run: uv run --project bench python bench/export_dynamarq.py
"""

import math
import sys

from qiskit import ClassicalRegister, QuantumRegister

from dynamarq.benchmarks.algorithms.IPE import IPE
from dynamarq.benchmarks.eccs.FiveQubitCode import FiveQubitCode
from dynamarq.benchmarks.eccs.RepetitionCode import RepetitionCode
from dynamarq.benchmarks.eccs.SteaneCode import SteaneCode
from dynamarq.benchmarks.gates.CNOTLadder import CNOTLadder
from dynamarq.benchmarks.gates.Fanout import Fanout
from dynamarq.benchmarks.gates.LongRangeCNOT import LongRangeCNOT
from dynamarq.benchmarks.states.GHZ import GHZ

from qlin_qiskit import ROOT, Unsupported, from_qiskit

OUT = ROOT / "benchmarks" / "dynamarq"

# Probability of an X error on each data qubit in the *_noisy variants.
NOISE_P = 0.05
NOISE_THETA = 2 * math.asin(math.sqrt(NOISE_P))
ANCILLA_REGISTERS = {"anc", "xanc", "zanc"}

# (file stem, benchmark, number of circuits to keep). The gate benchmarks
# return one circuit per direct-fidelity-estimation sample. The first one
# is enough for compilation metrics.
SPECS = [
    ("repetition3", lambda: RepetitionCode(3), 2),
    ("repetition5", lambda: RepetitionCode(5), 2),
    ("five_qubit_code", FiveQubitCode, 1),
    ("steane", SteaneCode, 1),
    ("long_range_cnot3", lambda: LongRangeCNOT(3, num_dfe_samples=1), 1),
    ("fanout4", lambda: Fanout(4, num_dfe_samples=1), 1),
    ("cnot_ladder4", lambda: CNOTLadder(4, num_dfe_samples=1), 1),
    ("ghz5", lambda: GHZ(5), 1),
    ("ipe3", lambda: IPE(5, 3), 1),
]


def with_noise(circ):
    """Adds a random X error (probability NOISE_P) on each data qubit, just
    before the first gate on a syndrome ancilla. One extra qubit, the last
    one, is the noise source: prepared, measured, reset for each site."""
    data = next(r for r in circ.qregs if r.name == "data")
    noise = QuantumRegister(1, "noise")
    err = ClassicalRegister(len(data), "err")
    out = circ.copy_empty_like()
    out.add_register(noise)
    out.add_register(err)
    inserted = False
    for inst in circ.data:
        on_ancilla = any(
            reg.name in ANCILLA_REGISTERS
            for q in inst.qubits
            for reg, _ in circ.find_bit(q).registers
        )
        if not inserted and on_ancilla and inst.operation.name != "barrier":
            for i, d in enumerate(data):
                out.ry(NOISE_THETA, noise[0])
                out.measure(noise[0], err[i])
                with out.if_test((err[i], 1)):
                    out.x(d)
                out.reset(noise[0])
            inserted = True
        out.append(inst)
    if not inserted:
        raise ValueError("no gate on a syndrome ancilla")
    return out


NOISY = {"repetition3_0", "repetition3_1", "repetition5_0", "repetition5_1", "five_qubit_code", "steane"}


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    failures = 0
    for stem, make, keep in SPECS:
        circuits = make().qiskit_circuits(mcm=True)[:keep]
        for i, circ in enumerate(circuits):
            name = stem if keep == 1 else f"{stem}_{i}"
            try:
                text = from_qiskit(circ)
            except Unsupported as e:
                print(f"{name}: unsupported: {e}")
                failures += 1
                continue
            (OUT / f"{name}.qlin").write_text(text)
            print(f"{name}: {circ.num_qubits} qubits, {circ.num_clbits} bits")
            if name in NOISY:
                noisy = with_noise(circ)
                (OUT / f"{name}_noisy.qlin").write_text(from_qiskit(noisy))
                print(f"{name}_noisy: {noisy.num_qubits} qubits, {noisy.num_clbits} bits")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
