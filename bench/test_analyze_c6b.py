"""analyze_c6b on synthetic data: a planted gap slope is recovered."""

import json
import random

from analyze_c6b import KS, main


def test_recovers_planted_slope(tmp_path, capsys):
    rng = random.Random(3)
    rows = []
    for v, per_copy in (("source", 78.0), ("best_defer", 59.0)):
        for k in KS:
            ts = [1000 * (1150 + per_copy * k + rng.gauss(0, 30)) for _ in range(15)]
            rows.append({"variant": f"{v}_x{k}", "times": ts})
    rows[0]["times"][4] += 3_000_000  # one outlier job, 3000 us
    p = tmp_path / "c6b.json"
    p.write_text(json.dumps(rows))
    main(str(p))
    out = capsys.readouterr().out
    assert "jobs dropped 1" in out
    assert "model ranking confirmed" in out
    gap = float(out.split("gap slope ")[1].split()[0])
    assert abs(gap - 19.0) < 4.0
