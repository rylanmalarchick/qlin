# AGENTS.md

## Structure

- `src/ir.rs`: IR types (`Program`, `Op`, `Gate`, `BitExpr`).
- `src/builder.rs`: builder API for programs in code.
- `src/text.rs`: `.qlin` parser and printer.
- `src/analysis/`: def-use over bits and dynamic-core marking.
- `src/trace.rs`: per-outcome trace enumerator.
- `src/sim.rs`: dense state-vector simulator, test oracle only.
- `src/import/jeff.rs`: jeff importer (partial evaluation of the classical part).
- `src/stats.rs`: metrics for the baseline table. `src/bin/qlin.rs`: CLI.
- `src/cost.rs`: cost model. `src/latency.rs`: outcome records and replay latency.
- `src/check.rs`: equivalence check by simulation (distribution + state witnesses).
- `src/transform/m0.rs`: M0 normal form. `src/transform/defer.rs`: defer rewrite.
- `src/search.rs`: exhaustive and branch-and-bound search over defer choices.
- `src/transform/fastpath.rs`: fast path over M_t. `src/transform/sink.rs`:
  Pauli sink. `src/pauli.rs`: Pauli strings and Clifford conjugation.
- `bench/`: Python (uv project). Qiskit bridge, dynamarq export, baseline runner.
- `benchmarks/`: `hand/`, `jeff/` (vendored `.jeff` + golden `.qlin`), `dynamarq/`.
  `benchmarks/SOURCES.txt` records origins and commits.
- `tests/`: integration tests. `benchmarks/hand/`: hand-written programs.
- `lean/`: Lean model and proofs (`Qlin/IR`, `Sem`, `Structure`, `M0`,
  `FastPath`, `Sink`, `PauliTable`, `Latency`, `Negative`). `lean/Axioms.lean`
  lists the theorems that `scripts/lean_axioms.sh` checks.
- `notes/wolfram/`: Wolfram Language checks (`wolfram -script FILE`).

## Build and test

- `cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test`
- Full-suite certifiers: `cargo test --release -- --ignored` (about 8 minutes).
- CI job `fast` runs the first line. CI job `full` runs the certifiers, one
  shard per test file (`defer`, `fastpath`, `m0`, `search`, `sink`). A new
  ignored test in another file needs a new shard.
- Lean: `cd lean && lake build && ../scripts/lean_axioms.sh`. CI job `lean`.
- Python: `cargo build --release`, then `uv run --project bench pytest bench`.
  The bench scripts call `target/release/qlin` (override with `QLIN_BIN`).

## Gotchas

- The IR has no static loops. `repeat N` unrolls in the parser.
- Gate angles are constants. A bit-dependent angle is an `If`.
- Bit constant folding uses only bits with a known classical value. It
  never infers a bit value from a quantum state.
- The simulator rejects programs with more than 12 qubits.
- After changing the importer or the printer, regenerate `benchmarks/jeff/*.qlin`.
  `tests/import_jeff.rs` fails on any drift.
- Latency, the search, and the checks need exact simulation: 12 qubits at most,
  including defer copy qubits. Larger cases are reported as skipped or unchecked.
- Some tests pin exact counts (benchmarks certified, variants checked). A new
  benchmark changes them. Update the pinned number and its comment together.
- Selene streams results over a local socket: consume each shot's results
  while `run_shots` runs (see `bench/selene_run.py`).
- IBM backends have no switch_case: use `to_qiskit(..., switch_as_if=True)`.
- Every value in a cost preset needs a tagged line in `notes/cost-sources.txt`
  (a unit test checks HERON_KINGSTON).
- Lean toolchain and Mathlib are pinned to v4.28.0 (Aristotle's version).
  Do not bump them without a rebuild of every proof.
- A Lean statement is never weakened to make a proof pass. Check with
  `scripts/lean_statements_unchanged.py REV FILE...` against the draft commit.
- A new G5 theorem goes into `lean/Axioms.lean`.
- `match_arms` needs the enclosing condition bits: a hoist or merge that
  ignores them can add latency (notes/c1-counterexample).
- bqcp has no license. Call it from a clone. Do not copy its code into this repo.
