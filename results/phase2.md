# Phase 2 results

Cost model HERON_LIKE (starting values, not measured), t_ff swept.
Latencies are expected makespans in ns under the ideal-controller model,
over exact outcome probabilities from |0...0>.

## G2 counts

- benchmark x t_ff rows: 188; skipped benchmarks: 3
- rows with exhaustive certification: 180
- B&B optimum = exhaustive optimum: 180 of 180
- bound violations: 0
- search leaves checked by simulation (t_ff = 600, exhaustive and B&B): 3046 passed (a failure stops the run), 26 over 12 qubits not checked
- M0 normal form optimal among prefix applications: see tests/m0.rs

## Rows with candidates

| benchmark | t_ff | k | source | M0 | best | floor | deferred | +2q | +q | B&B nodes / tree |
|---|---|---|---|---|---|---|---|---|---|---|
| dynamarq/cnot_ladder4 | 0 | 3 | 1792 | 1792 | 1236 | 1080 | 3 | 6 | 0 | 7 / 15 |
| dynamarq/cnot_ladder4 | 150 | 3 | 1923 | 1923 | 1236 | 1080 | 3 | 6 | 0 | 7 / 15 |
| dynamarq/cnot_ladder4 | 600 | 3 | 2317 | 2317 | 1236 | 1080 | 3 | 6 | 0 | 7 / 15 |
| dynamarq/cnot_ladder4 | 2400 | 3 | 3892 | 3892 | 1236 | 1080 | 3 | 6 | 0 | 7 / 15 |
| dynamarq/fanout4 | 0 | 3 | 1874 | 1874 | 1376 | 1220 | 3 | 8 | 0 | 7 / 15 |
| dynamarq/fanout4 | 150 | 3 | 2005 | 2005 | 1376 | 1220 | 3 | 8 | 0 | 7 / 15 |
| dynamarq/fanout4 | 600 | 3 | 2399 | 2399 | 1376 | 1220 | 3 | 8 | 0 | 7 / 15 |
| dynamarq/fanout4 | 2400 | 3 | 3974 | 3974 | 1376 | 1220 | 3 | 8 | 0 | 7 / 15 |
| dynamarq/five_qubit_code | 0 | 5 | 3340 | 3340 | 3002 | 2650 | 5 | 5 | 0 | 11 / 63 |
| dynamarq/five_qubit_code | 150 | 5 | 3575 | 3575 | 3143 | 2791 | 5 | 5 | 0 | 11 / 63 |
| dynamarq/five_qubit_code | 600 | 5 | 4278 | 4278 | 3565 | 3213 | 5 | 5 | 0 | 11 / 63 |
| dynamarq/five_qubit_code | 2400 | 5 | 7090 | 7090 | 5252 | 4900 | 5 | 5 | 0 | 11 / 63 |
| dynamarq/five_qubit_code_noisy | 0 | 5 | 3282 | 3282 | 3002 | 2649 | 5 | 5 | 0 | 11 / 63 |
| dynamarq/five_qubit_code_noisy | 150 | 5 | 3509 | 3509 | 3143 | 2789 | 5 | 5 | 0 | 11 / 63 |
| dynamarq/five_qubit_code_noisy | 600 | 5 | 4189 | 4189 | 3565 | 3211 | 5 | 5 | 0 | 11 / 63 |
| dynamarq/five_qubit_code_noisy | 2400 | 5 | 6909 | 6909 | 5252 | 4899 | 5 | 5 | 0 | 11 / 63 |
| dynamarq/ghz5 | 0 | 4 | 1748 | 1748 | 1240 | 998 | 4 | 10 | 0 | 9 / 31 |
| dynamarq/ghz5 | 150 | 4 | 1889 | 1889 | 1240 | 998 | 4 | 10 | 0 | 9 / 31 |
| dynamarq/ghz5 | 600 | 4 | 2310 | 2310 | 1240 | 998 | 4 | 10 | 0 | 9 / 31 |
| dynamarq/ghz5 | 2400 | 4 | 3998 | 3998 | 1240 | 998 | 4 | 10 | 0 | 9 / 31 |
| dynamarq/ipe3 | 0 | 3 | 5860 | 5860 | 5860 | 5860 | 0 | 0 | 0 | 15 / 15 |
| dynamarq/ipe3 | 150 | 3 | 5860 | 5860 | 5860 | 5860 | 0 | 0 | 0 | 15 / 15 |
| dynamarq/ipe3 | 600 | 3 | 5860 | 5860 | 5860 | 5860 | 0 | 0 | 0 | 15 / 15 |
| dynamarq/ipe3 | 2400 | 3 | 7160 | 7160 | 5964 | 5860 | 1 | 2 | 1 | 9 / 15 |
| dynamarq/long_range_cnot3 | 0 | 2 | 1624 | 1624 | 1136 | 1016 | 2 | 3 | 0 | 5 / 7 |
| dynamarq/long_range_cnot3 | 150 | 2 | 1736 | 1736 | 1136 | 1016 | 2 | 3 | 0 | 5 / 7 |
| dynamarq/long_range_cnot3 | 600 | 2 | 2074 | 2074 | 1136 | 1016 | 2 | 3 | 0 | 5 / 7 |
| dynamarq/long_range_cnot3 | 2400 | 2 | 3424 | 3424 | 1136 | 1016 | 2 | 3 | 0 | 5 / 7 |
| dynamarq/repetition3_0 | 0 | 3 | 1172 | 1172 | 1172 | 1172 | 0 | 0 | 0 | 13 / 15 |
| dynamarq/repetition3_0 | 150 | 3 | 1172 | 1172 | 1172 | 1172 | 0 | 0 | 0 | 13 / 15 |
| dynamarq/repetition3_0 | 600 | 3 | 1172 | 1172 | 1172 | 1172 | 0 | 0 | 0 | 13 / 15 |
| dynamarq/repetition3_0 | 2400 | 3 | 1172 | 1172 | 1172 | 1172 | 0 | 0 | 0 | 13 / 15 |
| dynamarq/repetition3_0_noisy | 0 | 3 | 1291 | 1291 | 1291 | 1174 | 0 | 0 | 0 | 15 / 15 |
| dynamarq/repetition3_0_noisy | 150 | 3 | 1312 | 1312 | 1312 | 1174 | 0 | 0 | 0 | 15 / 15 |
| dynamarq/repetition3_0_noisy | 600 | 3 | 1376 | 1376 | 1376 | 1174 | 0 | 0 | 0 | 15 / 15 |
| dynamarq/repetition3_0_noisy | 2400 | 3 | 1633 | 1633 | 1633 | 1174 | 0 | 0 | 0 | 15 / 15 |
| dynamarq/repetition3_1 | 0 | 3 | 1340 | 1340 | 1340 | 1340 | 0 | 0 | 0 | 13 / 15 |
| dynamarq/repetition3_1 | 150 | 3 | 1340 | 1340 | 1340 | 1340 | 0 | 0 | 0 | 13 / 15 |
| dynamarq/repetition3_1 | 600 | 3 | 1340 | 1340 | 1340 | 1340 | 0 | 0 | 0 | 13 / 15 |
| dynamarq/repetition3_1 | 2400 | 3 | 1340 | 1340 | 1340 | 1340 | 0 | 0 | 0 | 13 / 15 |
| dynamarq/repetition3_1_noisy | 0 | 3 | 1455 | 1455 | 1455 | 1342 | 0 | 0 | 0 | 13 / 15 |
| dynamarq/repetition3_1_noisy | 150 | 3 | 1477 | 1477 | 1477 | 1342 | 0 | 0 | 0 | 13 / 15 |
| dynamarq/repetition3_1_noisy | 600 | 3 | 1541 | 1541 | 1541 | 1342 | 0 | 0 | 0 | 13 / 15 |
| dynamarq/repetition3_1_noisy | 2400 | 3 | 1797 | 1797 | 1797 | 1342 | 0 | 0 | 0 | 15 / 15 |
| hand/mbqc_chain4 | 0 | 4 | 3132 | 3132 | 1604 | 1108 | 4 | 7 | 0 | 9 / 31 |
| hand/mbqc_chain4 | 150 | 4 | 3507 | 3507 | 1604 | 1108 | 4 | 7 | 0 | 9 / 31 |
| hand/mbqc_chain4 | 600 | 4 | 4632 | 4632 | 1604 | 1108 | 4 | 7 | 0 | 9 / 31 |
| hand/mbqc_chain4 | 2400 | 4 | 9132 | 9132 | 1604 | 1108 | 4 | 7 | 0 | 9 / 31 |
| hand/repetition3 | 0 | 3 | 1172 | 1172 | 1172 | 1172 | 0 | 0 | 0 | 15 / 15 |
| hand/repetition3 | 150 | 3 | 1172 | 1172 | 1172 | 1172 | 0 | 0 | 0 | 15 / 15 |
| hand/repetition3 | 600 | 3 | 1172 | 1172 | 1172 | 1172 | 0 | 0 | 0 | 15 / 15 |
| hand/repetition3 | 2400 | 3 | 1172 | 1172 | 1172 | 1172 | 0 | 0 | 0 | 15 / 15 |
| hand/teleportation | 0 | 2 | 1016 | 1016 | 1016 | 1000 | 0 | 0 | 0 | 7 / 7 |
| hand/teleportation | 150 | 2 | 1128 | 1128 | 1104 | 1000 | 2 | 2 | 0 | 7 / 7 |
| hand/teleportation | 600 | 2 | 1466 | 1466 | 1104 | 1000 | 2 | 2 | 0 | 5 / 7 |
| hand/teleportation | 2400 | 2 | 2816 | 2816 | 1104 | 1000 | 2 | 2 | 0 | 5 / 7 |
| jeff/iqft_3 | 0 | 3 | 5544 | 5544 | 5544 | 5544 | 0 | 0 | 0 | 15 / 15 |
| jeff/iqft_3 | 150 | 3 | 5544 | 5544 | 5544 | 5544 | 0 | 0 | 0 | 15 / 15 |
| jeff/iqft_3 | 600 | 3 | 5544 | 5544 | 5544 | 5544 | 0 | 0 | 0 | 15 / 15 |
| jeff/iqft_3 | 2400 | 3 | 6944 | 6944 | 5784 | 5544 | 2 | 4 | 2 | 7 / 15 |
| jeff/iqft_5 | 0 | 10 | 9320 | 9320 | 9320 | 9320 | 0 | 0 | 0 | 293 / 2047 |
| jeff/iqft_5 | 150 | 10 | 9320 | 9320 | 9320 | 9320 | 0 | 0 | 0 | 293 / 2047 |
| jeff/iqft_5 | 600 | 10 | 9320 | 9320 | 9320 | 9320 | 0 | 0 | 0 | 293 / 2047 |
| jeff/iqft_5 | 2400 | 10 | 12120 | 12120 | 9800 | 9320 | 4 | 8 | 4 | 107 / 2047 |
| jeff/iqft_7 | 0 | 21 | 13160 | 13160 | 13160 | 13160 | 0 | 0 | 0 | 2489 / 4194303 |
| jeff/iqft_7 | 150 | 21 | 13160 | 13160 | 13160 | 13160 | 0 | 0 | 0 | 2489 / 4194303 |
| jeff/iqft_7 | 600 | 21 | 13160 | 13160 | 13160 | 13160 | 0 | 0 | 0 | 2489 / 4194303 |
| jeff/iqft_7 | 2400 | 21 | 17360 | 17360 | 13880 | 13160 | 6 | 12 | 6 | 3003 / 4194303 |
| jeff/iqpe_3 | 0 | 3 | 5844 | 5844 | 5844 | 5844 | 0 | 0 | 0 | 15 / 15 |
| jeff/iqpe_3 | 150 | 3 | 5844 | 5844 | 5844 | 5844 | 0 | 0 | 0 | 15 / 15 |
| jeff/iqpe_3 | 600 | 3 | 5844 | 5844 | 5844 | 5844 | 0 | 0 | 0 | 15 / 15 |
| jeff/iqpe_3 | 2400 | 3 | 7144 | 7144 | 6084 | 5844 | 2 | 4 | 2 | 7 / 15 |
| jeff/iqpe_5 | 0 | 10 | 9820 | 9820 | 9820 | 9820 | 0 | 0 | 0 | 233 / 2047 |
| jeff/iqpe_5 | 150 | 10 | 9820 | 9820 | 9820 | 9820 | 0 | 0 | 0 | 233 / 2047 |
| jeff/iqpe_5 | 600 | 10 | 9820 | 9820 | 9820 | 9820 | 0 | 0 | 0 | 233 / 2047 |
| jeff/iqpe_5 | 2400 | 10 | 12420 | 12420 | 10028 | 9820 | 2 | 4 | 2 | 159 / 2047 |
| jeff/iqpe_7 | 0 | 21 | 13684 | 13684 | 13684 | 13684 | 0 | 0 | 0 | 1977 / 4194303 |
| jeff/iqpe_7 | 150 | 21 | 13684 | 13684 | 13684 | 13684 | 0 | 0 | 0 | 1977 / 4194303 |
| jeff/iqpe_7 | 600 | 21 | 13684 | 13684 | 13684 | 13684 | 0 | 0 | 0 | 1977 / 4194303 |
| jeff/iqpe_7 | 2400 | 21 | 16284 | 16284 | 13892 | 13684 | 2 | 4 | 2 | 2117 / 4194303 |
| jeff/teleportation | 0 | 2 | 1640 | 1640 | 1136 | 1000 | 2 | 2 | 0 | 5 / 7 |
| jeff/teleportation | 150 | 2 | 1753 | 1753 | 1136 | 1000 | 2 | 2 | 0 | 5 / 7 |
| jeff/teleportation | 600 | 2 | 2090 | 2090 | 1136 | 1000 | 2 | 2 | 0 | 5 / 7 |
| jeff/teleportation | 2400 | 2 | 3440 | 3440 | 1136 | 1000 | 2 | 2 | 0 | 5 / 7 |

## Skipped

- dynamarq/steane: 14 qubits > 12
- dynamarq/steane_noisy: 15 qubits > 12
- jeff/qft-adder-quantum_7: 14 qubits > 12
