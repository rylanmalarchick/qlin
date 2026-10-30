# qlin

A compiler for dynamic quantum circuits (circuits with mid-circuit
measurement and classical feedforward). qlin finds the part of a program
that must be decided at runtime, precompiles a fast path for likely
measurement outcomes, and keeps the unchanged program as the fallback for
the rest. It also chooses which classically controlled branches to replace
by coherent control ("defer"), against a latency cost model.

## Build and test

Requires Rust 1.85 or later.

```
cargo build --release
cargo test
cargo test --release -- --ignored   # full certifiers, about 8 minutes
```

## Command line

```
qlin import [--max-iters K] FILE.jeff   # jeff -> .qlin
qlin fmt FILE.qlin                      # canonical form
qlin json FILE.qlin                     # program tree as JSON
qlin stats [--json] FILE.qlin           # program metrics
qlin sim FILE.qlin                      # output distribution from |0...0>
qlin traces FILE.qlin                   # every per-outcome trace
qlin lat [MODEL] FILE.qlin              # expected latency
qlin opt [MODEL] [--check] [--json] FILE.qlin
                                        # M0 normal form, then the defer search
qlin fastpath [--t T] [--size S] [--sink] [--check] [MODEL] [--json] FILE.qlin
                                        # fast path over outcomes within t bits of the reference
qlin check [--random N] A.qlin B.qlin   # compare B with A by simulation
qlin sweep [--tmeas-list ..] [--tff-list ..] [--tbranch-list ..] FILE.qlin
                                        # variants scored over a cost grid
qlin tv-export [--t T] [--sink] FILE.qlin
                                        # jobs for the Lean output checker
# MODEL: [--preset heron_like|heron_kingston] [--model ideal|block]
#        [--tff NS] [--tbranch NS] [--tmeas NS] [--t1q NS] [--t2q NS] [--treset NS]
```

`qlin --help` lists every option. The cost presets are in `src/cost.rs`.
`notes/cost-sources.txt` gives the source of each value.

Latency, the search, and `--check` use exact simulation: a dense state
vector up to 12 qubits, and a stabilizer tableau past that. The tableau
runs Clifford programs and one-qubit non-Clifford gates on unentangled
qubits. A program that neither backend can run is reported as skipped.

## Lean proofs

`lean/` holds a Lean 4 model of the IR and its semantics, and proofs that
the rewrite rules (M0, fast path, Pauli sink, direct defer) are sound in a
density-matrix model. It also holds a checker, proved sound, for the
outputs of the M0 and fast-path passes. `lean/Axioms.lean` lists the
theorems that `scripts/lean_axioms.sh` checks.

```
cd lean
lake exe cache get          # Mathlib build cache
lake build
../scripts/lean_axioms.sh   # each listed theorem uses only the standard axioms
```

## Benchmarks and experiments

`benchmarks/` holds the input programs. `benchmarks/SOURCES.txt` records
where each one comes from. `bench/` is a Python (uv) project with the
Qiskit bridge, the baseline runner, and one script per experiment. Each
script writes its result files to `results/`, and its docstring gives the
command to run it.

```
cargo build --release
git clone https://github.com/1nnocenzo/bqcp ~/dev/oss/bqcp   # or set BQCP_PATH
uv run --project bench pytest bench
uv run --project bench python bench/run_baselines.py
```

The scripts call `target/release/qlin`. Set `QLIN_BIN` to use another
binary. The IBM runs (`bench/run_phase4_ibm.py`) need an IBM Quantum
account.

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
