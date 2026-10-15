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

Verdict: not resolved. The 95% interval of the gap contains both 0 and the
model's 19 us.

| quantity | this run (60 pairs) | pooled with 2026-09-29 (87 pairs) |
|---|---|---|
| pairs dropped (\|d\| > 1000 us) | 0 | 2 |
| mean gap, source - best_defer (us) | 21.06 | 14.00 |
| SE (us) | 15.41 | 11.33 |
| 95% CI (us) | -9.77 to 51.90 | -8.52 to 36.53 |
| t test against 19 us, p | 0.89 | 0.66 |
| Wilcoxon against 0, p (median, us) | 0.73 (-1.88) | 0.66 (-1.90) |
| Shapiro-Wilk on kept pairs, p | < 0.0001 | < 0.0001 |

- Design: 60 interleaved rounds. Each round runs a source job, then a
  best_defer job, with 1000 shots each. A 100-shot smoke job ran first.
  All 60 rounds completed.
- The 2026-09-29 run gave a weak hint that 19 us is too large (p 0.046,
  post hoc outlier rule). This run does not repeat it.
- The differences are not normal, so the t tests are weak evidence.
- Next design: notes/c6b-prereg.txt. It repeats the program body k times
  per circuit, so the gap grows with k.
