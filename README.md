# qlin

A compiler for dynamic quantum circuits (circuits with mid-circuit
measurement and classical feedforward). qlin finds the part of a program
that must be decided at runtime, precompiles a fast path for likely
measurement outcomes, and keeps a correct fallback for the rest.

Status: early development. The crate has the IR, the `.qlin` text format,
the dynamic-core analysis, a trace enumerator, a small state-vector
simulator used as a test oracle, an importer for jeff files, a
latency model, and a search that chooses which classically controlled
Ifs to replace by coherent control ("defer").

## Build and test

```
cargo build
cargo test
```

Requires Rust 1.85 or later.

## Command line

```
qlin import [--max-iters K] FILE.jeff   # jeff -> .qlin
qlin stats [--json] FILE.qlin           # program metrics
qlin sim FILE.qlin                      # output distribution from |0...0>
qlin fmt FILE.qlin                      # canonical form
qlin json FILE.qlin                     # program tree as JSON
qlin opt [MODEL] [--noise-qubits I] [--check] [--json] FILE.qlin
                                        # defer search, best program or report
qlin fastpath [--t T] [--size S] [--sink] [--check] [MODEL] [--json] FILE.qlin
                                        # fast path over the outcome budget t
qlin lat [MODEL] FILE.qlin              # expected latency
# MODEL: [--model ideal|block] [--tff NS] [--tbranch NS]
```

`qlin fastpath` dispatches each run of Ifs on the same measured bits
through one `switch` with a case for every outcome within the budget t,
and a generic fallback for the rest. `--sink` first moves Pauli
corrections forward through Clifford gates.

`qlin opt` puts the program in M0 normal form (hoist and merge out of
Ifs), then searches the defer choices. Latency is the expected makespan
over exact outcome probabilities (programs up to 12 qubits), under the
`HERON_LIKE` cost model in `src/cost.rs`. `--check` verifies every scored
variant by simulation.

## Baselines

`bench/` runs bqcp, Qiskit, and TKET on every file in `benchmarks/` and
writes `results/phase1.csv`. It needs [uv](https://docs.astral.sh/uv/)
and a clone of [bqcp](https://github.com/1nnocenzo/bqcp).

```
cargo build --release
git clone https://github.com/1nnocenzo/bqcp ~/dev/oss/bqcp   # or set BQCP_PATH
uv run --project bench pytest bench
uv run --project bench python bench/run_baselines.py
```

`bench/export_dynamarq.py` regenerates `benchmarks/dynamarq/`.
`bench/run_phase2.py` runs `qlin opt` on every benchmark over a t_ff sweep
and writes `results/phase2.csv` and `results/phase2.md`.
`bench/run_phase3.py` runs the fast-path sweep under the block model and
writes `results/phase3.csv` and `results/phase3.md`.

## The `.qlin` text format

```
qubits 3
bits 2
h q0
cx q0 q1
measure q0 -> c0
measure q1 -> c1
if c1 { x q2 }
if c0 & !c1 { z q2 } else { h q2 }
repeat 3 { h q0 }
loop max 8 { h q0  measure q0 -> c0 } until c0
```

- `qubits N` and `bits N` come first.
- `opaque NAME ARITY NPARAMS` declares a gate with no matrix. The
  analysis compares it by name. The simulator refuses it.
- A gate is its name, optional parameters in parentheses, then qubits:
  `rz(0.5) q0`, `cx q0 q1`.
- `measure qI -> cJ` writes bit J. `reset qI` resets qubit I.
- `if COND { ... } else { ... }` branches on a bit expression. The
  operators are `!`, `&`, `^`, `|` (tightest first), with parentheses.
  `0` and `1` are constants.
- `repeat N { ... }` unrolls at parse time.
- `loop max K { ... } until COND` runs the body, then exits when COND is
  true. K bounds the number of iterations the analysis explores.
- `switch c0 c1 { case 1 0 { ... } default { ... } }` runs the case whose
  values equal the bits, else the default.
- `#` starts a comment.
