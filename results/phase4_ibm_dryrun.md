# Phase 4 IBM run (dry run, nothing measured)

Backend fake_kingston, 2026-09-27.
Model durations from the backend target (ns): {'t1q': 32.0, 't2q': 68.0, 'tmeas': 1760.0, 'treset': 2312.0}, t_ff 600.
1000 shots per job, 3 jobs per circuit. Measured time per shot is the
execution-span total over the shots, so it includes the repetition delay,
which is the same for every circuit.

## Branch-cost probe

| if_else blocks | per shot (us), mean +- sd |
|---|---|
| 0 | - |
| 1 | - |
| 2 | - |
| 4 | - |
| 8 | - |

## Benchmark variants

| benchmark | variant | model ideal (ns) | model block (ns) | measured per shot (us) | note |
|---|---|---|---|---|---|
| benchmarks/jeff/teleportation.qlin | source | 3770 | 4368 | - |  |
| benchmarks/jeff/teleportation.qlin | best_defer | 2096 | 2096 | - |  |
| benchmarks/jeff/teleportation.qlin | sink_only | 3746 | 4336 | - |  |
| benchmarks/jeff/teleportation.qlin | fast_t1 | 4384 | 4384 | - | measure inside a conditional |
| benchmarks/jeff/teleportation.qlin | sink_fast_t1 | 4352 | 4352 | - | measure inside a conditional |
| benchmarks/dynamarq/five_qubit_code.qlin | source | 6738 | 7994 | - |  |
| benchmarks/dynamarq/five_qubit_code.qlin | best_defer | 5425 | 5682 | - |  |
| benchmarks/dynamarq/five_qubit_code.qlin | sink_only | 6343 | 7352 | - |  |
| benchmarks/dynamarq/five_qubit_code.qlin | fast_t1 | 7526 | 8026 | - | measure inside a conditional |
| benchmarks/dynamarq/five_qubit_code.qlin | sink_fast_t1 | 6981 | 7352 | - | measure inside a conditional |
| benchmarks/dynamarq/repetition5_0.qlin | source | 2404 | 4764 | - |  |
| benchmarks/dynamarq/repetition5_0.qlin | best_defer | 2404 | 4764 | - |  |
| benchmarks/dynamarq/repetition5_0.qlin | sink_only | 2404 | 4764 | - |  |
| benchmarks/dynamarq/repetition5_0.qlin | fast_t1 | 4764 | 4764 | - | measure inside a conditional |
| benchmarks/dynamarq/repetition5_0.qlin | sink_fast_t1 | 4764 | 4764 | - | measure inside a conditional |
