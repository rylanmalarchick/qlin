# Phase 8.1 results: switch cost and sourced t_branch

Model: block sync, HERON_LIKE (assumed values), t_ff = 600 ns. Latency is
expected makespan (ns) over exact outcome probabilities from |0...0>
(dense up to 12 qubits, stabilizer past that). t_branch classes come
from notes/cost-sources.txt. Switch cost: table = 1 decision per
switch, tree = 1 per switch bit, chain = 1 per compare.
65 benchmarks.

## Summary

| class | t_branch (ns) | switch | gain > 0 | gain >= 10% | largest gain |
|---|---|---|---|---|---|
| none | 0 | table | 7 | 4 | 16.0% (qec/repetition11_1_noisy) |
| qubic | 14 | table | 11 | 8 | 80.2% (qec/repetition11_1_noisy) |
| qubic | 14 | tree | 11 | 7 | 79.1% (qec/repetition11_1_noisy) |
| qubic | 14 | chain | 11 | 8 | 78.0% (qec/repetition11_1_noisy) |
| qick | 42 | table | 11 | 11 | 92.0% (qec/repetition11_1_noisy) |
| qick | 42 | tree | 11 | 10 | 91.2% (qec/repetition11_0_noisy) |
| qick | 42 | chain | 11 | 10 | 89.4% (qec/repetition11_1_noisy) |
| ibm | 3450 | table | 13 | 13 | 99.8% (qec/repetition11_0_noisy) |
| ibm | 3450 | tree | 13 | 13 | 98.9% (qec/repetition11_0_noisy) |
| ibm | 3450 | chain | 13 | 13 | 96.9% (qec/repetition11_0_noisy) |

## none, t_branch = 0 ns, switch = table

| benchmark | qubits | best baseline | which | best ours | which | gain |
|---|---|---|---|---|---|---|
| dynamarq/repetition3_1_noisy | 6 | 2660 | best_defer | 2577 | sink_fast_t0 | 3.1% |
| dynamarq/repetition5_1_noisy | 10 | 3151 | source | 2851 | sink_fast_t0 | 9.5% |
| dynamarq/steane_noisy | 15 | 3789 | source | 3248 | sink_fast_t0 | 14.3% |
| qec/repetition11_1_noisy | 22 | 4375 | source | 3674 | sink_fast_t0 | 16.0% |
| qec/repetition7_1_noisy | 14 | 3559 | source | 3126 | sink_fast_t0 | 12.2% |
| qec/repetition9_1_noisy | 18 | 3967 | source | 3400 | sink_fast_t0 | 14.3% |
| qec/surface3_0_noisy | 19 | 3756 | source | 3488 | sink_fast_t0 | 7.1% |

## qubic, t_branch = 14 ns, switch = table

| benchmark | qubits | best baseline | which | best ours | which | gain |
|---|---|---|---|---|---|---|
| dynamarq/repetition3_1_noisy | 6 | 2660 | best_defer | 2605 | sink_fast_t2 | 2.1% |
| dynamarq/repetition5_0_noisy | 10 | 2986 | bqcp | 2865 | fast_t4 | 4.0% |
| dynamarq/repetition5_1_noisy | 10 | 3358 | source | 2904 | sink_fast_t4 | 13.5% |
| dynamarq/steane_noisy | 15 | 3887 | source | 3346 | sink_fast_t0 | 13.9% |
| qec/repetition11_0_noisy | 22 | 17914 | bqcp | 3692 | fast_t6 | 79.4% |
| qec/repetition11_1_noisy | 22 | 18694 | source | 3700 | sink_fast_t6 | 80.2% |
| qec/repetition7_0_noisy | 14 | 3930 | bqcp | 3140 | fast_t6 | 20.1% |
| qec/repetition7_1_noisy | 14 | 4438 | source | 3150 | sink_fast_t6 | 29.0% |
| qec/repetition9_0_noisy | 18 | 6890 | bqcp | 3414 | fast_t6 | 50.5% |
| qec/repetition9_1_noisy | 18 | 7534 | source | 3423 | sink_fast_t6 | 54.6% |
| qec/surface3_0_noisy | 19 | 3924 | source | 3549 | sink_fast_t3 | 9.6% |

## qubic, t_branch = 14 ns, switch = tree

| benchmark | qubits | best baseline | which | best ours | which | gain |
|---|---|---|---|---|---|---|
| dynamarq/repetition3_1_noisy | 6 | 2660 | best_defer | 2617 | sink_only | 1.6% |
| dynamarq/repetition5_0_noisy | 10 | 2986 | bqcp | 2907 | fast_t4 | 2.6% |
| dynamarq/repetition5_1_noisy | 10 | 3358 | source | 3054 | sink_only | 9.1% |
| dynamarq/steane_noisy | 15 | 3887 | source | 3346 | sink_only | 13.9% |
| qec/repetition11_0_noisy | 22 | 17914 | bqcp | 3818 | fast_t6 | 78.7% |
| qec/repetition11_1_noisy | 22 | 18694 | source | 3904 | sink_fast_t6 | 79.1% |
| qec/repetition7_0_noisy | 14 | 3930 | bqcp | 3210 | fast_t6 | 18.3% |
| qec/repetition7_1_noisy | 14 | 4438 | source | 3284 | sink_fast_t6 | 26.0% |
| qec/repetition9_0_noisy | 18 | 6890 | bqcp | 3512 | fast_t6 | 49.0% |
| qec/repetition9_1_noisy | 18 | 7534 | source | 3599 | sink_fast_t6 | 52.2% |
| qec/surface3_0_noisy | 19 | 3924 | source | 3710 | sink_fast_t3 | 5.4% |

## qubic, t_branch = 14 ns, switch = chain

| benchmark | qubits | best baseline | which | best ours | which | gain |
|---|---|---|---|---|---|---|
| dynamarq/repetition3_1_noisy | 6 | 2660 | best_defer | 2607 | sink_fast_t0 | 2.0% |
| dynamarq/repetition5_0_noisy | 10 | 2986 | bqcp | 2884 | fast_t4 | 3.4% |
| dynamarq/repetition5_1_noisy | 10 | 3358 | source | 2933 | sink_fast_t2 | 12.7% |
| dynamarq/steane_noisy | 15 | 3887 | source | 3346 | sink_fast_t0 | 13.9% |
| qec/repetition11_0_noisy | 22 | 17914 | bqcp | 4103 | fast_t6 | 77.1% |
| qec/repetition11_1_noisy | 22 | 18694 | source | 4117 | sink_fast_t6 | 78.0% |
| qec/repetition7_0_noisy | 14 | 3930 | bqcp | 3196 | fast_t6 | 18.7% |
| qec/repetition7_1_noisy | 14 | 4438 | source | 3228 | sink_fast_t2 | 27.3% |
| qec/repetition9_0_noisy | 18 | 6890 | bqcp | 3568 | fast_t6 | 48.2% |
| qec/repetition9_1_noisy | 18 | 7534 | source | 3603 | sink_fast_t6 | 52.2% |
| qec/surface3_0_noisy | 19 | 3924 | source | 3563 | sink_fast_t2 | 9.2% |

## qick, t_branch = 42 ns, switch = table

| benchmark | qubits | best baseline | which | best ours | which | gain |
|---|---|---|---|---|---|---|
| dynamarq/repetition5_0_noisy | 10 | 3406 | bqcp | 2893 | fast_t4 | 15.1% |
| dynamarq/repetition5_1_noisy | 10 | 3778 | source | 3025 | sink_fast_t4 | 19.9% |
| dynamarq/steane_noisy | 15 | 4114 | source | 3542 | sink_fast_t3 | 13.9% |
| qec/repetition11_0_noisy | 22 | 46558 | bqcp | 3727 | fast_t6 | 92.0% |
| qec/repetition11_1_noisy | 22 | 47338 | source | 3771 | sink_fast_t6 | 92.0% |
| qec/repetition7_0_noisy | 14 | 5694 | bqcp | 3168 | fast_t6 | 44.4% |
| qec/repetition7_1_noisy | 14 | 6202 | source | 3201 | sink_fast_t6 | 48.4% |
| qec/repetition9_0_noisy | 18 | 14030 | bqcp | 3442 | fast_t6 | 75.5% |
| qec/repetition9_1_noisy | 18 | 14674 | source | 3479 | sink_fast_t6 | 76.3% |
| qec/surface3_0_noisy | 19 | 4748 | source | 3670 | sink_fast_t3 | 22.7% |
| qec/surface3_1_noisy | 19 | 4392 | bqcp | 3943 | sink_fast_t3 | 10.2% |

## qick, t_branch = 42 ns, switch = tree

| benchmark | qubits | best baseline | which | best ours | which | gain |
|---|---|---|---|---|---|---|
| dynamarq/repetition5_0_noisy | 10 | 3406 | bqcp | 3019 | fast_t4 | 11.4% |
| dynamarq/repetition5_1_noisy | 10 | 3778 | source | 3319 | fast_t4 | 12.1% |
| dynamarq/steane_noisy | 15 | 4114 | source | 3600 | sink_only | 12.5% |
| qec/repetition11_0_noisy | 22 | 46558 | bqcp | 4105 | fast_t6 | 91.2% |
| qec/repetition11_1_noisy | 22 | 47338 | source | 4388 | sink_fast_t6 | 90.7% |
| qec/repetition7_0_noisy | 14 | 5694 | bqcp | 3378 | fast_t6 | 40.7% |
| qec/repetition7_1_noisy | 14 | 6202 | source | 3621 | sink_fast_t6 | 41.6% |
| qec/repetition9_0_noisy | 18 | 14030 | bqcp | 3736 | fast_t6 | 73.4% |
| qec/repetition9_1_noisy | 18 | 14674 | source | 4020 | sink_fast_t6 | 72.6% |
| qec/surface3_0_noisy | 19 | 4748 | source | 4094 | fast_t4 | 13.8% |
| qec/surface3_1_noisy | 19 | 4392 | bqcp | 4364 | fast_t4 | 0.6% |

## qick, t_branch = 42 ns, switch = chain

| benchmark | qubits | best baseline | which | best ours | which | gain |
|---|---|---|---|---|---|---|
| dynamarq/repetition5_0_noisy | 10 | 3406 | bqcp | 2948 | fast_t4 | 13.4% |
| dynamarq/repetition5_1_noisy | 10 | 3778 | source | 3109 | sink_fast_t2 | 17.7% |
| dynamarq/steane_noisy | 15 | 4114 | source | 3549 | sink_fast_t3 | 13.7% |
| qec/repetition11_0_noisy | 22 | 46558 | bqcp | 4963 | fast_t6 | 89.3% |
| qec/repetition11_1_noisy | 22 | 47338 | source | 5025 | sink_fast_t6 | 89.4% |
| qec/repetition7_0_noisy | 14 | 5694 | bqcp | 3336 | fast_t6 | 41.4% |
| qec/repetition7_1_noisy | 14 | 6202 | source | 3450 | sink_fast_t2 | 44.4% |
| qec/repetition9_0_noisy | 18 | 14030 | bqcp | 3903 | fast_t6 | 72.2% |
| qec/repetition9_1_noisy | 18 | 14674 | source | 4032 | sink_fast_t6 | 72.5% |
| qec/surface3_0_noisy | 19 | 4748 | source | 3750 | sink_fast_t2 | 21.0% |
| qec/surface3_1_noisy | 19 | 4392 | bqcp | 4226 | sink_fast_t1 | 3.8% |

## ibm, t_branch = 3450 ns, switch = table

| benchmark | qubits | best baseline | which | best ours | which | gain |
|---|---|---|---|---|---|---|
| dynamarq/five_qubit_code | 11 | 55236 | best_defer | 12052 | fast_t4 | 78.2% |
| dynamarq/five_qubit_code_noisy | 12 | 55236 | best_defer | 12052 | fast_t5 | 78.2% |
| dynamarq/repetition5_0_noisy | 10 | 54526 | bqcp | 6301 | fast_t4 | 88.4% |
| dynamarq/repetition5_1_noisy | 10 | 54898 | source | 6601 | fast_t4 | 88.0% |
| dynamarq/steane_noisy | 15 | 51444 | source | 7239 | fast_t3 | 85.9% |
| qec/repetition11_0_noisy | 22 | 3532942 | bqcp | 8074 | fast_t6 | 99.8% |
| qec/repetition11_1_noisy | 22 | 3533722 | source | 8776 | fast_t6 | 99.8% |
| qec/repetition7_0_noisy | 14 | 220398 | bqcp | 6576 | fast_t6 | 97.0% |
| qec/repetition7_1_noisy | 14 | 220906 | source | 7009 | fast_t6 | 96.8% |
| qec/repetition9_0_noisy | 18 | 883070 | bqcp | 6890 | fast_t6 | 99.2% |
| qec/repetition9_1_noisy | 18 | 883714 | source | 7457 | fast_t6 | 99.2% |
| qec/surface3_0_noisy | 19 | 106988 | source | 7208 | fast_t4 | 93.3% |
| qec/surface3_1_noisy | 19 | 106616 | bqcp | 7478 | fast_t4 | 93.0% |

## ibm, t_branch = 3450 ns, switch = tree

| benchmark | qubits | best baseline | which | best ours | which | gain |
|---|---|---|---|---|---|---|
| dynamarq/five_qubit_code | 11 | 55236 | best_defer | 22402 | fast_t4 | 59.4% |
| dynamarq/five_qubit_code_noisy | 12 | 55236 | best_defer | 22402 | fast_t5 | 59.4% |
| dynamarq/repetition5_0_noisy | 10 | 54526 | bqcp | 16651 | fast_t4 | 69.5% |
| dynamarq/repetition5_1_noisy | 10 | 54898 | source | 16951 | fast_t4 | 69.1% |
| dynamarq/steane_noisy | 15 | 51444 | source | 24489 | fast_t3 | 52.4% |
| qec/repetition11_0_noisy | 22 | 3532942 | bqcp | 39124 | fast_t6 | 98.9% |
| qec/repetition11_1_noisy | 22 | 3533722 | source | 39826 | fast_t6 | 98.9% |
| qec/repetition7_0_noisy | 14 | 220398 | bqcp | 23826 | fast_t6 | 89.2% |
| qec/repetition7_1_noisy | 14 | 220906 | source | 24259 | fast_t6 | 89.0% |
| qec/repetition9_0_noisy | 18 | 883070 | bqcp | 31040 | fast_t6 | 96.5% |
| qec/repetition9_1_noisy | 18 | 883714 | source | 31607 | fast_t6 | 96.4% |
| qec/surface3_0_noisy | 19 | 106988 | source | 31358 | fast_t4 | 70.7% |
| qec/surface3_1_noisy | 19 | 106616 | bqcp | 31628 | fast_t4 | 70.3% |

## ibm, t_branch = 3450 ns, switch = chain

| benchmark | qubits | best baseline | which | best ours | which | gain |
|---|---|---|---|---|---|---|
| dynamarq/five_qubit_code | 11 | 55236 | best_defer | 39221 | fast_t4 | 29.0% |
| dynamarq/five_qubit_code_noisy | 12 | 55236 | best_defer | 39397 | fast_t5 | 28.7% |
| dynamarq/repetition5_0_noisy | 10 | 54526 | bqcp | 10819 | fast_t4 | 80.2% |
| dynamarq/repetition5_1_noisy | 10 | 54898 | source | 11119 | fast_t4 | 79.7% |
| dynamarq/steane_noisy | 15 | 51444 | source | 21258 | fast_t1 | 58.7% |
| qec/repetition11_0_noisy | 22 | 3532942 | bqcp | 109550 | fast_t6 | 96.9% |
| qec/repetition11_1_noisy | 22 | 3533722 | source | 110251 | fast_t6 | 96.9% |
| qec/repetition7_0_noisy | 14 | 220398 | bqcp | 20378 | fast_t6 | 90.8% |
| qec/repetition7_1_noisy | 14 | 220906 | source | 20811 | fast_t6 | 90.6% |
| qec/repetition9_0_noisy | 18 | 883070 | bqcp | 44741 | fast_t6 | 94.9% |
| qec/repetition9_1_noisy | 18 | 883714 | source | 45308 | fast_t6 | 94.9% |
| qec/surface3_0_noisy | 19 | 106988 | source | 31148 | fast_t2 | 70.9% |
| qec/surface3_1_noisy | 19 | 106616 | bqcp | 31415 | fast_t2 | 70.5% |

## Skipped

- jeff/qft-adder-quantum_7: qlin lat /home/rylan/dev/projects/qlin-surface/benchmarks/jeff/qft-adder-quantum_7.qlin: 14 qubits is more than the limit of 12
