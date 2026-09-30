"""Paper tables and number macros, computed from results/.

Run: uv run --project bench python bench/paper_tables.py [OUT_DIR]
OUT_DIR defaults to paper/generated. Writes tables/*.tex (booktabs) and
numbers.tex (one \\newcommand per number the text quotes). Every value
comes from a file in results/. Nothing is typed in by hand.
"""

from __future__ import annotations

import csv
import json
import os
import statistics as st
import sys
from pathlib import Path

from scipy import stats

ROOT = Path(__file__).resolve().parent.parent
RESULTS = Path(os.environ.get("QLIN_RESULTS", ROOT / "results"))
PIPELINES = ["bqcp", "qiskit_o0", "qiskit_o3", "tket"]
# TeX command names are letters only.
DIGITS = dict(zip("0123456789", ["Zero", "One", "Two", "Three", "Four", "Five", "Six",
                                 "Seven", "Eight", "Nine"]))


def rows(name: str) -> list[dict]:
    with open(RESULTS / name) as f:
        return list(csv.DictReader(f))


def tex_name(bench: str) -> str:
    return r"\texttt{" + bench.replace("_", r"\_") + "}"


def ns(x: str | float) -> str:
    return f"{float(x):.0f}"


def baselines() -> tuple[str, dict]:
    """Per pipeline: benchmarks that ran and passed the semantics guard, and
    on how many of them feedforward (ff) and the branch core shrink."""
    data = rows("phase1.csv")
    src = {r["benchmark"]: r for r in data if r["pipeline"] == "source"}
    lines, nums = [], {"benchmarks": len(src)}
    for p in PIPELINES:
        ok = [r for r in data if r["pipeline"] == p and r["status"] == "ok" and r["guard"] == "match"]
        ff = sum(int(r["feedforward"]) < int(src[r["benchmark"]]["feedforward"]) for r in ok)
        core = sum(int(r["core_branch"]) < int(src[r["benchmark"]]["core_branch"]) for r in ok)
        more = sum(int(r["dynamic_ops"]) > int(src[r["benchmark"]]["dynamic_ops"]) for r in ok)
        lines.append(f"{p.replace('_', r'\_')} & {len(ok)} & {ff} & {core} & {more} \\\\")
        nums[p] = {"ok": len(ok), "ff": ff, "core": core, "more_dyn": more}
    body = "\n".join(lines)
    tab = (r"\begin{tabular}{lrrrr}" "\n" r"\toprule" "\n"
           r"pipeline & ran & fewer ff & smaller core & more dyn \\" "\n" r"\midrule" "\n"
           f"{body}\n" r"\bottomrule" "\n" r"\end{tabular}" "\n")
    return tab, nums


def defer_table() -> tuple[str, dict]:
    """Phase 2 rows at t_ff = 600 ns with at least one defer candidate."""
    data = rows("phase2.csv")
    ok = [r for r in data if r["status"] == "ok"]
    sel = [r for r in ok if float(r["tff"]) == 600 and int(r["candidates"] or 0) > 0]
    lines = []
    for r in sorted(sel, key=lambda r: r["benchmark"]):
        lines.append(" & ".join([tex_name(r["benchmark"]), r["candidates"], ns(r["source"]),
                                 ns(r["m0"]), ns(r["best"]), ns(r["floor"]), r["deferred"],
                                 r["added_2q"], r["added_qubits"]]) + r" \\")
    certified = [r for r in ok if r["ex_leaves"] not in ("", "0")]
    nums = {"rows": len(ok), "certified": len(certified),
            "bnb_match": sum(r["bnb_matches"] == "True" for r in certified),
            "violations": sum(int(r["bound_violations"] or 0) for r in ok),
            "checked": sum(int(r["leaves_checked"] or 0) for r in ok if float(r["tff"]) == 600),
            "unchecked": sum(int(r["leaves_unchecked"] or 0) for r in ok if float(r["tff"]) == 600),
            "defer_wins_600": sum(float(r["best"]) < float(r["m0"]) for r in sel)}
    tab = (r"\begin{tabular}{lrrrrrrrr}" "\n" r"\toprule" "\n"
           r"benchmark & cand. & source & M0 & best & floor & deferred & +2q & +q \\" "\n"
           r"\midrule" "\n" + "\n".join(lines) + "\n" r"\bottomrule" "\n" r"\end{tabular}" "\n")
    return tab, nums


def fastpath_table() -> tuple[str, dict]:
    """Phase 3 rows with a gain over the best baseline, per t_branch."""
    data = rows("phase3.csv")
    lines, nums = [], {}
    for tb in sorted({float(r["tbranch"]) for r in data}):
        sel = [r for r in data if float(r["tbranch"]) == tb and r["gain"] and float(r["gain"]) > 0]
        nums[f"tb{tb:.0f}"] = {"gain_rows": len(sel),
                               "ge10": sum(float(r["gain"]) >= 0.10 for r in sel)}
        for r in sorted(sel, key=lambda r: r["benchmark"]):
            lines.append(" & ".join([f"{tb:.0f}", tex_name(r["benchmark"]), ns(r["best_baseline"]),
                                     r["best_baseline_is"].replace("_", r"\_"), ns(r["best_ours"]),
                                     r["best_ours_is"].replace("_", r"\_"),
                                     f"{100 * float(r['gain']):.1f}\\%"]) + r" \\")
    nums["rows"] = len(data)
    tab = (r"\begin{tabular}{rlrlrlr}" "\n" r"\toprule" "\n"
           r"$t_\mathrm{branch}$ & benchmark & best baseline & which & ours & which & gain \\" "\n"
           r"\midrule" "\n" + "\n".join(lines) + "\n" r"\bottomrule" "\n" r"\end{tabular}" "\n")
    return tab, nums


def selene() -> dict:
    d = json.loads((RESULTS / "phase4_selene.json").read_text())
    return {"variants": len(d), "benchmarks": len({r["benchmark"] for r in d}),
            "shots": sum(r["shots"] for r in d), "exact": sum(r["exact"] for r in d),
            "variants_exact": sum(r["exact"] == r["shots"] for r in d)}


def ibm() -> tuple[str, dict]:
    probe = [r for r in json.loads((RESULTS / "phase4_ibm.json").read_text())
             if r["benchmark"] == "branch_probe"]
    pts = [(r["k"], t / 1000) for r in probe for t in r["times"]]
    fit = stats.linregress([k for k, _ in pts], [y for _, y in pts])
    q = stats.t.ppf(0.975, len(pts) - 2)
    n27 = {r["variant"]: [t / 1000 for t in r["times"]]
           for r in json.loads((RESULTS / "phase4_ibm_five_qubit_n27.json").read_text())}
    d = [a - b for a, b in zip(n27["source"], n27["best_defer"])]
    keep = [x for x in d if abs(x) < 1000]
    se = st.stdev(keep) / len(keep) ** 0.5
    qk = stats.t.ppf(0.975, len(keep) - 1)
    nums = {"probe_points": len(pts), "slope": fit.slope,
            "slope_lo": fit.slope - q * fit.stderr, "slope_hi": fit.slope + q * fit.stderr,
            "pairs": len(d), "kept": len(keep), "kept_mean": st.mean(keep), "kept_se": se,
            "kept_lo": st.mean(keep) - qk * se, "kept_hi": st.mean(keep) + qk * se,
            "median": st.median(d), "wilcoxon_p": stats.wilcoxon(d).pvalue,
            "t19_p": stats.ttest_1samp(keep, 19).pvalue,
            "normal_p": stats.shapiro(keep).pvalue}
    lines = [f"{r['k']} & {len(r['times'])} & {st.mean(r['times']) / 1000:.2f} & "
             f"{st.stdev(r['times']) / 1000:.2f} \\\\" for r in probe]
    tab = (r"\begin{tabular}{rrrr}" "\n" r"\toprule" "\n"
           r"if\_else blocks & jobs & mean per shot ($\mu$s) & sd ($\mu$s) \\" "\n" r"\midrule" "\n"
           + "\n".join(lines) + "\n" r"\bottomrule" "\n" r"\end{tabular}" "\n")
    return tab, nums


def macros(prefix: str, d: dict, fmt: dict[str, str] | None = None) -> list[str]:
    """One \\newcommand per scalar, named prefix + key in camel case."""
    out = []
    for k, v in d.items():
        if isinstance(v, dict):
            out += macros(prefix + "".join(p.capitalize() for p in k.split("_")), v, fmt)
            continue
        name = prefix + "".join(p.capitalize() for p in str(k).split("_"))
        name = "".join(c if c.isalpha() else DIGITS.get(c, "") for c in name)
        val = f"{v:{(fmt or {}).get(k, '.2f')}}" if isinstance(v, float) else str(v)
        out.append(f"\\newcommand{{\\{name}}}{{{val}}}")
    return out


def main(out: Path) -> None:
    (out / "tables").mkdir(parents=True, exist_ok=True)
    t1, n1 = baselines()
    t2, n2 = defer_table()
    t3, n3 = fastpath_table()
    t4, n4 = ibm()
    for name, tab in [("baselines", t1), ("defer", t2), ("fastpath", t3), ("ibm_probe", t4)]:
        (out / "tables" / f"{name}.tex").write_text(tab)
    fmt = {"wilcoxon_p": ".2f", "t19_p": ".3f", "normal_p": ".3f"}
    lines = (["% Generated by bench/paper_tables.py from results/. Do not edit."]
             + macros("nBase", n1) + macros("nDefer", n2) + macros("nFast", n3)
             + macros("nSelene", selene()) + macros("nIbm", n4, fmt))
    (out / "numbers.tex").write_text("\n".join(lines) + "\n")
    print(f"wrote {out}/tables/*.tex and numbers.tex ({len(lines) - 1} macros)")


if __name__ == "__main__":
    main(Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "paper" / "generated")
