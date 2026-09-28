# Phase 4 results (G4)

Labels: modeled (qlin replay), emulated (Selene), measured (device). The
only measured numbers are in item 3 (ibm_kingston, 2026-09-27).

## G4 item 1: sourced presets

HERON_KINGSTON: every value has a tagged source line in
notes/cost-sources.txt, and `cost::tests::kingston_values_match_their_source_lines`
checks the file against the code. Gates, measure, and reset come from the
FakeKingston calibration snapshot (2026-04-15). t_ff comes from
arXiv:2604.03360. t_3q and t_branch are assumed, with the reason stated.
One conflict is recorded: the snapshot's mid-circuit measure is 1760 ns,
and dynamarq's "65% shorter" gives 798 ns. No Helios preset: arXiv:2511.05465
gives a 2q gate time only, and Helios time is dominated by transport and
cooling (55 ms per depth-1 layer), which the per-op model does not represent.

## G4 item 2: Selene and sensitivity

Selene SimpleRuntime is serial and has no feedforward cost
(notes/selene-timing.txt), so it cannot test scheduling. Two checks
replace the planned cross-check:

- Accounting check (emulated, results/phase4_selene.md): on 220 program
  variants of 44 benchmarks, 39988 of 44000 shots take exactly the time
  that qlin's per-outcome trace predicts (199 of 220 variants exact on
  every shot). One lowering rule was learned from the misses: a
  non-destructive measure with outcome 1 costs one extra rxy. The residual
  misses come from Selene's compile-time gate cancellation (a probe shows
  `x q0` twice compiles to no op). In the recorded misses, qlin predicts 64 or
  128 ns more than Selene, at most 0.17% of the shot.
- Distribution check (emulated, bench/test_guppy.py): every benchmark with
  at most 12 qubits gives the same output distribution on Selene as `qlin
  sim`, within the stated sampling tolerance. A planted wrong gate fails.
- Sensitivity (modeled, results/phase4_sensitivity.md), over t_meas
  1760-4000, t_ff 224-700, t_branch 0-1000 ns:
  - Defer beating M0 holds at all 12 (t_meas, t_ff) points on 9
    benchmarks and at none on 17. The conclusion does not flip inside the
    sourced ranges.
  - The fast-path gain (>= 10%) depends only on t_branch, which has no
    source: at t_branch = 0 it holds on no benchmark, at 200 ns on the
    repetition5 codes, at 1000 ns also on the five-qubit code.
  - The Phase 3 five-qubit gain at t_branch = 200 (16% under HERON_LIKE)
    does not hold under HERON_KINGSTON at any grid point.

## G4 item 3: IBM

Run on ibm_kingston (Open Plan, 60 s of device time, results/phase4_ibm.md).
- Measured: a branch-cost probe gives 3.45 us per if_else block (95% CI
  0.32 to 6.58 us). This is the first measured value for t_branch.
- Not resolvable: the teleportation variants differ by 2 to 7 us in the
  model, below the 7.7 us job-to-job noise. No ranking claim.
- Failed: five_qubit_code and repetition5 variants, IBM error 1500,
  likely from aliased multi-bit registers in the bridge (not verified).
- Not runnable on IBM: the fast path (a measure inside a conditional,
  nested conditionals, no switch_case).

## G4 item 4

The gate passes on this report. The model is not falsified or confirmed
on a device. What holds: the sourced values, the per-outcome op
accounting (against Selene), the defer conclusion across the sourced
ranges, and a measured bound on t_branch. What is open: every
scheduling ranking on a device.
