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
- `bench/`: Python (uv project). Qiskit bridge, dynamarq export, baseline runner.
- `benchmarks/`: `hand/`, `jeff/` (vendored `.jeff` + golden `.qlin`), `dynamarq/`.
  `benchmarks/SOURCES.txt` records origins and commits.
- `tests/`: integration tests. `benchmarks/hand/`: hand-written programs.

## Build and test

- `cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test`
- CI runs the same three commands.
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
- bqcp has no license. Call it from a clone. Do not copy its code into this repo.
