//! Pauli strings up to phase, and their conjugation through Clifford gates.
//!
//! A Pauli string maps each qubit to its (x, z) bits: X = (1, 0),
//! Z = (0, 1), Y = (1, 1). Phases are dropped. Inside one classical branch
//! a phase is global, so it has no effect.

use std::collections::BTreeMap;

use crate::ir::{Gate, Op, Qubit};

pub type PauliString = BTreeMap<Qubit, (bool, bool)>;

fn mul(p: &mut PauliString, q: Qubit, x: bool, z: bool) {
    let e = p.entry(q).or_insert((false, false));
    e.0 ^= x;
    e.1 ^= z;
    if *e == (false, false) {
        p.remove(&q);
    }
}

/// The Pauli product of a block of x, y, z gates, or `None` if the block
/// holds any other op.
pub fn from_block(ops: &[Op]) -> Option<PauliString> {
    let mut p = PauliString::new();
    for op in ops {
        let Op::Gate { gate, qubits, .. } = op else {
            return None;
        };
        let (x, z) = match gate {
            Gate::X => (true, false),
            Gate::Y => (true, true),
            Gate::Z => (false, true),
            _ => return None,
        };
        mul(&mut p, qubits[0], x, z);
    }
    Some(p)
}

/// The gates of a Pauli string, one per qubit.
pub fn to_ops(p: &PauliString) -> Vec<Op> {
    p.iter()
        .map(|(q, xz)| Op::Gate {
            gate: match xz {
                (true, false) => Gate::X,
                (true, true) => Gate::Y,
                _ => Gate::Z,
            },
            qubits: vec![*q],
            params: vec![],
        })
        .collect()
}

fn get(p: &PauliString, q: Qubit) -> (bool, bool) {
    p.get(&q).copied().unwrap_or((false, false))
}

fn set(p: &mut PauliString, q: Qubit, xz: (bool, bool)) {
    if xz == (false, false) {
        p.remove(&q);
    } else {
        p.insert(q, xz);
    }
}

/// True when `gate` is a Clifford gate that [`conjugate`] handles.
pub fn is_clifford(gate: &Gate) -> bool {
    matches!(
        gate,
        Gate::H
            | Gate::S
            | Gate::Sdg
            | Gate::Sx
            | Gate::X
            | Gate::Y
            | Gate::Z
            | Gate::Cx
            | Gate::Cy
            | Gate::Cz
            | Gate::Swap
    )
}

/// Moves `p` forward past the Clifford gate `op`: `p` becomes
/// `C p C^dagger`, so that `p; C` equals `C; p'`. Returns false, and leaves
/// `p` unchanged, if `op` is not a handled Clifford gate.
pub fn conjugate(p: &mut PauliString, op: &Op) -> bool {
    let Op::Gate { gate, qubits, .. } = op else {
        return false;
    };
    match gate {
        Gate::X | Gate::Y | Gate::Z => {}
        Gate::H => {
            let (x, z) = get(p, qubits[0]);
            set(p, qubits[0], (z, x));
        }
        Gate::S | Gate::Sdg => {
            let (x, z) = get(p, qubits[0]);
            set(p, qubits[0], (x, z ^ x));
        }
        Gate::Sx => {
            let (x, z) = get(p, qubits[0]);
            set(p, qubits[0], (x ^ z, z));
        }
        Gate::Cx => {
            let (c, t) = (qubits[0], qubits[1]);
            let ((xc, zc), (xt, zt)) = (get(p, c), get(p, t));
            set(p, c, (xc, zc ^ zt));
            set(p, t, (xt ^ xc, zt));
        }
        Gate::Cz => {
            let (a, b) = (qubits[0], qubits[1]);
            let ((xa, za), (xb, zb)) = (get(p, a), get(p, b));
            set(p, a, (xa, za ^ xb));
            set(p, b, (xb, zb ^ xa));
        }
        Gate::Cy => {
            // CY = S_t CX S_t^dagger, applied in time order.
            let t = qubits[1];
            let s = |g: Gate, q: Qubit| Op::Gate {
                gate: g,
                qubits: vec![q],
                params: vec![],
            };
            conjugate(p, &s(Gate::Sdg, t));
            conjugate(
                p,
                &Op::Gate {
                    gate: Gate::Cx,
                    qubits: qubits.clone(),
                    params: vec![],
                },
            );
            conjugate(p, &s(Gate::S, t));
        }
        Gate::Swap => {
            let (a, b) = (get(p, qubits[0]), get(p, qubits[1]));
            set(p, qubits[0], b);
            set(p, qubits[1], a);
        }
        _ => return false,
    }
    true
}
