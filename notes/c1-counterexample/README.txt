C1 counterexample (found 2026-09-29 while drafting the Lean statement for R4)

Claim C1: the M0 normal form never increases replay latency. It is false
for nested Ifs under the replay model in src/latency.rs.

  c1_nested_hoist.qlin     source
  c1_nested_hoist_nf.qlin  M0 normal form (the measure hoisted out of the
                           inner If)

  target/release/qlin lat notes/c1-counterexample/c1_nested_hoist.qlin
    mean 1532 ns, worst 2232 ns
  target/release/qlin lat notes/c1-counterexample/c1_nested_hoist_nf.qlin
    mean 1690 ns, worst 2864 ns
  target/release/qlin opt --json on the source reports m0 mean 1690 and
  floor 1690, above the source's 1532.

Cause. The hoisted op `measure q0 -> c0` writes c0, a bit that the outer
If reads. Replay::gate_time uses the latest measurement end of each
enclosing condition bit. After the hoist, the measure runs before `x q1`,
so `x q1` waits for the new measurement of c0 plus t_ff. Before the hoist
it waited only for the first one.

The hoist is still semantically sound (the rule conditions of
match_arms hold). Only the latency claim fails.

Merge has the same problem (c1_nested_merge.qlin): `x q1` merged to the
back of the inner If moves past `measure q0 -> c0`, then waits for that
new measurement of c0. Source mean 1348 ns, normal form 1506 ns (before
the fix).

Fix (Rylan, 2026-09-29: restrict the rules, keep the replay model).
match_arms takes the enclosing condition bits (Ifs, Switches, loop exits):
- hoist: the op writes no enclosing bit (and no bit of the If's own
  condition, as before),
- merge: the ops the merged op moves past write no enclosing bit.
tests/m0.rs pins both cases. No benchmark contains the pattern: a scan of
all 50 benchmark files found no measurement inside an If or Switch that
writes a bit an enclosing If or Switch reads.
