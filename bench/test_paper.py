"""The paper tables agree with the phase reports.

bench/paper_tables.py computes tables from results/*.csv and *.json. The
phase runners wrote results/*.md from the same runs with separate code.
Each emitted value is compared with its report line.
"""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from qlin_qiskit import ROOT

EMITTER = ROOT / "bench" / "paper_tables.py"


def emit(out: Path, results: Path | None = None) -> None:
    env = dict(os.environ)
    if results is not None:
        env["QLIN_RESULTS"] = str(results)
    subprocess.run([sys.executable, str(EMITTER), str(out)], check=True, env=env,
                   capture_output=True)


def cells(line: str) -> list[str]:
    """The cells of a LaTeX table row, without markup."""
    line = line.rstrip().removesuffix(r"\\").strip()
    return [re.sub(r"\\texttt\{(.*)\}", r"\1", c.strip()).replace(r"\_", "_").replace(r"\%", "%")
            for c in line.split("&")]


def body(tex: str) -> list[list[str]]:
    part = tex.split(r"\midrule")[1].split(r"\bottomrule")[0]
    return [cells(x) for x in part.strip().splitlines()]


def mismatches(out: Path) -> list[str]:
    bad = []
    p2 = (ROOT / "results" / "phase2.md").read_text()
    for r in body((out / "tables" / "defer.tex").read_text()):
        want = "| " + " | ".join([r[0], "600"] + r[1:]) + " |"
        if want not in p2:
            bad.append(f"defer: {want}")
    p3 = (ROOT / "results" / "phase3.md").read_text()
    for r in body((out / "tables" / "fastpath.tex").read_text()):
        tb, rest = r[0], r[1:]
        section = p3.split(f"## t_branch = {tb} ns")[1].split("## ")[0]
        if "| " + " | ".join(rest) + " |" not in section:
            bad.append(f"fastpath t_branch {tb}: {rest}")
    nums = dict(re.findall(r"\\newcommand\{\\(\w+)\}\{([^}]*)\}", (out / "numbers.tex").read_text()))
    sel = (ROOT / "results" / "phase4_selene.md").read_text()
    if f"{nums['nSeleneExact']} of {nums['nSeleneShots']}, over {nums['nSeleneVariants']}" not in sel:
        bad.append("selene shots")
    if f"{nums['nSeleneVariantsExact']} of {nums['nSeleneVariants']}" not in sel:
        bad.append("selene variants")
    ibm = (ROOT / "results" / "phase4_ibm.md").read_text()
    if f"slope: {nums['nIbmSlope']} us" not in ibm:
        bad.append("ibm slope")
    c6b = (ROOT / "results" / "phase7_c6b_analysis.txt").read_text()
    if (f"gap slope {nums['nCsixbMean']} us/copy, SE {nums['nCsixbSe']}, "
            f"95% CI {nums['nCsixbLo']} to {nums['nCsixbHi']}") not in c6b:
        bad.append("c6b gap")
    if (f"t test against {nums['nCsixbModel']}" not in c6b
            or f"p {nums['nCsixbTOneNineP']}" not in c6b
            or f"Wilcoxon against 0: p {nums['nCsixbWilcoxonP']}" not in c6b):
        bad.append("c6b tests")
    if f"complete rounds {nums['nCsixbRounds']}, rounds with both slopes {nums['nCsixbBoth']}, jobs dropped {nums['nCsixbDropped']}" not in c6b:
        bad.append("c6b rounds")
    model = (ROOT / "results" / "phase7_c6b_model.txt").read_text()
    if ("3450 source per shot (us)" not in model
            or f"slope {nums['nCsixbModelSource']} us/copy" not in model.split("3450 source")[1].splitlines()[0]
            or f"slope {nums['nCsixbModelDefer']} us/copy" not in model.split("3450 best_defer")[1].splitlines()[0]):
        bad.append("c6b model slopes")
    return bad


def test_tables_match_the_phase_reports(tmp_path):
    emit(tmp_path)
    assert len(body((tmp_path / "tables" / "defer.tex").read_text())) == 21
    assert mismatches(tmp_path) == []


def test_a_planted_wrong_value_is_caught(tmp_path):
    res = tmp_path / "results"
    shutil.copytree(ROOT / "results", res)
    csv = res / "phase2.csv"
    lines = csv.read_text().splitlines()
    i = next(k for k, x in enumerate(lines) if x.startswith("jeff/teleportation,600.0,ok"))
    f = lines[i].split(",")
    f[8] = "9999"  # best
    lines[i] = ",".join(f)
    csv.write_text("\n".join(lines) + "\n")
    out = tmp_path / "gen"
    emit(out, res)
    assert mismatches(out) == ["defer: | jeff/teleportation | 600 | 2 | 2090 | 2090 | 9999 | 1000 | 2 | 2 | 0 |"]


def test_a_planted_wrong_c6b_time_is_caught(tmp_path):
    res = tmp_path / "results"
    shutil.copytree(ROOT / "results", res)
    p = res / "phase7_c6b.json"
    rows = json.loads(p.read_text())
    for r in rows:
        if r["variant"] == "source_x8":
            r["times"] = [t + 50_000.0 for t in r["times"]]  # +50 us per shot
    p.write_text(json.dumps(rows))
    out = tmp_path / "gen"
    emit(out, res)
    # The shift moves the gap slope and, with it, both test p values.
    assert mismatches(out) == ["c6b gap", "c6b tests"]
