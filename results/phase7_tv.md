# Phase 7.3 results: translation validation in Lean

Every job runs a Lean checker of lean/Qlin/Check.lean. checkBlock checks
source to M0 normal form. checkFP checks normal form (or its sink) to
fast path, for t = 0, 1, 2. checkBlock_sound and checkFP_sound cover a
passing job (standard axioms only). Simulation checks the sink step
itself, not this run.

- 428 of 428 jobs checked
- Jobs not passing: 0


## Skipped

- benchmarks/jeff/qft-adder-quantum_7.qlin : fast path not exported (no outcome records); M0 job only
- benchmarks/jeff/qft-adder-quantum_7.qlin --sink: fast path not exported (no outcome records); M0 job only
