//! Per-program metrics. One implementation serves every tool in the
//! baseline table.

use std::collections::BTreeSet;

use serde::Serialize;

use crate::analysis::core::{core, CoreKind};
use crate::ir::{Bit, Block, Op, Program, Qubit};

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Stats {
    pub qubits: u32,
    pub bits: u32,
    /// Live measure ops (a matched pair counts once).
    pub measurements: usize,
    /// Gate ops in the program text, in every arm.
    pub gates: usize,
    /// Gate ops on two or more qubits, in every arm.
    pub gates_2q: usize,
    /// Leaf ops inside an arm of a dynamic If or the body of a dynamic loop.
    pub dynamic_ops: usize,
    /// Dynamic conditions (If and loop exits that do not fold).
    pub feedforward: usize,
    /// Core leaves in dynamic If arms.
    pub core_branch: usize,
    /// Core leaves in dynamic loop bodies.
    pub core_loop: usize,
    /// Matched leaf pairs that hoist or merge out of a dynamic If.
    pub movable: usize,
    /// Leaves in arms that never run.
    pub dead: usize,
}

fn count_gates(block: &Block, all: &mut usize, two: &mut usize) {
    for op in block {
        match op {
            Op::Gate { qubits, .. } => {
                *all += 1;
                if qubits.len() >= 2 {
                    *two += 1;
                }
            }
            Op::If { then_, else_, .. } => {
                count_gates(then_, all, two);
                count_gates(else_, all, two);
            }
            Op::Loop { body, .. } => count_gates(body, all, two),
            Op::Measure { .. } | Op::Reset { .. } => {}
        }
    }
}

pub fn stats(prog: &Program) -> Stats {
    let r = core(prog);
    let (mut gates, mut gates_2q) = (0, 0);
    count_gates(&prog.body, &mut gates, &mut gates_2q);
    let dynamic: BTreeSet<&Vec<usize>> = r
        .core
        .iter()
        .map(|(p, _)| p)
        .chain(r.movable.iter().flat_map(|(a, b)| [a, b]))
        .collect();
    Stats {
        qubits: prog.n_qubits,
        bits: prog.n_bits,
        measurements: r.measurements,
        gates,
        gates_2q,
        dynamic_ops: dynamic.len(),
        feedforward: r.feedforward,
        core_branch: r
            .core
            .iter()
            .filter(|(_, k)| *k == CoreKind::Branch)
            .count(),
        core_loop: r
            .core
            .iter()
            .filter(|(_, k)| *k == CoreKind::LoopRepeat)
            .count(),
        movable: r.movable.len(),
        dead: r.dead.len(),
    }
}

/// Bits written by a measurement of a noise qubit.
pub fn noise_bits(prog: &Program, noise: &BTreeSet<Qubit>) -> BTreeSet<Bit> {
    let mut out = BTreeSet::new();
    collect_noise_bits(&prog.body, noise, &mut out);
    out
}

/// Like [`stats`], but first removes error-injection ops: every leaf op on
/// a noise qubit, and every If whose condition reads only bits measured
/// from a noise qubit. Noise qubits do not count toward `qubits`.
pub fn stats_with_noise(prog: &Program, noise: &BTreeSet<Qubit>) -> Stats {
    let noise_bits = noise_bits(prog, noise);
    let stripped = Program {
        n_qubits: prog.n_qubits,
        n_bits: prog.n_bits,
        body: strip(&prog.body, noise, &noise_bits),
    };
    let mut s = stats(&stripped);
    s.qubits -= noise.iter().filter(|q| q.0 < prog.n_qubits).count() as u32;
    s.bits -= noise_bits.len() as u32;
    s
}

fn collect_noise_bits(block: &Block, noise: &BTreeSet<Qubit>, out: &mut BTreeSet<Bit>) {
    for op in block {
        match op {
            Op::Measure { q, b } if noise.contains(q) => {
                out.insert(*b);
            }
            Op::If { then_, else_, .. } => {
                collect_noise_bits(then_, noise, out);
                collect_noise_bits(else_, noise, out);
            }
            Op::Loop { body, .. } => collect_noise_bits(body, noise, out),
            _ => {}
        }
    }
}

fn strip(block: &Block, noise: &BTreeSet<Qubit>, noise_bits: &BTreeSet<Bit>) -> Block {
    let mut out = Block::new();
    for op in block {
        match op {
            Op::Gate { qubits, .. } if qubits.iter().any(|q| noise.contains(q)) => {}
            Op::Measure { q, .. } | Op::Reset { q } if noise.contains(q) => {}
            Op::If { cond, .. } if !cond.bits().is_empty() && cond.bits().is_subset(noise_bits) => {
            }
            Op::If { cond, then_, else_ } => out.push(Op::If {
                cond: cond.clone(),
                then_: strip(then_, noise, noise_bits),
                else_: strip(else_, noise, noise_bits),
            }),
            Op::Loop {
                body,
                until,
                max_iters,
            } => out.push(Op::Loop {
                body: strip(body, noise, noise_bits),
                until: until.clone(),
                max_iters: *max_iters,
            }),
            other => out.push(other.clone()),
        }
    }
    out
}
