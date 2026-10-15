# Phase 7.2 results: benchmarks past 12 qubits

Model: block sync, HERON_LIKE (assumed values), t_ff = 600 ns. Latency is
expected makespan (ns) over exact outcome probabilities from |0...0>, from
the stabilizer backend. Every fast-path and sink variant passed the
stabilizer check: 196 variants (a failure stops the run).

## t_branch = 0 ns

| benchmark | qubits | best baseline | which | best ours | which | gain |
|---|---|---|---|---|---|---|
| dynamarq/steane | 14 | 1916 | bqcp | 3248 | sink_fast_t0 | -69.5% |
| dynamarq/steane_noisy | 15 | 3789 | source | 3248 | sink_fast_t0 | 14.3% |
| qec/repetition11_0 | 21 | 832 | bqcp | 3660 | fast_t0 | -339.9% |
| qec/repetition11_0_noisy | 22 | 3606 | bqcp | 3674 | fast_t0 | -1.9% |
| qec/repetition11_1 | 21 | 2172 | bqcp | 3660 | sink_fast_t0 | -68.5% |
| qec/repetition11_1_noisy | 22 | 4375 | source | 3674 | sink_fast_t0 | 16.0% |
| qec/repetition7_0 | 13 | 832 | bqcp | 3116 | fast_t0 | -274.5% |
| qec/repetition7_0_noisy | 14 | 3058 | bqcp | 3126 | fast_t0 | -2.2% |
| qec/repetition7_1 | 13 | 1356 | bqcp | 3116 | sink_fast_t0 | -129.8% |
| qec/repetition7_1_noisy | 14 | 3559 | source | 3126 | sink_fast_t0 | 12.2% |
| qec/repetition9_0 | 17 | 832 | bqcp | 3388 | fast_t0 | -307.2% |
| qec/repetition9_0_noisy | 18 | 3332 | bqcp | 3400 | fast_t0 | -2.0% |
| qec/repetition9_1 | 17 | 1764 | bqcp | 3388 | sink_fast_t0 | -92.1% |
| qec/repetition9_1_noisy | 18 | 3967 | source | 3400 | sink_fast_t0 | 14.3% |

## t_branch = 200 ns

| benchmark | qubits | best baseline | which | best ours | which | gain |
|---|---|---|---|---|---|---|
| dynamarq/steane | 14 | 1916 | bqcp | 3988 | fast_t0 | -108.1% |
| dynamarq/steane_noisy | 15 | 5980 | source | 3989 | fast_t3 | 33.3% |
| qec/repetition11_0 | 21 | 832 | bqcp | 3860 | fast_t0 | -363.9% |
| qec/repetition11_0_noisy | 22 | 208192 | bqcp | 3929 | fast_t6 | 98.1% |
| qec/repetition11_1 | 21 | 2172 | bqcp | 4060 | sink_fast_t0 | -86.9% |
| qec/repetition11_1_noisy | 22 | 208972 | source | 4189 | sink_fast_t6 | 98.0% |
| qec/repetition7_0 | 13 | 832 | bqcp | 3316 | fast_t0 | -298.6% |
| qec/repetition7_0_noisy | 14 | 15648 | bqcp | 3326 | fast_t6 | 78.7% |
| qec/repetition7_1 | 13 | 1356 | bqcp | 3516 | sink_fast_t0 | -159.3% |
| qec/repetition7_1_noisy | 14 | 16156 | source | 3521 | sink_fast_t6 | 78.2% |
| qec/repetition9_0 | 17 | 832 | bqcp | 3588 | fast_t0 | -331.2% |
| qec/repetition9_0_noisy | 18 | 54320 | bqcp | 3602 | fast_t6 | 93.4% |
| qec/repetition9_1 | 17 | 1764 | bqcp | 3788 | sink_fast_t0 | -114.7% |
| qec/repetition9_1_noisy | 18 | 54964 | source | 3823 | sink_fast_t6 | 93.0% |

## t_branch = 1000 ns

| benchmark | qubits | best baseline | which | best ours | which | gain |
|---|---|---|---|---|---|---|
| dynamarq/steane | 14 | 1916 | bqcp | 4788 | fast_t0 | -149.9% |
| dynamarq/steane_noisy | 15 | 17144 | source | 4789 | fast_t3 | 72.1% |
| qec/repetition11_0 | 21 | 832 | bqcp | 4660 | fast_t0 | -460.1% |
| qec/repetition11_0_noisy | 22 | 1026592 | bqcp | 4949 | fast_t6 | 99.5% |
| qec/repetition11_1 | 21 | 2172 | bqcp | 5372 | fast_t0 | -147.3% |
| qec/repetition11_1_noisy | 22 | 1027372 | source | 5651 | fast_t6 | 99.4% |
| qec/repetition7_0 | 13 | 832 | bqcp | 4116 | fast_t0 | -394.7% |
| qec/repetition7_0_noisy | 14 | 66048 | bqcp | 4126 | fast_t6 | 93.8% |
| qec/repetition7_1 | 13 | 1356 | bqcp | 4556 | fast_t0 | -236.0% |
| qec/repetition7_1_noisy | 14 | 66556 | source | 4559 | fast_t6 | 93.1% |
| qec/repetition9_0 | 17 | 832 | bqcp | 4388 | fast_t0 | -427.4% |
| qec/repetition9_0_noisy | 18 | 258320 | bqcp | 4412 | fast_t6 | 98.3% |
| qec/repetition9_1 | 17 | 1764 | bqcp | 4964 | fast_t0 | -181.4% |
| qec/repetition9_1_noisy | 18 | 258964 | source | 4979 | fast_t6 | 98.1% |

## Baselines (guarded by qlin check from |0...0>)

- dynamarq/steane bqcp: checked
- dynamarq/steane qiskit_o3: 14 qubits, not a stabilizer program
- dynamarq/steane_noisy bqcp: checked
- dynamarq/steane_noisy qiskit_o3: 15 qubits, not a stabilizer program
- qec/repetition11_0 bqcp: checked
- qec/repetition11_0 qiskit_o3: checked
- qec/repetition11_0_noisy bqcp: checked
- qec/repetition11_0_noisy qiskit_o3: checked
- qec/repetition11_1 bqcp: checked
- qec/repetition11_1 qiskit_o3: checked
- qec/repetition11_1_noisy bqcp: checked
- qec/repetition11_1_noisy qiskit_o3: checked
- qec/repetition7_0 bqcp: checked
- qec/repetition7_0 qiskit_o3: checked
- qec/repetition7_0_noisy bqcp: checked
- qec/repetition7_0_noisy qiskit_o3: checked
- qec/repetition7_1 bqcp: checked
- qec/repetition7_1 qiskit_o3: checked
- qec/repetition7_1_noisy bqcp: checked
- qec/repetition7_1_noisy qiskit_o3: checked
- qec/repetition9_0 bqcp: checked
- qec/repetition9_0 qiskit_o3: checked
- qec/repetition9_0_noisy bqcp: checked
- qec/repetition9_0_noisy qiskit_o3: checked
- qec/repetition9_1 bqcp: checked
- qec/repetition9_1 qiskit_o3: checked
- qec/repetition9_1_noisy bqcp: checked
- qec/repetition9_1_noisy qiskit_o3: checked

## Skipped

- jeff/qft-adder-quantum_7: qlin lat /home/rylan/dev/projects/qlin/.claude/worktrees/scale-stab/benchmarks/jeff/qft-adder-quantum_7.qlin: 14 qubits is more than the limit of 12

## Interpretation (2026-10-14)

- Noiseless codes: from |0...0> every syndrome is 0, so bqcp removes every
  correction and wins (as in Phase 1). Read the QEC results on the _noisy
  variants only.
- t_branch = 0 (no assumed branch overhead): the Pauli sink beats the best
  baseline by 12.2% (repetition7_1_noisy), 14.3% (repetition9_1_noisy),
  16.0% (repetition11_1_noisy), and 14.3% (steane_noisy), modeled. These
  are the |+> codes, where corrections pass the unencoding Cliffords. On
  the _0_noisy codes bqcp is 1.9 to 2.2% faster than ours. The gain at
  t_branch = 0 grows with d (repetition5_1_noisy: 9.5% in Phase 3).
- t_branch = 200 and 1000 ns: 33 to 99.5%. The source's lookup decoder
  has one If per syndrome value (63, 255, 1023 for d = 7, 9, 11), and a
  serial controller pays t_branch for each. The gain is as large as that
  decoder form and as real as t_branch (one measurement, 3.45 us, CI 0.32
  to 6.58, Phase 4).
- bqcp was not combined with ours here (bqcp as a pre-pass, then the fast
  path). steane and steane_noisy Qiskit O3 outputs are not stabilizer
  programs in the backend's sense and are missing as baselines.
