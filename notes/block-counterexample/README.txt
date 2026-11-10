Block-model counterexample to C1 (2026-11-10)
=============================================

hoist_branch.qlin: a hoist that meets every side condition of
hoist_latency, where the hoisted op is itself an `if`.

  qlin fastpath --t 0 --model MODEL --tff 600 --tbranch 42 --json hoist_branch.qlin

  model   source mean   M0 mean   source worst   M0 worst   (ns)
  ideal   1886          1886      2432           2432
  block   2078          2208      2474           2708

Cause. The block model has a serial controller. In the source the
controller decides the outer `if c0` first (c0 is known early), so
`reset q4` starts early. M0 hoists `if c2 { x q3 }` in front. Now the
controller waits for c2 (known late), and the outer branch and `reset q4`
wait for the controller.

Scope. The ideal model has no controller, and there C1 holds
(lean/Qlin/Latency.lean). In the block model C1 fails for a hoisted
branch: lean/Qlin/Block.lean, theorem hoist_block_can_delay. No benchmark
shows it: M0 is never slower than the source in results/phase8_switch.csv
(650 rows). bench/test_block_counterexample.py pins the numbers above.
