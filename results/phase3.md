# Phase 3 results

Model: block sync, HERON_LIKE (assumed values), t_ff = 600 ns. Latency is
expected makespan (ns) over exact outcome probabilities from |0...0>.

## G3

- Phase 2 search under block sync: 135 certified rows, 0 bound violations, 0 B&B mismatches.
- Every fast-path and sink variant in this sweep passed the simulation check: 282 variants (a failure stops the run). Also tests/fastpath.rs and tests/sink.rs (full job).
- Pitch decision at t_branch = 0: 0 benchmarks with gain >= 10% against the best baseline (method + bound + soundness).

## t_branch = 0 ns

| benchmark | best baseline | which | best ours | which | gain |
|---|---|---|---|---|---|
| dynamarq/repetition3_1_noisy | 2660 | best_defer | 2577 | sink_fast_t0 | 3.1% |
| dynamarq/repetition5_1_noisy | 3151 | source | 2851 | sink_fast_t0 | 9.5% |

Rows with no gain at this t_branch: 45.

## t_branch = 200 ns

| benchmark | best baseline | which | best ours | which | gain |
|---|---|---|---|---|---|
| dynamarq/five_qubit_code | 6486 | best_defer | 5459 | sink_fast_t5 | 15.8% |
| dynamarq/five_qubit_code_noisy | 6486 | best_defer | 5468 | sink_fast_t5 | 15.7% |
| dynamarq/repetition5_0_noisy | 5776 | bqcp | 3051 | fast_t4 | 47.2% |
| dynamarq/repetition5_1_noisy | 6148 | source | 3351 | fast_t4 | 45.5% |

Rows with no gain at this t_branch: 43.

## t_branch = 1000 ns

| benchmark | best baseline | which | best ours | which | gain |
|---|---|---|---|---|---|
| dynamarq/five_qubit_code | 18486 | best_defer | 7152 | fast_t4 | 61.3% |
| dynamarq/five_qubit_code_noisy | 18486 | best_defer | 7152 | fast_t5 | 61.3% |
| dynamarq/repetition5_0_noisy | 17776 | bqcp | 3851 | fast_t4 | 78.3% |
| dynamarq/repetition5_1_noisy | 18148 | source | 4151 | fast_t4 | 77.1% |

Rows with no gain at this t_branch: 43.

## Skipped

- dynamarq/steane: 14 qubits
- dynamarq/steane_noisy: 15 qubits
- jeff/qft-adder-quantum_7: 14 qubits
