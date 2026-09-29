# Phase 4 IBM run (measured)

Backend ibm_kingston, 2026-09-28.
Model durations from the backend target (ns): {'t1q': 32.0, 't2q': 68.0, 'tmeas': 1380.0, 'treset': 2212.0}, t_ff 600.
1000 shots per job, 3 jobs per circuit. Measured time per shot is the
execution-span total over the shots, so it includes the repetition delay,
which is the same for every circuit.

## Branch-cost probe

| if_else blocks | per shot (us), mean +- sd |
|---|---|

## Benchmark variants

| benchmark | variant | model ideal (ns) | model block (ns) | measured per shot (us) | note |
|---|---|---|---|---|---|
| benchmarks/dynamarq/five_qubit_code.qlin | source | 5764 | 6854 | 1154.53 +- 15.38 |  |
| benchmarks/dynamarq/five_qubit_code.qlin | best_defer | 4688 | 4922 | 1148.33 +- 35.52 |  |

## Rank correlation (Spearman, per benchmark, measured means)

- benchmarks/dynamarq/five_qubit_code.qlin: 2 variants measured, too few for a rank correlation

## Interpretation (2026-09-28)

- The no-alias register layout fixes IBM error 1500: all 7 jobs ran (1
  smoke job of 100 shots, then 3 x 1000 shots per variant). 14 s of
  device time.
- Measured difference source - best_defer: 6.2 us per shot, standard
  error about 22 us (3 jobs each). Not resolved.
- Model at the measured branch cost (t_branch 3.45 us, Block model):
  source about 75 us, best defer about 56 us of circuit time, a 19 us gap.
  The measurement is consistent with 0 and with 19 us.
- Power: resolving 19 us at this job noise (80% power, 5% level) needs
  about 27 jobs per variant, about 110 s of Open Plan time. Not run.
