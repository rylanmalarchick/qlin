"""C6b model prediction per variant: block-model time per shot at each k.

Run: uv run --project bench python bench/c6b_model.py
Rebuilds the C6b circuits as run_phase4_ibm.py does (FakeKingston
calibration snapshot, HERON_KINGSTON, t_ff 600 ns) and scores them with the
block model at t_branch = 0, 1725, and 3450 ns (3450 is the measured branch
cost; k = 1 exact, k > 1 sampled with 2000 records, seed 1). Writes
results/phase7_c6b_model.json and prints, per t_branch, the time per shot of
each variant, the gap per k, and the least-squares slopes against k.
notes/c6b-prereg.txt quotes the gaps at 3450 ns (19.29, 38.51, 76.96, 153.84 us).
"""

import json

from qiskit_ibm_runtime.fake_provider import FakeKingston

from qlin_qiskit import ROOT, from_qiskit, qlin_text, to_qiskit
from run_phase4_ibm import MODEL_SAMPLES, RESULTS, calibration, model_flags, repeat_program, variants

KS = (1, 2, 4, 8)
T_BRANCH_NS = (0, 1725, 3450)


def slope(ys: list[float]) -> float:
    kb, yb = sum(KS) / len(KS), sum(ys) / len(ys)
    return sum((k - kb) * (y - yb) for k, y in zip(KS, ys)) / sum((k - kb) ** 2 for k in KS)


def main() -> None:
    flags = model_flags(calibration(FakeKingston()))
    base = variants(str(ROOT / "benchmarks/dynamarq/five_qubit_code.qlin"), flags)
    texts = {(v, k): from_qiskit(to_qiskit(json.loads(qlin_text(repeat_program(base[v], k), "json")),
                                           switch_as_if=True, no_alias=True))
             for v in ("source", "best_defer") for k in KS}
    out = []
    for tb in T_BRANCH_NS:
        us = {}
        for v in ("source", "best_defer"):
            us[v] = []
            for k in KS:
                sample = [] if k == 1 else ["--sample", str(MODEL_SAMPLES), "--seed", "1"]
                lat = qlin_text(texts[(v, k)], "lat", *flags, "--model", "block",
                                "--tbranch", str(tb), *sample)
                us[v].append(json.loads(lat)["mean"] / 1000)
        gap = [a - b for a, b in zip(us["source"], us["best_defer"])]
        out.append({"t_branch_ns": tb, "us": us, "gap": gap,
                    "slope": {v: slope(us[v]) for v in us}, "gap_slope": slope(gap)})
        for v in us:
            print(tb, v, "per shot (us):", " ".join(f"{x:.2f}" for x in us[v]),
                  f"slope {slope(us[v]):.2f} us/copy")
        print(tb, "gap (us):", " ".join(f"{x:.2f}" for x in gap), f"slope {slope(gap):.2f} us/copy")
    (RESULTS / "phase7_c6b_model.json").write_text(json.dumps(out, indent=1) + "\n")


if __name__ == "__main__":
    main()
