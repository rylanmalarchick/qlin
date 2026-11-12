"""The paper tables agree with the phase reports.

bench/paper_tables.py computes tables from results/*.csv and *.json. The
phase runners wrote results/*.md from the same runs with separate code.
Each emitted value is compared with its report line.
"""

import csv
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
    sw = (ROOT / "results" / "phase8_switch.md").read_text()
    for c in ("none", "qubic", "qick", "ibm"):
        cc = c.capitalize()
        for s in ("table", "tree", "chain"):
            key = f"nSwitch{cc}{s.capitalize()}"
            if f"{key}Ten" not in nums:
                continue
            want = (f"| {c} | {nums[f'nSwitch{cc}Tb']} | {s} | {nums[key + 'Pos']} | "
                    f"{nums[key + 'Ten']} | {nums[key + 'Max']}% (")
            if want not in sw:
                bad.append(f"switch {c} {s}")
    qb = (ROOT / "results" / "qubic_dispatch.md").read_text()
    if f"largest absolute residual {nums['nQubicResid']} cycles" not in qb:
        bad.append("qubic residual")
    kinds = {l.split("|")[1].strip(): float(l.split("|")[2]) for l in qb.splitlines()
             if l.startswith("| cond_") or l.startswith("| jump ")}
    if (f"{kinds['cond_taken']:.1f}" != nums["nQubicCond"]
            or f"{kinds['jump']:.1f}" != nums["nQubicJump"]):
        bad.append("qubic cycles per kind")
    rows = {tuple(c.strip() for c in l.split("|")[1:6]): l.split("|")[6].strip()
            for l in qb.splitlines() if l.startswith("| dynamarq/")}
    for b, v, key in [("repetition5_1_noisy", "source", "nQubicRepSource"),
                      ("repetition5_1_noisy", "chain", "nQubicRepChain"),
                      ("five_qubit_code_noisy", "source", "nQubicFiveSource"),
                      ("five_qubit_code_noisy", "tree", "nQubicFiveTree")]:
        if f"{float(rows[(f'dynamarq/{b}', '2', '4', '11', v)]):.1f}" != nums[key]:
            bad.append(f"qubic {b} {v}")
    fs = (ROOT / "results" / "phase8_full.md").read_text().splitlines()
    summary = [l.split("|") for l in fs
               if l.startswith("| ") and l.split("|")[3].strip() in ("table", "tree")
               and l.split("|")[1].strip() in ("none", "qubic", "qick", "ibm")]
    if f"{max(float(c[8].split('%')[0]) for c in summary):.1f}" != nums["nFullTabtreeMax"]:
        bad.append("full table/tree margin")
    margin = {l.split("|")[1].strip(): l.split("|")[7].strip() for l in fs
              if l.split("|")[2:4] == [" ibm ", " chain "]}
    if margin.get("dynamarq/steane_noisy") != f"{nums['nFullSteaneMargin']}%":
        bad.append("full steane margin")
    budget = next(l for l in fs if l.startswith("| qec/repetition11_0_noisy | 10 |"))
    for want in (f"{nums['nFullRepFull']}% ({nums['nFullRepFullCases']})",
                 f"t=2: {nums['nFullRepTwo']}% ({nums['nFullRepTwoCases']})",
                 f"t=4: {nums['nFullRepFour']}% ({nums['nFullRepFourCases']})"):
        if want not in budget:
            bad.append(f"full budget {want}")
    ns = (ROOT / "results" / "phase8_noise.md").read_text()
    qick = ns[ns.index("## qick"):]
    counts = next(l for l in qick.splitlines() if l.startswith("| programs |"))
    if {c.strip() for c in counts.split("|")[2:-1]} != {nums["nNoiseQickTenLo"], nums["nNoiseQickTenHi"]}:
        bad.append("noise qick counts")
    rep11 = next(l for l in qick.splitlines() if l.startswith("| qec/repetition11_0_noisy |"))
    cells = [c.strip() for c in rep11.split("|")[3:-1]]
    if (not cells[0].endswith(f"; {nums['nNoiseRepTwoLoP']}%")
            or not cells[-1].endswith(f"; {nums['nNoiseRepTwoHiP']}%")):
        bad.append("noise rep11 t=2")
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


def test_a_planted_wrong_switch_gain_is_caught(tmp_path):
    res = tmp_path / "results"
    shutil.copytree(ROOT / "results", res)
    p = res / "phase8_switch.csv"
    lines = p.read_text().splitlines()
    head = lines[0].split(",")
    col = {k: i for i, k in enumerate(head)}
    for i, line in enumerate(lines[1:], 1):
        f = line.split(",")
        if (f[col["benchmark"]], f[col["class"]], f[col["switch"]]) == (
                "qec/repetition11_0_noisy", "qick", "tree"):
            f[col["gain"]] = "0.5"
            lines[i] = ",".join(f)
    p.write_text("\n".join(lines) + "\n")
    out = tmp_path / "gen"
    emit(out, res)
    # The largest QICK tree gain falls from 91.2% (this row) to 90.7%.
    assert mismatches(out) == ["switch qick tree"]


def test_a_planted_wrong_qubic_cycle_count_is_caught(tmp_path):
    res = tmp_path / "results"
    shutil.copytree(ROOT / "results", res)
    p = res / "qubic_dispatch.json"
    d = json.loads(p.read_text())
    for r in d["rows"]:
        if (r["benchmark"], r["t"], r["variant"]) == ("dynamarq/repetition5_1_noisy", 2, "chain"):
            r["expected_cycles"] = 99.0
    p.write_text(json.dumps(d))
    out = tmp_path / "gen"
    emit(out, res)
    assert mismatches(out) == ["qubic repetition5_1_noisy chain"]


def test_a_planted_wrong_full_switch_value_is_caught(tmp_path):
    res = tmp_path / "results"
    shutil.copytree(ROOT / "results", res)
    p = res / "phase8_full.csv"
    rows = list(csv.DictReader(open(p)))
    for r in rows:
        if (r["benchmark"], r["class"], r["switch"]) == ("dynamarq/steane_noisy", "ibm", "chain"):
            r["nosink_margin"] = "0.5"
    with open(p, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    out = tmp_path / "gen"
    emit(out, res)
    assert mismatches(out) == ["full steane margin"]


def test_a_planted_wrong_noise_value_is_caught(tmp_path):
    res = tmp_path / "results"
    shutil.copytree(ROOT / "results", res)
    p = res / "phase8_noise.csv"
    rows = list(csv.DictReader(open(p)))
    for r in rows:
        if (r["benchmark"], r["class"], r["p"]) == ("qec/repetition11_0_noisy", "qick", "0.1"):
            r["gain_t2"] = "0.5"
    with open(p, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    out = tmp_path / "gen"
    emit(out, res)
    assert mismatches(out) == ["noise rep11 t=2"]
