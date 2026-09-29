# Phase 4 IBM run (measured)

Backend ibm_kingston, 2026-09-29.
Model durations from the backend target (ns): {'t1q': 32.0, 't2q': 68.0, 'tmeas': 1380.0, 'treset': 2212.0}, t_ff 600.
1000 shots per job, up to 27 jobs per circuit. Measured time per shot is the
execution-span total over the shots, so it includes the repetition delay,
which is the same for every circuit.

## Branch-cost probe

| if_else blocks | per shot (us), mean +- sd |
|---|---|

## Benchmark variants

| benchmark | variant | model ideal (ns) | model block (ns) | measured per shot (us) | note |
|---|---|---|---|---|---|
| benchmarks/dynamarq/five_qubit_code.qlin | source | 5764 | 6854 | 1328.19 +- 631.75 |  |
| benchmarks/dynamarq/five_qubit_code.qlin | best_defer | 4688 | 4922 | 1162.05 +- 41.73 |  |

## Rank correlation (Spearman, per benchmark, measured means)

- benchmarks/dynamarq/five_qubit_code.qlin: 2 variants measured, too few for a rank correlation

## Interpretation (2026-09-29)

- Design: 27 rounds, each round runs one source job, then one best_defer
  job (interleaved, so device drift affects both alike). 1 smoke job of
  100 shots first. 55 jobs, about 110 s of Open Plan time.
- Two source jobs are outliers: 3199 us (round 12) and 3793 us (round 24)
  per shot, against a median of 1154 us. In round 12 the best_defer job
  was also slow (1270 us). The spans do not say why.
- All 27 pairs: difference source - best_defer 166 +- 119 us (paired t,
  p = 0.17). Wilcoxon signed-rank, robust to the outliers: median
  difference -5.4 us, p = 0.86.
- Without the two outlier pairs (a post hoc rule: |difference| > 1000
  us): -3.0 +- 10.4 us, 95% CI -24.5 to 18.6 us, n = 25.
- Model at the measured branch cost (t_branch 3.45 us, Block model):
  about 19 us. The CI without outliers just excludes it (t test against
  19 us, p = 0.046). That result depends on the post hoc outlier rule,
  so it is weak evidence, not a refutation.
- Conclusion: no measurable time difference between source and
  best_defer on ibm_kingston. The measured gap is smaller than the
  model predicts, at the edge of significance. The model's ranking
  (defer faster) is not confirmed.
