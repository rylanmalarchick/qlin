"""C6b: did ibm_kingston run the jobs in the submitted order?

Run: uv run --project bench python bench/c6b_order.py results/phase7_c6b.json
Reads the job ids of each round (the --submit-ahead order), fetches each
job's start time from IBM, and prints how many adjacent pairs ran out of
order and the time each round spans on the device. Read-only: submits nothing.
"""

import json
import sys

from qiskit_ibm_runtime import QiskitRuntimeService


def main(path: str) -> None:
    rows = json.load(open(path))
    # jobs[0] of the first row is the smoke job. The rest are rounds in order.
    jobs = [r["jobs"][1:] if i == 0 else r["jobs"] for i, r in enumerate(rows)]
    order = [jobs[c][r] for r in range(len(jobs[0])) for c in range(len(rows))]
    service = QiskitRuntimeService()
    start = {jid: service.job(jid).metrics()["timestamps"]["running"] for jid in order}
    swaps = sum(start[a] > start[b] for a, b in zip(order, order[1:]))
    print(f"jobs {len(order)}, adjacent pairs out of submitted order {swaps}")
    print(f"first start {min(start.values())}, last start {max(start.values())}")
    for r in range(len(jobs[0])):
        ts = sorted(start[jobs[c][r]] for c in range(len(rows)))
        print(f"round {r + 1}: {ts[0]} to {ts[-1]}")


if __name__ == "__main__":
    main(sys.argv[1])
