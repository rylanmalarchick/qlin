"""bqcp keeps a stale bit value after an if/else whose arms both measure it.

Found by the semantics guard on benchmarks/hand/mbqc_chain4.qlin.
Run: uv run --project bench python bench/repro_bqcp_branch_measure.py
Prints P(c2 = 1) for the source and the bqcp output, from Qiskit Aer.
The source gives about 0.5. The bqcp output gives 0.0, because bqcp
removes `if c1 { x q2 }` as if c1 were still 0.
"""

import os
import sys
from pathlib import Path

from qiskit import QuantumCircuit, transpile
from qiskit_aer import AerSimulator

sys.path.insert(0, str(Path(os.environ.get("BQCP_PATH", Path.home() / "dev/oss/bqcp")) / "src"))
from ConstantPropagation import ConstantPropagation  # noqa: E402

SHOTS = 100_000


def circuit() -> QuantumCircuit:
    qc = QuantumCircuit(3, 3)
    qc.h(0)
    qc.measure(0, 0)
    with qc.if_test((qc.clbits[0], 1)) as else_:
        qc.h(1)
        qc.measure(1, 1)
    with else_:
        qc.h(1)
        qc.measure(1, 1)
    with qc.if_test((qc.clbits[1], 1)):
        qc.x(2)
    qc.measure(2, 2)
    return qc


def p_c2(qc: QuantumCircuit) -> float:
    sim = AerSimulator(seed_simulator=1)
    counts = sim.run(transpile(qc, sim), shots=SHOTS).result().get_counts()
    return sum(v for k, v in counts.items() if k.replace(" ", "")[0] == "1") / SHOTS


if __name__ == "__main__":
    src = circuit()
    out = ConstantPropagation.optimize(src, max_amplitudes=512, max_branches=4)
    print(f"source P(c2 = 1) = {p_c2(src):.3f}")
    print(f"bqcp   P(c2 = 1) = {p_c2(out):.3f}")
