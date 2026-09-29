# Phase 4 Selene accounting check

Selene SimpleRuntime is serial (notes/selene-timing.txt). This checks which ops
qlin's traces run on each outcome and the gate lowering, not scheduling.
Durations: HERON_KINGSTON. Emulated.

- Shots with an exact match: 39988 of 44000, over 220 program variants.
- Native op times calibrated: 265.

Residual misses: Selene's compiler cancels adjacent gates at compile time (a probe
shows `x q0; x q0` compiles to no op), so a shot is not always the plain sum of its
per-op times. A per-op model cannot capture that. In the recorded misses (up to 3
per variant), qlin predicts 64 or 128 ns more than Selene, at most 0.17% of the
shot time. The outcome-1 re-preparation cost (finding 5 in
notes/selene-timing.txt) was learned from the first run's misses and is part of the
prediction.

| benchmark | variant | exact / shots | first misses |
|---|---|---|---|
| dynamarq/five_qubit_code_noisy | sink_fast_t1 | 188 / 200 | bits 0010011111100000: qlin 107888, selene 107760; bits 0110001111100000: qlin 107888, selene 107760; bits 0110001111100000: qlin 107888, selene 107760 |
| hand/decode_reset | source | 0 / 200 | bits 11100: qlin 37528, selene 37464; bits 11100: qlin 37528, selene 37464; bits 11100: qlin 37528, selene 37464 |
| hand/decode_reset | m0 | 0 / 200 | bits 11100: qlin 37528, selene 37464; bits 11100: qlin 37528, selene 37464; bits 11100: qlin 37528, selene 37464 |
| hand/decode_reset | best_defer | 0 / 200 | bits 11100: qlin 37528, selene 37464; bits 11100: qlin 37528, selene 37464; bits 11100: qlin 37528, selene 37464 |
| hand/decode_reset | fast_t1 | 0 / 200 | bits 11100: qlin 37528, selene 37464; bits 11100: qlin 37528, selene 37464; bits 11100: qlin 37528, selene 37464 |
| hand/decode_reset | sink_fast_t1 | 0 / 200 | bits 11100: qlin 37528, selene 37464; bits 11100: qlin 37528, selene 37464; bits 11100: qlin 37528, selene 37464 |
| jeff/iqpe_5 | source | 0 / 200 | bits 01100: qlin 37232, selene 37168; bits 01100: qlin 37232, selene 37168; bits 01100: qlin 37232, selene 37168 |
| jeff/iqpe_5 | m0 | 0 / 200 | bits 01100: qlin 37232, selene 37168; bits 01100: qlin 37232, selene 37168; bits 01100: qlin 37232, selene 37168 |
| jeff/iqpe_5 | best_defer | 0 / 200 | bits 01100: qlin 37232, selene 37168; bits 01100: qlin 37232, selene 37168; bits 01100: qlin 37232, selene 37168 |
| jeff/iqpe_5 | fast_t1 | 0 / 200 | bits 01100: qlin 37232, selene 37168; bits 01100: qlin 37232, selene 37168; bits 01100: qlin 37232, selene 37168 |
| jeff/iqpe_5 | sink_fast_t1 | 0 / 200 | bits 01100: qlin 37232, selene 37168; bits 01100: qlin 37232, selene 37168; bits 01100: qlin 37232, selene 37168 |
| jeff/iqpe_7 | source | 0 / 200 | bits 0001100: qlin 50128, selene 50064; bits 0001100: qlin 50128, selene 50064; bits 0001100: qlin 50128, selene 50064 |
| jeff/iqpe_7 | m0 | 0 / 200 | bits 0001100: qlin 50128, selene 50064; bits 0001100: qlin 50128, selene 50064; bits 0001100: qlin 50128, selene 50064 |
| jeff/iqpe_7 | best_defer | 0 / 200 | bits 0001100: qlin 50128, selene 50064; bits 0001100: qlin 50128, selene 50064; bits 0001100: qlin 50128, selene 50064 |
| jeff/iqpe_7 | fast_t1 | 0 / 200 | bits 0001100: qlin 50128, selene 50064; bits 0001100: qlin 50128, selene 50064; bits 0001100: qlin 50128, selene 50064 |
| jeff/iqpe_7 | sink_fast_t1 | 0 / 200 | bits 0001100: qlin 50128, selene 50064; bits 0001100: qlin 50128, selene 50064; bits 0001100: qlin 50128, selene 50064 |
| jeff/qpe_7 | source | 0 / 200 | bits 001100: qlin 42388, selene 42324; bits 001100: qlin 42388, selene 42324; bits 001100: qlin 42388, selene 42324 |
| jeff/qpe_7 | m0 | 0 / 200 | bits 001100: qlin 42388, selene 42324; bits 001100: qlin 42388, selene 42324; bits 001100: qlin 42388, selene 42324 |
| jeff/qpe_7 | best_defer | 0 / 200 | bits 001100: qlin 42388, selene 42324; bits 001100: qlin 42388, selene 42324; bits 001100: qlin 42388, selene 42324 |
| jeff/qpe_7 | fast_t1 | 0 / 200 | bits 001100: qlin 42388, selene 42324; bits 001100: qlin 42388, selene 42324; bits 001100: qlin 42388, selene 42324 |
| jeff/qpe_7 | sink_fast_t1 | 0 / 200 | bits 001100: qlin 42388, selene 42324; bits 001100: qlin 42388, selene 42324; bits 001100: qlin 42388, selene 42324 |

Variants with every shot exact: 199 of 220 (not listed).

## Excluded

- dynamarq/steane: 14 qubits
- dynamarq/steane_noisy: 15 qubits
- jeff/qft-adder-quantum_7: 14 qubits
- jeff/repeat-until-success_3 source: has a loop
- jeff/repeat-until-success_3 m0: has a loop
- jeff/repeat-until-success_3 best_defer: has a loop
- jeff/repeat-until-success_3 fast_t1: has a loop
- jeff/repeat-until-success_3 sink_fast_t1: has a loop
- jeff/repeat-until-success_5 source: has a loop
- jeff/repeat-until-success_5 m0: has a loop
- jeff/repeat-until-success_5 best_defer: has a loop
- jeff/repeat-until-success_5 fast_t1: has a loop
- jeff/repeat-until-success_5 sink_fast_t1: has a loop
- jeff/repeat-until-success_7 source: has a loop
- jeff/repeat-until-success_7 m0: has a loop
- jeff/repeat-until-success_7 best_defer: has a loop
- jeff/repeat-until-success_7 fast_t1: has a loop
- jeff/repeat-until-success_7 sink_fast_t1: has a loop
