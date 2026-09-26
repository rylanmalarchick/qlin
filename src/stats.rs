//! Per-program metrics. One implementation serves every tool in the
//! baseline table.

use std::collections::BTreeSet;

use serde::Serialize;

use crate::analysis::core::{core, CoreKind};
use crate::ir::{Block, Op, Program};

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
