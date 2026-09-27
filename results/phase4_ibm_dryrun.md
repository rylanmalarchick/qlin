# Phase 4 IBM run (dry run, nothing measured)

Backend fake_kingston, 2026-09-27.
Model durations from the backend target (ns): {'t1q': 32.0, 't2q': 68.0, 'tmeas': 1760.0, 'treset': 2312.0}, t_ff 600.

| benchmark | variant | model ideal | model block | depth | measured per shot |
|---|---|---|---|---|---|
| benchmarks/jeff/teleportation.qlin | source | 3770 | 4368 | 18 | - |
| benchmarks/jeff/teleportation.qlin | best_defer | 2096 | 2096 | 23 | - |
| benchmarks/jeff/teleportation.qlin | fast_t1 | 4384 | 4384 | 13 | - |
| benchmarks/jeff/teleportation.qlin | sink_fast_t1 | 4352 | 4352 | 13 | - |
| benchmarks/dynamarq/five_qubit_code.qlin | source | 6738 | 7994 | 182 | - |
| benchmarks/dynamarq/five_qubit_code.qlin | best_defer | 5425 | 5682 | 214 | - |
| benchmarks/dynamarq/five_qubit_code.qlin | fast_t1 | 7526 | 8026 | 94 | - |
| benchmarks/dynamarq/five_qubit_code.qlin | sink_fast_t1 | 6981 | 7352 | 112 | - |
| benchmarks/dynamarq/repetition5_0.qlin | source | 2404 | 4764 | 59 | - |
| benchmarks/dynamarq/repetition5_0.qlin | best_defer | 2404 | 4764 | 59 | - |
| benchmarks/dynamarq/repetition5_0.qlin | fast_t1 | 4764 | 4764 | 44 | - |
| benchmarks/dynamarq/repetition5_0.qlin | sink_fast_t1 | 4764 | 4764 | 44 | - |
