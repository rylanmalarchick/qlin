# Phase 4 IBM run (measured)

Backend ibm_kingston, 2026-10-14.
Model durations from the backend target (ns): {'t1q': 32.0, 't2q': 68.0, 'tmeas': 1380.0, 'treset': 2212.0}, t_ff 600.
1000 shots per job, up to 60 jobs per circuit. Measured time per shot is the
execution-span total over the shots, so it includes the repetition delay,
which is the same for every circuit.

## Branch-cost probe

| if_else blocks | per shot (us), mean +- sd |
|---|---|

## Benchmark variants

| benchmark | variant | model ideal (ns) | model block (ns) | measured per shot (us) | note |
|---|---|---|---|---|---|
| benchmarks/dynamarq/five_qubit_code.qlin | source | 5764 | 6854 | 1202.55 +- 111.59 |  |
| benchmarks/dynamarq/five_qubit_code.qlin | best_defer | 4688 | 4922 | 1181.48 +- 52.65 |  |

## Rank correlation (Spearman, per benchmark, measured means)

- benchmarks/dynamarq/five_qubit_code.qlin: 2 variants measured, too few for a rank correlation

## Interpretation (2026-10-14, analysis fixed in notes/c6-prereg.txt)

- Design: 60 interleaved rounds (source job, then best_defer job), 1000
  shots each, one 100-shot smoke job first. All 60 rounds completed.
- Analysis (bench/analyze_c6.py, outlier rule |d| > 1000 us fixed before
  the run): 0 pairs dropped. Mean difference source - best_defer
  21.06 us, SE 15.41, 95% CI -9.77 to 51.90 us. t test against the model's
  19 us: p 0.89. Wilcoxon against 0: median -1.88 us, p 0.73.
  Shapiro-Wilk on the differences: p < 0.0001.
- Verdict by the plan: not resolved. The interval contains both 0 and the
  model's 19 us. The 2026-09-29 run's weak hint that 19 us is too large
  (p 0.046, post hoc outlier rule) does not hold here.
- Pooled with the 2026-09-29 run (secondary, 87 pairs, 2 dropped): mean
  14.00 us, 95% CI -8.52 to 36.53, not resolved.
- Next design: notes/c6b-prereg.txt (the body repeated k times per
  circuit, so the gap grows with k).
