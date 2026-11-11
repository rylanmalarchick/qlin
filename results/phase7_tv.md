# Phase 7.3 results: translation validation in Lean

Every job runs Lean checkers of lean/Qlin/Check.lean and
lean/Qlin/CheckLatency.lean. A job source to M0 normal form passes only
if checkBlock (semantics) and checkLat (latency, ideal replay model)
both accept. checkFP checks normal form (or its sink) to fast path, for
t = 0 to 6. checkBlock_sound, checkLat_sound, and checkFP_sound cover a
passing job (standard axioms only). Simulation checks the sink step
itself, not this run.

- 976 of 976 jobs checked
- M0 jobs (semantics and latency): 66
- Jobs not passing: 0
- 66 of 66 M0 jobs move leaves only (checkLatLeaf; a moved branch can add latency in the
  block model, notes/block-counterexample)


## Skipped

- benchmarks/jeff/qft-adder-quantum_7.qlin : fast path not exported (no outcome records); M0 job only
- benchmarks/jeff/qft-adder-quantum_7.qlin --sink: fast path not exported (no outcome records); M0 job only
