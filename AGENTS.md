# AGENTS.md

## Structure

- `src/ir.rs`: IR types (`Program`, `Op`, `Gate`, `BitExpr`).
- `src/builder.rs`: builder API for programs in code.
- `src/text.rs`: `.qlin` parser and printer.
- `src/analysis/`: def-use over bits and dynamic-core marking.
- `src/trace.rs`: per-outcome trace enumerator.
- `src/sim.rs`: dense state-vector simulator, test oracle only.
- `tests/`: integration tests. `benchmarks/hand/`: hand-written programs.

## Build and test

- `cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test`
- CI runs the same three commands.

## Gotchas

- The IR has no static loops. `repeat N` unrolls in the parser.
- Gate angles are constants. A bit-dependent angle is an `If`.
- Bit constant folding uses only bits with a known classical value. It
  never infers a bit value from a quantum state.
- The simulator rejects programs with more than 12 qubits.
