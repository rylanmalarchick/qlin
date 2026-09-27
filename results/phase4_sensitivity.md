# Phase 4 sensitivity

Base preset HERON_KINGSTON. Grid (sources in bench/run_phase4_sensitivity.py and
notes/cost-sources.txt): t_meas [1760, 2280, 3000, 4000] ns, t_ff [224, 600, 700] ns, t_branch [0, 200, 1000] ns
(t_branch assumed). All numbers modeled.

D = defer beats M0 (Ideal model), counted over the 12 (t_meas, t_ff) points.
F = fast path or sink gains >= 10% over the best of source, M0, best defer
(Block model), counted over the 12 points, per t_branch.

| benchmark | k | m | D | F tb=0 | F tb=200 | F tb=1000 | gain range tb=0 | gain range tb=1000 |
|---|---|---|---|---|---|---|---|---|
| dynamarq/cnot_ladder4 | 3 | 3 | 12/12 | 0/12 | 0/12 | 0/12 | -104.0% .. -82.3% | -151.9% .. -115.0% |
| dynamarq/fanout4 | 3 | 4 | 12/12 | 0/12 | 0/12 | 0/12 | -97.9% .. -75.5% | -141.4% .. -110.8% |
| dynamarq/five_qubit_code | 5 | 5 | 12/12 | 0/12 | 0/12 | 12/12 | -39.1% .. -24.4% | +32.2% .. +53.7% |
| dynamarq/five_qubit_code_noisy | 5 | 5 | 12/12 | 0/12 | 0/12 | 12/12 | -39.0% .. -24.2% | +32.2% .. +53.7% |
| dynamarq/ghz5 | 4 | 4 | 12/12 | 0/12 | 0/12 | 0/12 | -100.8% .. -79.2% | -146.3% .. -112.2% |
| dynamarq/ipe3 | 3 | 3 | 0/12 | 0/12 | 0/12 | 0/12 | +0.0% .. +0.0% | +0.0% .. +0.0% |
| dynamarq/long_range_cnot3 | 2 | 3 | 12/12 | 0/12 | 0/12 | 0/12 | -112.0% .. -89.3% | -160.9% .. -118.5% |
| dynamarq/repetition3_0 | 3 | 2 | 0/12 | 0/12 | 0/12 | 0/12 | -59.4% .. -19.2% | -77.0% .. -48.2% |
| dynamarq/repetition3_0_noisy | 3 | 2 | 0/12 | 0/12 | 0/12 | 0/12 | -59.5% .. -19.4% | -77.0% .. -48.3% |
| dynamarq/repetition3_1 | 3 | 2 | 0/12 | 0/12 | 0/12 | 0/12 | -54.8% .. -13.7% | -74.7% .. -46.0% |
| dynamarq/repetition3_1_noisy | 3 | 2 | 0/12 | 0/12 | 0/12 | 0/12 | -54.9% .. -13.8% | -74.8% .. -46.1% |
| dynamarq/repetition5_0 | 0 | 4 | 0/12 | 0/12 | 12/12 | 12/12 | +0.0% .. +0.0% | +57.5% .. +72.2% |
| dynamarq/repetition5_0_noisy | 0 | 4 | 0/12 | 0/12 | 12/12 | 12/12 | +0.0% .. +0.0% | +57.5% .. +72.2% |
| dynamarq/repetition5_1 | 0 | 4 | 0/12 | 0/12 | 12/12 | 12/12 | +3.2% .. +6.5% | +56.8% .. +71.1% |
| dynamarq/repetition5_1_noisy | 0 | 4 | 0/12 | 0/12 | 12/12 | 12/12 | +3.1% .. +6.4% | +56.8% .. +71.1% |
| hand/decode_reset | 0 | 2 | 0/12 | 0/12 | 0/12 | 0/12 | +0.0% .. +0.0% | +0.0% .. +0.0% |
| hand/mbqc_chain4 | 4 | 5 | 12/12 | 0/12 | 0/12 | 0/12 | -283.5% .. -213.4% | -386.1% .. -316.2% |
| hand/repetition3 | 3 | 2 | 0/12 | 0/12 | 0/12 | 0/12 | +0.0% .. +0.0% | -10.0% .. +2.0% |
| hand/teleportation | 2 | 2 | 12/12 | 0/12 | 0/12 | 0/12 | -29.7% .. -3.2% | -78.9% .. -26.8% |
| jeff/iqft_3 | 3 | 3 | 0/12 | 0/12 | 0/12 | 0/12 | +0.0% .. +0.0% | +0.0% .. +1.0% |
| jeff/iqft_5 | 10 | 10 | 0/12 | 0/12 | 0/12 | 0/12 | +0.0% .. +0.0% | -3.3% .. -2.0% |
| jeff/iqft_7 | 21 | 21 | 0/12 | 0/12 | 0/12 | 0/12 | +0.0% .. +0.0% | -30.4% .. -16.4% |
| jeff/iqpe_3 | 3 | 3 | 0/12 | 0/12 | 0/12 | 0/12 | +0.0% .. +0.0% | +0.0% .. +0.9% |
| jeff/iqpe_5 | 10 | 10 | 0/12 | 0/12 | 0/12 | 0/12 | +0.0% .. +0.0% | +0.7% .. +1.6% |
| jeff/iqpe_7 | 21 | 21 | 0/12 | 0/12 | 0/12 | 0/12 | +0.0% .. +0.0% | +1.0% .. +2.0% |
| jeff/teleportation | 2 | 2 | 12/12 | 0/12 | 0/12 | 0/12 | -111.6% .. -88.9% | -160.1% .. -118.1% |

No candidates and no dispatch groups (not shown): 21 benchmarks.

## Skipped

- dynamarq/steane: 14 qubits
- dynamarq/steane_noisy: 15 qubits
- jeff/qft-adder-quantum_7: 14 qubits
