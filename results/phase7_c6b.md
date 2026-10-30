# Phase 4 IBM run (measured)

Backend ibm_kingston, 2026-10-30.
Model durations from the backend target (ns): {'t1q': 32.0, 't2q': 68.0, 'tmeas': 1380.0, 'treset': 2212.0}, t_ff 600.
1000 shots per job, up to 15 jobs per circuit. Measured time per shot is the
execution-span total over the shots, so it includes the repetition delay,
which is the same for every circuit.

## Branch-cost probe

| if_else blocks | per shot (us), mean +- sd |
|---|---|

## Benchmark variants

| benchmark | variant | model ideal (ns) | model block (ns) | measured per shot (us) | note |
|---|---|---|---|---|---|
| benchmarks/dynamarq/five_qubit_code.qlin | source_x1 | 5764 | 6854 | 1373.76 +- 673.05 |  |
| benchmarks/dynamarq/five_qubit_code.qlin | best_defer_x1 | 4688 | 4922 | 1199.61 +- 97.80 |  |
| benchmarks/dynamarq/five_qubit_code.qlin | source_x2 | 13416 | 15584 | 1219.01 +- 38.85 |  |
| benchmarks/dynamarq/five_qubit_code.qlin | best_defer_x2 | 11247 | 11720 | 1443.11 +- 568.56 |  |
| benchmarks/dynamarq/five_qubit_code.qlin | source_x4 | 28653 | 33044 | 1303.25 +- 73.85 |  |
| benchmarks/dynamarq/five_qubit_code.qlin | best_defer_x4 | 24361 | 25315 | 1334.80 +- 77.54 |  |
| benchmarks/dynamarq/five_qubit_code.qlin | source_x8 | 59142 | 67961 | 1655.20 +- 657.31 |  |
| benchmarks/dynamarq/five_qubit_code.qlin | best_defer_x8 | 50613 | 52506 | 1649.44 +- 652.92 |  |

## Rank correlation (Spearman, per benchmark, measured means)

- benchmarks/dynamarq/five_qubit_code.qlin: ideal +0.62, block +0.62 (n = 8)
