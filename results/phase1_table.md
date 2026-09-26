| benchmark | pipeline | qubits | m | gates | 2q | dyn | ff | core_b | core_l | mov | dead | guard |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| dynamarq/cnot_ladder4 | source | 7 | 7 | 19 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | reference |
| dynamarq/cnot_ladder4 | bqcp | 7 | 5 | 14 | 2 | 2 | 2 | 2 | 0 | 0 | 0 | match |
| dynamarq/cnot_ladder4 | qiskit_o0 | 7 | 7 | 35 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| dynamarq/cnot_ladder4 | qiskit_o3 | 7 | 7 | 32 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| dynamarq/cnot_ladder4 | tket | n/a: NotImplementedError: Handling of Unary, Var, Binary and Expr conditions is not supported yet. |  |  |  |  |  |  |  |  |  |  |
| dynamarq/fanout4 | source | 9 | 9 | 26 | 11 | 5 | 3 | 5 | 0 | 0 | 0 | reference |
| dynamarq/fanout4 | bqcp | 9 | 5 | 20 | 7 | 3 | 2 | 3 | 0 | 0 | 0 | match |
| dynamarq/fanout4 | qiskit_o0 | 9 | 9 | 42 | 11 | 5 | 3 | 5 | 0 | 0 | 0 | match |
| dynamarq/fanout4 | qiskit_o3 | 9 | 9 | 39 | 11 | 5 | 3 | 5 | 0 | 0 | 0 | match |
| dynamarq/fanout4 | tket | n/a: NotImplementedError: Handling of Unary, Var, Binary and Expr conditions is not supported yet. |  |  |  |  |  |  |  |  |  |  |
| dynamarq/five_qubit_code | source | 11 | 11 | 58 | 26 | 20 | 20 | 20 | 0 | 0 | 0 | reference |
| dynamarq/five_qubit_code | bqcp | 11 | 11 | 55 | 23 | 20 | 20 | 20 | 0 | 0 | 0 | match |
| dynamarq/five_qubit_code | qiskit_o0 | 11 | 11 | 195 | 26 | 25 | 20 | 25 | 0 | 0 | 0 | match |
| dynamarq/five_qubit_code | qiskit_o3 | 11 | 11 | 171 | 26 | 25 | 20 | 25 | 0 | 0 | 0 | match |
| dynamarq/five_qubit_code | tket | 11 | 11 | 88 | 26 | 20 | 20 | 20 | 0 | 0 | 0 | match |
| dynamarq/five_qubit_code_noisy | source | 11 | 11 | 58 | 26 | 20 | 20 | 20 | 0 | 0 | 0 | reference |
| dynamarq/five_qubit_code_noisy | bqcp | 11 | 11 | 58 | 26 | 20 | 20 | 20 | 0 | 0 | 0 | match |
| dynamarq/five_qubit_code_noisy | qiskit_o0 | 11 | 11 | 195 | 26 | 25 | 20 | 25 | 0 | 0 | 0 | match |
| dynamarq/five_qubit_code_noisy | qiskit_o3 | 11 | 11 | 171 | 26 | 25 | 20 | 25 | 0 | 0 | 0 | match |
| dynamarq/five_qubit_code_noisy | tket | 11 | 11 | 88 | 26 | 20 | 20 | 20 | 0 | 0 | 0 | match |
| dynamarq/ghz5 | source | 9 | 9 | 17 | 8 | 4 | 4 | 4 | 0 | 0 | 0 | reference |
| dynamarq/ghz5 | bqcp | 9 | 9 | 17 | 8 | 4 | 4 | 4 | 0 | 0 | 0 | match |
| dynamarq/ghz5 | qiskit_o0 | 9 | 9 | 27 | 8 | 4 | 4 | 4 | 0 | 0 | 0 | match |
| dynamarq/ghz5 | qiskit_o3 | 9 | 9 | 27 | 8 | 4 | 4 | 4 | 0 | 0 | 0 | match |
| dynamarq/ghz5 | tket | n/a: NotImplementedError: Handling of Unary, Var, Binary and Expr conditions is not supported yet. |  |  |  |  |  |  |  |  |  |  |
| dynamarq/ipe3 | source | 2 | 3 | 16 | 3 | 3 | 3 | 3 | 0 | 0 | 3 | reference |
| dynamarq/ipe3 | bqcp | 2 | 2 | 12 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| dynamarq/ipe3 | qiskit_o0 | 2 | 3 | 40 | 6 | 3 | 3 | 3 | 0 | 0 | 3 | match |
| dynamarq/ipe3 | qiskit_o3 | 2 | 3 | 41 | 5 | 3 | 3 | 3 | 0 | 0 | 3 | match |
| dynamarq/ipe3 | tket | 2 | 3 | 23 | 5 | 3 | 3 | 3 | 0 | 0 | 3 | match |
| dynamarq/long_range_cnot3 | source | 5 | 5 | 11 | 4 | 2 | 2 | 2 | 0 | 0 | 0 | reference |
| dynamarq/long_range_cnot3 | bqcp | 5 | 3 | 6 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| dynamarq/long_range_cnot3 | qiskit_o0 | 5 | 5 | 21 | 4 | 2 | 2 | 2 | 0 | 0 | 0 | match |
| dynamarq/long_range_cnot3 | qiskit_o3 | 5 | 5 | 21 | 4 | 2 | 2 | 2 | 0 | 0 | 0 | match |
| dynamarq/long_range_cnot3 | tket | n/a: NotImplementedError: Handling of Unary, Var, Binary and Expr conditions is not supported yet. |  |  |  |  |  |  |  |  |  |  |
| dynamarq/repetition3_0 | source | 5 | 5 | 10 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | reference |
| dynamarq/repetition3_0 | bqcp | 5 | 3 | 7 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| dynamarq/repetition3_0 | qiskit_o0 | 5 | 5 | 10 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| dynamarq/repetition3_0 | qiskit_o3 | 5 | 5 | 10 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| dynamarq/repetition3_0 | tket | 5 | 5 | 10 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| dynamarq/repetition3_0_noisy | source | 5 | 5 | 10 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | reference |
| dynamarq/repetition3_0_noisy | bqcp | 5 | 5 | 10 | 4 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| dynamarq/repetition3_0_noisy | qiskit_o0 | 5 | 5 | 10 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| dynamarq/repetition3_0_noisy | qiskit_o3 | 5 | 5 | 10 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| dynamarq/repetition3_0_noisy | tket | 5 | 5 | 10 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| dynamarq/repetition3_1 | source | 5 | 5 | 13 | 8 | 3 | 3 | 3 | 0 | 0 | 0 | reference |
| dynamarq/repetition3_1 | bqcp | 5 | 0 | 10 | 8 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| dynamarq/repetition3_1 | qiskit_o0 | 5 | 5 | 17 | 8 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| dynamarq/repetition3_1 | qiskit_o3 | 5 | 5 | 17 | 8 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| dynamarq/repetition3_1 | tket | 5 | 5 | 14 | 8 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| dynamarq/repetition3_1_noisy | source | 5 | 5 | 13 | 8 | 3 | 3 | 3 | 0 | 0 | 0 | reference |
| dynamarq/repetition3_1_noisy | bqcp | 5 | 5 | 13 | 8 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| dynamarq/repetition3_1_noisy | qiskit_o0 | 5 | 5 | 17 | 8 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| dynamarq/repetition3_1_noisy | qiskit_o3 | 5 | 5 | 17 | 8 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| dynamarq/repetition3_1_noisy | tket | 5 | 5 | 14 | 8 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| dynamarq/repetition5_0 | source | 9 | 9 | 38 | 12 | 25 | 15 | 25 | 0 | 0 | 0 | reference |
| dynamarq/repetition5_0 | bqcp | 9 | 5 | 13 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| dynamarq/repetition5_0 | qiskit_o0 | 9 | 9 | 38 | 12 | 25 | 15 | 25 | 0 | 0 | 0 | match |
| dynamarq/repetition5_0 | qiskit_o3 | 9 | 9 | 38 | 12 | 25 | 15 | 25 | 0 | 0 | 0 | match |
| dynamarq/repetition5_0 | tket | n/a: RuntimeError: Can only build replacement circuits for basic gates: CircBox |  |  |  |  |  |  |  |  |  |  |
| dynamarq/repetition5_0_noisy | source | 9 | 9 | 38 | 12 | 25 | 15 | 25 | 0 | 0 | 0 | reference |
| dynamarq/repetition5_0_noisy | bqcp | 9 | 9 | 38 | 8 | 25 | 15 | 25 | 0 | 0 | 0 | match |
| dynamarq/repetition5_0_noisy | qiskit_o0 | 9 | 9 | 38 | 12 | 25 | 15 | 25 | 0 | 0 | 0 | match |
| dynamarq/repetition5_0_noisy | qiskit_o3 | 9 | 9 | 38 | 12 | 25 | 15 | 25 | 0 | 0 | 0 | match |
| dynamarq/repetition5_0_noisy | tket | n/a: RuntimeError: Can only build replacement circuits for basic gates: CircBox |  |  |  |  |  |  |  |  |  |  |
| dynamarq/repetition5_1 | source | 9 | 9 | 43 | 16 | 25 | 15 | 25 | 0 | 0 | 0 | reference |
| dynamarq/repetition5_1 | bqcp | 9 | 0 | 18 | 16 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| dynamarq/repetition5_1 | qiskit_o0 | 9 | 9 | 47 | 16 | 25 | 15 | 25 | 0 | 0 | 0 | match |
| dynamarq/repetition5_1 | qiskit_o3 | 9 | 9 | 47 | 16 | 25 | 15 | 25 | 0 | 0 | 0 | match |
| dynamarq/repetition5_1 | tket | n/a: RuntimeError: Can only build replacement circuits for basic gates: CircBox |  |  |  |  |  |  |  |  |  |  |
| dynamarq/repetition5_1_noisy | source | 9 | 9 | 43 | 16 | 25 | 15 | 25 | 0 | 0 | 0 | reference |
| dynamarq/repetition5_1_noisy | bqcp | 9 | 9 | 43 | 16 | 25 | 15 | 25 | 0 | 0 | 0 | match |
| dynamarq/repetition5_1_noisy | qiskit_o0 | 9 | 9 | 47 | 16 | 25 | 15 | 25 | 0 | 0 | 0 | match |
| dynamarq/repetition5_1_noisy | qiskit_o3 | 9 | 9 | 47 | 16 | 25 | 15 | 25 | 0 | 0 | 0 | match |
| dynamarq/repetition5_1_noisy | tket | n/a: RuntimeError: Can only build replacement circuits for basic gates: CircBox |  |  |  |  |  |  |  |  |  |  |
| dynamarq/steane | source | 14 | 14 | 79 | 40 | 14 | 14 | 14 | 0 | 0 | 0 | too many qubits |
| dynamarq/steane | bqcp | 14 | 7 | 65 | 40 | 0 | 0 | 0 | 0 | 0 | 0 | too many qubits |
| dynamarq/steane | qiskit_o0 | 14 | 14 | 143 | 40 | 14 | 14 | 14 | 0 | 0 | 0 | too many qubits |
| dynamarq/steane | qiskit_o3 | 14 | 14 | 103 | 40 | 14 | 14 | 14 | 0 | 0 | 0 | too many qubits |
| dynamarq/steane | tket | 14 | 14 | 73 | 40 | 14 | 14 | 14 | 0 | 0 | 0 | too many qubits |
| dynamarq/steane_noisy | source | 14 | 14 | 79 | 40 | 14 | 14 | 14 | 0 | 0 | 0 | too many qubits |
| dynamarq/steane_noisy | bqcp | 14 | 14 | 79 | 40 | 14 | 14 | 14 | 0 | 0 | 0 | too many qubits |
| dynamarq/steane_noisy | qiskit_o0 | 14 | 14 | 143 | 40 | 14 | 14 | 14 | 0 | 0 | 0 | too many qubits |
| dynamarq/steane_noisy | qiskit_o3 | 14 | 14 | 103 | 40 | 14 | 14 | 14 | 0 | 0 | 0 | too many qubits |
| dynamarq/steane_noisy | tket | 14 | 14 | 73 | 40 | 14 | 14 | 14 | 0 | 0 | 0 | too many qubits |
| hand/decode_reset | source | 5 | 5 | 12 | 6 | 11 | 3 | 11 | 0 | 0 | 0 | reference |
| hand/decode_reset | bqcp | 5 | 3 | 11 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | match |
| hand/decode_reset | qiskit_o0 | 5 | 5 | 16 | 6 | 11 | 3 | 11 | 0 | 0 | 0 | match |
| hand/decode_reset | qiskit_o3 | 5 | 5 | 10 | 6 | 11 | 3 | 11 | 0 | 0 | 0 | match |
| hand/decode_reset | tket | n/a: RuntimeError: Cannot find classical register with name "k3_4". |  |  |  |  |  |  |  |  |  |  |
| hand/mbqc_chain4 | source | 4 | 4 | 20 | 3 | 14 | 4 | 6 | 0 | 4 | 0 | reference |
| hand/mbqc_chain4 | bqcp | 4 | 4 | 17 | 3 | 7 | 2 | 3 | 0 | 2 | 0 | MISMATCH (max diff 0.0177) |
| hand/mbqc_chain4 | qiskit_o0 | 4 | 4 | 58 | 3 | 22 | 4 | 6 | 0 | 8 | 0 | match |
| hand/mbqc_chain4 | qiskit_o3 | 4 | 4 | 41 | 3 | 18 | 4 | 6 | 0 | 6 | 0 | match |
| hand/mbqc_chain4 | tket | n/a: NotImplementedError: Handling of Unary, Var, Binary and Expr conditions is not supported yet. |  |  |  |  |  |  |  |  |  |  |
| hand/repetition3 | source | 5 | 2 | 10 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | reference |
| hand/repetition3 | bqcp | 5 | 0 | 7 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| hand/repetition3 | qiskit_o0 | 5 | 2 | 10 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| hand/repetition3 | qiskit_o3 | 5 | 2 | 10 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| hand/repetition3 | tket | 5 | 2 | 10 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| hand/teleportation | source | 3 | 2 | 6 | 2 | 2 | 2 | 2 | 0 | 0 | 0 | reference |
| hand/teleportation | bqcp | 3 | 2 | 4 | 1 | 1 | 1 | 1 | 0 | 0 | 0 | match |
| hand/teleportation | qiskit_o0 | 3 | 2 | 10 | 2 | 2 | 2 | 2 | 0 | 0 | 0 | match |
| hand/teleportation | qiskit_o3 | 3 | 2 | 10 | 2 | 2 | 2 | 2 | 0 | 0 | 0 | match |
| hand/teleportation | tket | 3 | 2 | 7 | 2 | 2 | 2 | 2 | 0 | 0 | 0 | match |
| jeff/ghz-linear_3 | source | 3 | 3 | 3 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/ghz-linear_3 | bqcp | 3 | 3 | 3 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-linear_3 | qiskit_o0 | 3 | 3 | 5 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-linear_3 | qiskit_o3 | 3 | 3 | 5 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-linear_3 | tket | 3 | 3 | 3 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-linear_5 | source | 5 | 5 | 5 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/ghz-linear_5 | bqcp | 5 | 5 | 5 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-linear_5 | qiskit_o0 | 5 | 5 | 7 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-linear_5 | qiskit_o3 | 5 | 5 | 7 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-linear_5 | tket | 5 | 5 | 5 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-linear_7 | source | 7 | 7 | 7 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/ghz-linear_7 | bqcp | 7 | 7 | 7 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-linear_7 | qiskit_o0 | 7 | 7 | 9 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-linear_7 | qiskit_o3 | 7 | 7 | 9 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-linear_7 | tket | 7 | 7 | 7 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-star_3 | source | 3 | 3 | 3 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/ghz-star_3 | bqcp | 3 | 3 | 3 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-star_3 | qiskit_o0 | 3 | 3 | 5 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-star_3 | qiskit_o3 | 3 | 3 | 5 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-star_3 | tket | 3 | 3 | 3 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-star_5 | source | 5 | 5 | 5 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/ghz-star_5 | bqcp | 5 | 5 | 5 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-star_5 | qiskit_o0 | 5 | 5 | 7 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-star_5 | qiskit_o3 | 5 | 5 | 7 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-star_5 | tket | 5 | 5 | 5 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-star_7 | source | 7 | 7 | 7 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/ghz-star_7 | bqcp | 7 | 7 | 7 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-star_7 | qiskit_o0 | 7 | 7 | 9 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-star_7 | qiskit_o3 | 7 | 7 | 9 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/ghz-star_7 | tket | 7 | 7 | 7 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/grover_3 | source | 2 | 2 | 12 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/grover_3 | bqcp | 2 | 2 | 10 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/grover_3 | qiskit_o0 | 2 | 2 | 36 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/grover_3 | qiskit_o3 | 2 | 2 | 16 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/grover_3 | tket | 2 | 2 | 7 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/iqft_3 | source | 1 | 3 | 6 | 0 | 3 | 3 | 3 | 0 | 0 | 0 | reference |
| jeff/iqft_3 | bqcp | 1 | 3 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/iqft_3 | qiskit_o0 | 1 | 3 | 12 | 0 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| jeff/iqft_3 | qiskit_o3 | 1 | 3 | 12 | 0 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| jeff/iqft_3 | tket | 1 | 3 | 6 | 0 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| jeff/iqft_5 | source | 1 | 5 | 15 | 0 | 10 | 10 | 10 | 0 | 0 | 0 | reference |
| jeff/iqft_5 | bqcp | 1 | 5 | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/iqft_5 | qiskit_o0 | 1 | 5 | 25 | 0 | 10 | 10 | 10 | 0 | 0 | 0 | match |
| jeff/iqft_5 | qiskit_o3 | 1 | 5 | 25 | 0 | 10 | 10 | 10 | 0 | 0 | 0 | match |
| jeff/iqft_5 | tket | 1 | 5 | 15 | 0 | 10 | 10 | 10 | 0 | 0 | 0 | match |
| jeff/iqft_7 | source | 1 | 7 | 28 | 0 | 21 | 21 | 21 | 0 | 0 | 0 | reference |
| jeff/iqft_7 | bqcp | 1 | 7 | 7 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/iqft_7 | qiskit_o0 | 1 | 7 | 42 | 0 | 21 | 21 | 21 | 0 | 0 | 0 | match |
| jeff/iqft_7 | qiskit_o3 | 1 | 7 | 42 | 0 | 21 | 21 | 21 | 0 | 0 | 0 | match |
| jeff/iqft_7 | tket | 1 | 7 | 28 | 0 | 21 | 21 | 21 | 0 | 0 | 0 | match |
| jeff/iqpe_3 | source | 2 | 3 | 13 | 3 | 3 | 3 | 3 | 0 | 0 | 0 | reference |
| jeff/iqpe_3 | bqcp | 2 | 3 | 13 | 3 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| jeff/iqpe_3 | qiskit_o0 | 2 | 3 | 37 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| jeff/iqpe_3 | qiskit_o3 | 2 | 3 | 33 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| jeff/iqpe_3 | tket | 2 | 3 | 22 | 6 | 3 | 3 | 3 | 0 | 0 | 0 | match |
| jeff/iqpe_5 | source | 2 | 5 | 26 | 5 | 10 | 10 | 10 | 0 | 0 | 0 | reference |
| jeff/iqpe_5 | bqcp | 2 | 2 | 20 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/iqpe_5 | qiskit_o0 | 2 | 5 | 66 | 10 | 10 | 10 | 10 | 0 | 0 | 0 | match |
| jeff/iqpe_5 | qiskit_o3 | 2 | 5 | 53 | 7 | 10 | 10 | 10 | 0 | 0 | 0 | match |
| jeff/iqpe_5 | tket | 2 | 5 | 33 | 7 | 10 | 10 | 10 | 0 | 0 | 0 | match |
| jeff/iqpe_7 | source | 2 | 7 | 43 | 7 | 21 | 21 | 21 | 0 | 0 | 0 | reference |
| jeff/iqpe_7 | bqcp | 2 | 2 | 24 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/iqpe_7 | qiskit_o0 | 2 | 7 | 99 | 14 | 21 | 21 | 21 | 0 | 0 | 0 | match |
| jeff/iqpe_7 | qiskit_o3 | 2 | 7 | 76 | 7 | 21 | 21 | 21 | 0 | 0 | 0 | match |
| jeff/iqpe_7 | tket | 2 | 7 | 48 | 7 | 21 | 21 | 21 | 0 | 0 | 0 | match |
| jeff/qft-adder-classical_3 | source | 3 | 3 | 16 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/qft-adder-classical_3 | bqcp | 3 | 2 | 13 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-classical_3 | qiskit_o0 | 3 | 3 | 52 | 12 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-classical_3 | qiskit_o3 | 3 | 3 | 36 | 9 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-classical_3 | tket | 3 | 3 | 21 | 9 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-classical_5 | source | 5 | 5 | 36 | 20 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/qft-adder-classical_5 | bqcp | 5 | 2 | 25 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-classical_5 | qiskit_o0 | 5 | 5 | 136 | 40 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-classical_5 | qiskit_o3 | 5 | 5 | 102 | 37 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-classical_5 | tket | 5 | 5 | 81 | 37 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-classical_7 | source | 7 | 7 | 64 | 42 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/qft-adder-classical_7 | bqcp | 7 | 2 | 37 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-classical_7 | qiskit_o0 | 7 | 7 | 260 | 84 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-classical_7 | qiskit_o3 | 7 | 7 | 200 | 81 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-classical_7 | tket | 7 | 7 | 173 | 81 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-quantum_3 | source | 6 | 6 | 22 | 12 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/qft-adder-quantum_3 | bqcp | 6 | 6 | 21 | 9 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-quantum_3 | qiskit_o0 | 6 | 6 | 88 | 24 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-quantum_3 | qiskit_o3 | 6 | 6 | 85 | 21 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-quantum_3 | tket | 6 | 6 | 49 | 21 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-quantum_5 | source | 10 | 10 | 51 | 35 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/qft-adder-quantum_5 | bqcp | 10 | 10 | 45 | 25 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-quantum_5 | qiskit_o0 | 10 | 10 | 221 | 70 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-quantum_5 | qiskit_o3 | 10 | 10 | 203 | 65 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-quantum_5 | tket | 10 | 10 | 143 | 65 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft-adder-quantum_7 | source | 14 | 14 | 92 | 70 | 0 | 0 | 0 | 0 | 0 | 0 | too many qubits |
| jeff/qft-adder-quantum_7 | bqcp | 14 | 14 | 77 | 49 | 0 | 0 | 0 | 0 | 0 | 0 | too many qubits |
| jeff/qft-adder-quantum_7 | qiskit_o0 | 14 | 14 | 414 | 140 | 0 | 0 | 0 | 0 | 0 | 0 | too many qubits |
| jeff/qft-adder-quantum_7 | qiskit_o3 | 14 | 14 | 369 | 133 | 0 | 0 | 0 | 0 | 0 | 0 | too many qubits |
| jeff/qft-adder-quantum_7 | tket | 14 | 14 | 285 | 133 | 0 | 0 | 0 | 0 | 0 | 0 | too many qubits |
| jeff/qft_3 | source | 3 | 3 | 6 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/qft_3 | bqcp | 3 | 3 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft_3 | qiskit_o0 | 3 | 3 | 24 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft_3 | qiskit_o3 | 3 | 3 | 21 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft_3 | tket | 3 | 3 | 15 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft_5 | source | 5 | 5 | 15 | 10 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/qft_5 | bqcp | 5 | 5 | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft_5 | qiskit_o0 | 5 | 5 | 65 | 20 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft_5 | qiskit_o3 | 5 | 5 | 55 | 20 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft_5 | tket | 5 | 5 | 45 | 20 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft_7 | source | 7 | 7 | 28 | 21 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/qft_7 | bqcp | 7 | 7 | 7 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft_7 | qiskit_o0 | 7 | 7 | 126 | 42 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft_7 | qiskit_o3 | 7 | 7 | 105 | 42 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qft_7 | tket | 7 | 7 | 91 | 42 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qpe_3 | source | 3 | 2 | 8 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/qpe_3 | bqcp | 3 | 2 | 8 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qpe_3 | qiskit_o0 | 3 | 2 | 28 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qpe_3 | qiskit_o3 | 3 | 2 | 23 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qpe_3 | tket | 3 | 2 | 16 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qpe_5 | source | 5 | 4 | 19 | 10 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/qpe_5 | bqcp | 5 | 2 | 18 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qpe_5 | qiskit_o0 | 5 | 4 | 75 | 20 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qpe_5 | qiskit_o3 | 5 | 4 | 62 | 19 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qpe_5 | tket | 5 | 4 | 44 | 19 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qpe_7 | source | 7 | 6 | 34 | 21 | 0 | 0 | 0 | 0 | 0 | 0 | reference |
| jeff/qpe_7 | bqcp | 7 | 2 | 22 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qpe_7 | qiskit_o0 | 7 | 6 | 142 | 42 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qpe_7 | qiskit_o3 | 7 | 6 | 105 | 37 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/qpe_7 | tket | 7 | 6 | 81 | 37 | 0 | 0 | 0 | 0 | 0 | 0 | match |
| jeff/repeat-until-success_3 | source | 4 | 2 | 16 | 8 | 11 | 2 | 1 | 10 | 0 | 0 | reference |
| jeff/repeat-until-success_3 | bqcp | 4 | 2 | 16 | 8 | 11 | 2 | 1 | 10 | 0 | 0 | match |
| jeff/repeat-until-success_3 | qiskit_o0 | 4 | 2 | 32 | 8 | 21 | 2 | 1 | 20 | 0 | 0 | match |
| jeff/repeat-until-success_3 | qiskit_o3 | 4 | 2 | 24 | 8 | 15 | 2 | 1 | 14 | 0 | 0 | match |
| jeff/repeat-until-success_3 | tket | n/a: NotImplementedError: Conversion of qiskit's while_loop instruction is currently unsupported by qiskit_to_tk. Consider using QuantumCircuit.de |  |  |  |  |  |  |  |  |  |  |
| jeff/repeat-until-success_5 | source | 6 | 2 | 24 | 14 | 15 | 2 | 1 | 14 | 0 | 0 | reference |
| jeff/repeat-until-success_5 | bqcp | 6 | 2 | 24 | 14 | 15 | 2 | 1 | 14 | 0 | 0 | match |
| jeff/repeat-until-success_5 | qiskit_o0 | 6 | 2 | 44 | 14 | 25 | 2 | 1 | 24 | 0 | 0 | match |
| jeff/repeat-until-success_5 | qiskit_o3 | 6 | 2 | 36 | 14 | 19 | 2 | 1 | 18 | 0 | 0 | match |
| jeff/repeat-until-success_5 | tket | n/a: NotImplementedError: Conversion of qiskit's while_loop instruction is currently unsupported by qiskit_to_tk. Consider using QuantumCircuit.de |  |  |  |  |  |  |  |  |  |  |
| jeff/repeat-until-success_7 | source | 8 | 2 | 32 | 20 | 19 | 2 | 1 | 18 | 0 | 0 | reference |
| jeff/repeat-until-success_7 | bqcp | 8 | 2 | 32 | 20 | 19 | 2 | 1 | 18 | 0 | 0 | match |
| jeff/repeat-until-success_7 | qiskit_o0 | 8 | 2 | 56 | 20 | 29 | 2 | 1 | 28 | 0 | 0 | match |
| jeff/repeat-until-success_7 | qiskit_o3 | 8 | 2 | 48 | 20 | 23 | 2 | 1 | 22 | 0 | 0 | match |
| jeff/repeat-until-success_7 | tket | n/a: NotImplementedError: Conversion of qiskit's while_loop instruction is currently unsupported by qiskit_to_tk. Consider using QuantumCircuit.de |  |  |  |  |  |  |  |  |  |  |
| jeff/teleportation | source | 3 | 3 | 8 | 2 | 2 | 2 | 2 | 0 | 0 | 0 | reference |
| jeff/teleportation | bqcp | 3 | 2 | 7 | 2 | 1 | 1 | 1 | 0 | 0 | 0 | match |
| jeff/teleportation | qiskit_o0 | 3 | 3 | 16 | 2 | 2 | 2 | 2 | 0 | 0 | 0 | match |
| jeff/teleportation | qiskit_o3 | 3 | 3 | 15 | 2 | 2 | 2 | 2 | 0 | 0 | 0 | match |
| jeff/teleportation | tket | 3 | 3 | 8 | 2 | 2 | 2 | 2 | 0 | 0 | 0 | match |
