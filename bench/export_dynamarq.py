"""Write dynamarq benchmark circuits as .qlin files in benchmarks/dynamarq/.

Run: uv run --project bench python bench/export_dynamarq.py
"""

import sys

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
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
