//! Pauli sink: move a classically controlled Pauli correction forward.
//!
//! A Pauli If is a dynamic top-level If whose arms are products of x, y,
//! and z gates. It moves forward past each following op that either
//! shares no qubit with it and has no bit conflict, or is a Clifford gate
//! on its qubits. In the second case both arm Paulis are conjugated
//! through the gate. It stops at any other op. Noise Ifs do not move.
//!
//! In the Block latency model an If stalls its qubits until its condition
//! is known. After the sink, the Clifford ops no longer wait for it.

use crate::ir::{Block, Op, Program};
use crate::latency::Noise;
use crate::pauli::{conjugate, from_block, is_clifford, to_ops};

#[derive(Clone, Debug, PartialEq)]
pub struct Sunk {
    pub prog: Program,
    /// Pauli Ifs that moved, and ops they moved past in total.
    pub moved: usize,
    pub steps: usize,
}

/// Sinks every Pauli If in the top-level body, the last one first.
pub fn sink(prog: &Program, noise: &Noise) -> Sunk {
    let mut body: Block = prog.body.clone();
    let (mut moved, mut steps) = (0, 0);
    for i in (0..body.len()).rev() {
        let Op::If { cond, then_, else_ } = &body[i] else {
            continue;
        };
        if noise.is_noise_if(cond) {
            continue;
        }
        let (Some(mut pt), Some(mut pe)) = (from_block(then_), from_block(else_)) else {
            continue;
        };
        let cond = cond.clone();
        let mut at = i;
        for (j, next) in body.iter().enumerate().skip(i + 1) {
            let here = Op::If {
                cond: cond.clone(),
                then_: to_ops(&pt),
                else_: to_ops(&pe),
            }
            .footprint();
            let fp = next.footprint();
            let passes = if here.disjoint(&fp) {
                true
            } else {
                let clifford = matches!(next, Op::Gate { gate, .. } if is_clifford(gate));
                let bits_ok = fp.writes.is_disjoint(&here.reads);
                if clifford && bits_ok {
                    conjugate(&mut pt, next);
                    conjugate(&mut pe, next);
                    true
                } else {
                    false
                }
            };
            if !passes {
                break;
            }
            at = j;
        }
        if at > i {
            moved += 1;
            steps += at - i;
            body.remove(i);
            body.insert(
                at,
                Op::If {
                    cond,
                    then_: to_ops(&pt),
                    else_: to_ops(&pe),
                },
            );
        }
    }
    Sunk {
        prog: Program {
            n_qubits: prog.n_qubits,
            n_bits: prog.n_bits,
            body,
        },
        moved,
        steps,
    }
}
