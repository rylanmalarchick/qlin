# QubiC dispatch cycles (RTL simulation, one core, no qubits)

QubiC distributed processor, Verilator. Cycles from the arrival of the
syndrome (function-processor read) to the end of the dispatch group,
for every syndrome value; 2 ns per cycle at 500 MHz.
Expected values weight each syndrome by its exact probability (qlin
records). source: the group's ifs; chain, tree: the fast-path switch.

## Cycles per instruction kind (least squares over every program and value)

| kind | cycles |
|---|---|
| cond_taken | 6.020 |
| cond_not | 6.003 |
| jump | 3.996 |
| mark | 3.995 |
| base | 0.941 |

312 points, largest absolute residual 0.975 cycles.

## Expected and worst-case cycles

| benchmark | t | bits | cases | variant | expected cycles | expected ns | expected decisions | worst cycles |
|---|---|---|---|---|---|---|---|---|
| dynamarq/repetition3_1_noisy | 1 | 2 | 3 | source | 30.95 | 61.9 | 3.00 | 31 |
| dynamarq/repetition3_1_noisy | 1 | 2 | 3 | chain | 14.18 | 28.4 | 1.38 | 52 |
| dynamarq/repetition3_1_noisy | 1 | 2 | 3 | tree | 19.33 | 38.7 | 2.24 | 52 |
| dynamarq/repetition3_1_noisy | 2 | 2 | 4 | source | 30.95 | 61.9 | 3.00 | 31 |
| dynamarq/repetition3_1_noisy | 2 | 2 | 4 | chain | 13.28 | 26.6 | 1.29 | 33 |
| dynamarq/repetition3_1_noisy | 2 | 2 | 4 | tree | 18.14 | 36.3 | 2.10 | 27 |
| dynamarq/repetition5_0_noisy | 1 | 4 | 5 | source | 151.09 | 302.2 | 15.00 | 155 |
| dynamarq/repetition5_0_noisy | 1 | 4 | 5 | chain | 37.13 | 74.3 | 3.88 | 189 |
| dynamarq/repetition5_0_noisy | 1 | 4 | 5 | tree | 40.91 | 81.8 | 4.51 | 183 |
| dynamarq/repetition5_0_noisy | 2 | 4 | 11 | source | 151.09 | 302.2 | 15.00 | 155 |
| dynamarq/repetition5_0_noisy | 2 | 4 | 11 | chain | 21.30 | 42.6 | 2.44 | 225 |
| dynamarq/repetition5_0_noisy | 2 | 4 | 11 | tree | 27.57 | 55.1 | 3.49 | 189 |
| dynamarq/repetition5_1_noisy | 1 | 4 | 5 | source | 151.09 | 302.2 | 15.00 | 155 |
| dynamarq/repetition5_1_noisy | 1 | 4 | 5 | chain | 37.13 | 74.3 | 3.88 | 189 |
| dynamarq/repetition5_1_noisy | 1 | 4 | 5 | tree | 40.91 | 81.8 | 4.51 | 183 |
| dynamarq/repetition5_1_noisy | 2 | 4 | 11 | source | 151.09 | 302.2 | 15.00 | 155 |
| dynamarq/repetition5_1_noisy | 2 | 4 | 11 | chain | 21.30 | 42.6 | 2.44 | 225 |
| dynamarq/repetition5_1_noisy | 2 | 4 | 11 | tree | 27.57 | 55.1 | 3.49 | 189 |
| dynamarq/five_qubit_code_noisy | 1 | 4 | 5 | source | 150.94 | 301.9 | 15.00 | 151 |
| dynamarq/five_qubit_code_noisy | 1 | 4 | 5 | chain | 135.56 | 271.1 | 14.69 | 185 |
| dynamarq/five_qubit_code_noisy | 1 | 4 | 5 | tree | 127.31 | 254.6 | 13.31 | 173 |
| dynamarq/five_qubit_code_noisy | 2 | 4 | 11 | source | 150.94 | 301.9 | 15.00 | 151 |
| dynamarq/five_qubit_code_noisy | 2 | 4 | 11 | chain | 99.94 | 199.9 | 12.25 | 221 |
| dynamarq/five_qubit_code_noisy | 2 | 4 | 11 | tree | 79.69 | 159.4 | 8.87 | 185 |
