//! Dense state-vector simulator. It is a test oracle, not a product.
//!
//! Qubit `i` is bit `i` of the basis index (little-endian). Every
//! measurement and every reset splits the run into branches, one per
//! outcome with nonzero probability. A branch keeps its probability, its
//! final classical bits, and its normalized state.

use std::collections::BTreeMap;
use std::fmt;

use num_complex::Complex64 as C;

use crate::ir::{Bit, BitExpr, Block, Gate, Op, Program, Qubit};

pub const MAX_QUBITS: u32 = 12;

/// Outcomes with probability at or below this are dropped.
pub const PROB_EPS: f64 = 1e-14;

#[derive(Clone, Debug)]
pub struct Branch {
    /// Measurement outcomes in order. Reset outcomes are not recorded.
    pub outcomes: Vec<(Bit, bool)>,
    pub bits: Vec<bool>,
    pub prob: f64,
    pub state: Vec<C>,
    /// True when a loop hit `max_iters` before its exit condition held.
    pub truncated: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub enum SimError {
    TooManyQubits(u32),
    InitLength { expected: usize, got: usize },
    Unsupported(String),
    TooManyBranches { limit: usize },
}

impl fmt::Display for SimError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SimError::TooManyQubits(n) => {
                write!(f, "{n} qubits is more than the limit of {MAX_QUBITS}")
            }
            SimError::InitLength { expected, got } => {
                write!(f, "initial state has length {got}, expected {expected}")
            }
            SimError::Unsupported(g) => write!(f, "gate `{g}` has no matrix"),
            SimError::TooManyBranches { limit } => {
                write!(f, "run has more than {limit} branches")
            }
        }
    }
}

impl std::error::Error for SimError {}

/// The basis state `|index>` on `n` qubits.
pub fn basis_state(n: u32, index: usize) -> Vec<C> {
    let mut s = vec![C::new(0.0, 0.0); 1 << n];
    s[index] = C::new(1.0, 0.0);
    s
}

/// Sums branch probabilities by final classical bits.
pub fn distribution(branches: &[Branch]) -> BTreeMap<Vec<bool>, f64> {
    let mut out = BTreeMap::new();
    for b in branches {
        *out.entry(b.bits.clone()).or_insert(0.0) += b.prob;
    }
    out
}

type M2 = [[C; 2]; 2];

fn c(re: f64, im: f64) -> C {
    C::new(re, im)
}

fn matrix_1q(gate: &Gate, params: &[f64]) -> Option<M2> {
    let (o, z) = (c(1.0, 0.0), c(0.0, 0.0));
    let r = std::f64::consts::FRAC_1_SQRT_2;
    let half = |i: usize| params[i] / 2.0;
    Some(match gate {
        Gate::H => [[c(r, 0.0), c(r, 0.0)], [c(r, 0.0), c(-r, 0.0)]],
        Gate::X => [[z, o], [o, z]],
        Gate::Y => [[z, c(0.0, -1.0)], [c(0.0, 1.0), z]],
        Gate::Z => [[o, z], [z, -o]],
        Gate::S => [[o, z], [z, c(0.0, 1.0)]],
        Gate::Sdg => [[o, z], [z, c(0.0, -1.0)]],
        Gate::T => [[o, z], [z, C::from_polar(1.0, std::f64::consts::FRAC_PI_4)]],
        Gate::Tdg => [
            [o, z],
            [z, C::from_polar(1.0, -std::f64::consts::FRAC_PI_4)],
        ],
        Gate::Sx => [[c(0.5, 0.5), c(0.5, -0.5)], [c(0.5, -0.5), c(0.5, 0.5)]],
        Gate::Rx => {
            let (s, k) = half(0).sin_cos();
            [[c(k, 0.0), c(0.0, -s)], [c(0.0, -s), c(k, 0.0)]]
        }
        Gate::Ry => {
            let (s, k) = half(0).sin_cos();
            [[c(k, 0.0), c(-s, 0.0)], [c(s, 0.0), c(k, 0.0)]]
        }
        Gate::Rz | Gate::Crz => [
            [C::from_polar(1.0, -half(0)), z],
            [z, C::from_polar(1.0, half(0))],
        ],
        Gate::P | Gate::Cp => [[o, z], [z, C::from_polar(1.0, params[0])]],
        Gate::U => {
            let (th, ph, la) = (params[0], params[1], params[2]);
            let (s, k) = (th / 2.0).sin_cos();
            [
                [c(k, 0.0), -C::from_polar(s, la)],
                [C::from_polar(s, ph), C::from_polar(k, ph + la)],
            ]
        }
        _ => return None,
    })
}

/// Applies `m` to `target` on the basis states where every control is 1.
fn apply_controlled(state: &mut [C], controls: &[Qubit], target: Qubit, m: &M2) {
    let tmask = 1usize << target.0;
    let cmask: usize = controls.iter().map(|q| 1usize << q.0).sum();
    for i in 0..state.len() {
        if i & tmask == 0 && i & cmask == cmask {
            let j = i | tmask;
            let (a, b) = (state[i], state[j]);
            state[i] = m[0][0] * a + m[0][1] * b;
            state[j] = m[1][0] * a + m[1][1] * b;
        }
    }
}

fn apply_gate(
    state: &mut [C],
    gate: &Gate,
    qubits: &[Qubit],
    params: &[f64],
) -> Result<(), SimError> {
    let x = matrix_1q(&Gate::X, &[]).expect("X has a matrix");
    match gate {
        Gate::Cx => apply_controlled(state, &qubits[..1], qubits[1], &x),
        Gate::Cy | Gate::Cz | Gate::Ch | Gate::Cp | Gate::Crz => {
            let base = match gate {
                Gate::Cy => Gate::Y,
                Gate::Cz => Gate::Z,
                Gate::Ch => Gate::H,
                other => other.clone(),
            };
            let m = matrix_1q(&base, params).expect("controlled base gate has a matrix");
            apply_controlled(state, &qubits[..1], qubits[1], &m);
        }
        Gate::Ccx => apply_controlled(state, &qubits[..2], qubits[2], &x),
        Gate::Swap => {
            let (a, b) = (1usize << qubits[0].0, 1usize << qubits[1].0);
            for i in 0..state.len() {
                if i & a != 0 && i & b == 0 {
                    state.swap(i, (i & !a) | b);
                }
            }
        }
        g => {
            let m =
                matrix_1q(g, params).ok_or_else(|| SimError::Unsupported(g.name().to_string()))?;
            apply_controlled(state, &[], qubits[0], &m);
        }
    }
    Ok(())
}

/// Probability that qubit `q` reads 1.
fn prob_one(state: &[C], q: Qubit) -> f64 {
    let m = 1usize << q.0;
    state
        .iter()
        .enumerate()
        .filter(|(i, _)| i & m != 0)
        .map(|(_, a)| a.norm_sqr())
        .sum()
}

/// Projects qubit `q` onto `outcome` and renormalizes.
fn collapse(state: &mut [C], q: Qubit, outcome: bool, p: f64) {
    let m = 1usize << q.0;
    let scale = 1.0 / p.sqrt();
    for (i, a) in state.iter_mut().enumerate() {
        if (i & m != 0) == outcome {
            *a *= scale;
        } else {
            *a = C::new(0.0, 0.0);
        }
    }
}

#[derive(Clone)]
enum Cont<'a> {
    Ops(&'a [Op]),
    LoopTail {
        body: &'a Block,
        until: &'a BitExpr,
        max_iters: u32,
        done: u32,
    },
}

#[derive(Clone)]
struct Run<'a> {
    conts: Vec<Cont<'a>>,
    branch: Branch,
}

/// Runs `prog` from `init` and returns every branch. Fails when there are
/// more than `limit` branches.
pub fn simulate(prog: &Program, init: &[C], limit: usize) -> Result<Vec<Branch>, SimError> {
    if prog.n_qubits > MAX_QUBITS {
        return Err(SimError::TooManyQubits(prog.n_qubits));
    }
    let dim = 1usize << prog.n_qubits;
    if init.len() != dim {
        return Err(SimError::InitLength {
            expected: dim,
            got: init.len(),
        });
    }
    let mut work = vec![Run {
        conts: vec![Cont::Ops(&prog.body)],
        branch: Branch {
            outcomes: Vec::new(),
            bits: vec![false; prog.n_bits as usize],
            prob: 1.0,
            state: init.to_vec(),
            truncated: false,
        },
    }];
    let mut done = Vec::new();
    while let Some(mut run) = work.pop() {
        while let Some(cont) = run.conts.pop() {
            match cont {
                Cont::Ops([]) => {}
                Cont::Ops([op, rest @ ..]) => {
                    run.conts.push(Cont::Ops(rest));
                    step(op, &mut run, &mut work)?;
                }
                Cont::LoopTail {
                    body,
                    until,
                    max_iters,
                    done,
                } => {
                    let bits = &run.branch.bits;
                    if until.eval(&|b: Bit| bits[b.0 as usize]) {
                        // The loop exits. The run continues after it.
                    } else if done < max_iters {
                        run.conts.push(Cont::LoopTail {
                            body,
                            until,
                            max_iters,
                            done: done + 1,
                        });
                        run.conts.push(Cont::Ops(body));
                    } else {
                        run.branch.truncated = true;
                        run.conts.clear();
                    }
                }
            }
            if work.len() + done.len() >= limit {
                return Err(SimError::TooManyBranches { limit });
            }
        }
        done.push(run.branch);
    }
    Ok(done)
}

/// Splits `run` on qubit `q`. If both outcomes are possible, `run` keeps
/// outcome 0 and a clone with outcome 1 goes to `work`. Returns the outcome
/// that `run` keeps.
fn split<'a>(run: &mut Run<'a>, q: Qubit, work: &mut Vec<Run<'a>>) -> bool {
    let p1 = prob_one(&run.branch.state, q);
    let p0 = 1.0 - p1;
    if p0 > PROB_EPS && p1 > PROB_EPS {
        let mut one = run.clone();
        collapse(&mut one.branch.state, q, true, p1);
        one.branch.prob *= p1;
        work.push(one);
        collapse(&mut run.branch.state, q, false, p0);
        run.branch.prob *= p0;
        false
    } else {
        let outcome = p1 > PROB_EPS;
        let p = if outcome { p1 } else { p0 };
        collapse(&mut run.branch.state, q, outcome, p);
        outcome
    }
}

fn step<'a>(op: &'a Op, run: &mut Run<'a>, work: &mut Vec<Run<'a>>) -> Result<(), SimError> {
    match op {
        Op::Gate {
            gate,
            qubits,
            params,
        } => apply_gate(&mut run.branch.state, gate, qubits, params)?,
        Op::Measure { q, b } => {
            let before = work.len();
            let outcome = split(run, *q, work);
            if work.len() > before {
                let one = work.last_mut().expect("split pushed a branch");
                one.branch.bits[b.0 as usize] = true;
                one.branch.outcomes.push((*b, true));
            }
            run.branch.bits[b.0 as usize] = outcome;
            run.branch.outcomes.push((*b, outcome));
        }
        Op::Reset { q } => {
            let before = work.len();
            let x = matrix_1q(&Gate::X, &[]).expect("X has a matrix");
            let outcome = split(run, *q, work);
            if work.len() > before {
                let one = work.last_mut().expect("split pushed a branch");
                apply_controlled(&mut one.branch.state, &[], *q, &x);
            }
            if outcome {
                apply_controlled(&mut run.branch.state, &[], *q, &x);
            }
        }
        Op::If { cond, then_, else_ } => {
            let bits = &run.branch.bits;
            let arm = if cond.eval(&|b: Bit| bits[b.0 as usize]) {
                then_
            } else {
                else_
            };
            run.conts.push(Cont::Ops(arm));
        }
        Op::Switch {
            bits,
            cases,
            default,
        } => {
            let vals = &run.branch.bits;
            let (_, arm) = Op::switch_arm(bits, cases, default, &|b: Bit| vals[b.0 as usize]);
            run.conts.push(Cont::Ops(arm));
        }
        Op::Loop {
            body,
            until,
            max_iters,
        } => {
            run.conts.push(Cont::LoopTail {
                body,
                until,
                max_iters: *max_iters,
                done: 1,
            });
            run.conts.push(Cont::Ops(body));
        }
    }
    Ok(())
}
