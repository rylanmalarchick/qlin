# Phase 7.3 results: translation validation in Lean

Every job runs the Lean checkers of lean/Qlin/Check.lean (checkBlock for
source to M0 normal form, checkFP for normal form or sink to fast path,
t = 0, 1, 2). A passing job is covered by checkBlock_sound or
checkFP_sound (standard axioms only). The sink step itself is checked by
simulation, not here.

- 428 of 428 jobs checked
- Jobs not passing: 0


## Skipped

- benchmarks/jeff/qft-adder-quantum_7.qlin : fast path not exported (no outcome records); M0 job only
- benchmarks/jeff/qft-adder-quantum_7.qlin --sink: fast path not exported (no outcome records); M0 job only
