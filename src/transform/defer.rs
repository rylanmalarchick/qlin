//! Defer: replace a classically controlled top-level If by coherently
//! controlled gates.
//!
//! A candidate is a top-level dynamic If whose condition bits were each
//! last written by a top-level measure, and whose arms hold only gates
//! with a controlled form (see [`controlled`]). Each deferred If reads its
//! bits from a control qubit:
//! - *direct*: the measured qubit itself. This needs no op on that qubit,
//!   no classical reader of the bit, and no new write of the bit between
//!   the measure and the If. The measure then moves to just after the last
//!   direct user.
//!   A user whose gates target the measured qubit cannot use it.
//! - *copy*: otherwise, a fresh ancilla. `cx q anc` goes just before the
//!   measure, and the gates use the ancilla.
//!
//! An If chosen as [`Choice::Relaxed`] stays classical, and its path goes
//! into [`Variant::relaxed`] so that latency replay skips its feedforward
//! wait. This gives the search its lower bound.

use std::collections::{BTreeMap, BTreeSet};
use std::f64::consts::{FRAC_PI_2, FRAC_PI_4};

use crate::ir::{Bit, BitExpr, Block, Gate, Op, OpPath, Program, Qubit};
use crate::latency::Noise;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Choice {
    Classical,
    Defer,
    Relaxed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum Form {
    /// A conjunction of literals `(bit, value)`, distinct bits.
    Lits(Vec<(Bit, bool)>),
    /// An XOR of distinct bits.
    Xor(Vec<Bit>),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Candidate {
    /// Index of the If in the top-level body.
    pub index: usize,
    form: Form,
    /// For each condition bit: the top-level index and qubit of the
    /// measure that last wrote it.
    sources: BTreeMap<Bit, (usize, Qubit)>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Variant {
    pub prog: Program,
    /// Paths (in `prog`) of the Ifs chosen as relaxed.
    pub relaxed: BTreeSet<OpPath>,
    /// Multi-qubit gates added: controlled gates and copy CNOTs.
    pub added_2q: usize,
    pub added_qubits: usize,
}

fn literals(e: &BitExpr) -> Option<Vec<(Bit, bool)>> {
    match e {
        BitExpr::Bit(b) => Some(vec![(*b, true)]),
        BitExpr::Not(inner) => match &**inner {
            BitExpr::Bit(b) => Some(vec![(*b, false)]),
            _ => None,
        },
        BitExpr::And(a, b) => {
            let mut l = literals(a)?;
            l.extend(literals(b)?);
            Some(l)
        }
        _ => None,
    }
}

fn xor_bits(e: &BitExpr) -> Option<Vec<Bit>> {
    match e {
        BitExpr::Bit(b) => Some(vec![*b]),
        BitExpr::Xor(a, b) => {
            let mut l = xor_bits(a)?;
            l.extend(xor_bits(b)?);
            Some(l)
        }
        _ => None,
    }
}

fn form(cond: &BitExpr) -> Option<Form> {
    let distinct = |bits: &[Bit]| bits.iter().collect::<BTreeSet<_>>().len() == bits.len();
    if let Some(l) = literals(cond) {
        let bits: Vec<Bit> = l.iter().map(|x| x.0).collect();
        return distinct(&bits).then_some(Form::Lits(l));
    }
    let x = xor_bits(cond)?;
    (x.len() >= 2 && distinct(&x)).then_some(Form::Xor(x))
}

/// The singly controlled form of a 1-qubit gate, as (gate, params).
pub fn controlled(gate: &Gate, params: &[f64]) -> Option<(Gate, Vec<f64>)> {
    Some(match gate {
        Gate::X => (Gate::Cx, vec![]),
        Gate::Y => (Gate::Cy, vec![]),
        Gate::Z => (Gate::Cz, vec![]),
        Gate::H => (Gate::Ch, vec![]),
        Gate::P => (Gate::Cp, params.to_vec()),
        Gate::Rz => (Gate::Crz, params.to_vec()),
        Gate::S => (Gate::Cp, vec![FRAC_PI_2]),
        Gate::Sdg => (Gate::Cp, vec![-FRAC_PI_2]),
        Gate::T => (Gate::Cp, vec![FRAC_PI_4]),
        Gate::Tdg => (Gate::Cp, vec![-FRAC_PI_4]),
        _ => return None,
    })
}

fn arm_ok(arm: &Block, form: &Form) -> bool {
    arm.iter().all(|op| match op {
        Op::Gate {
            gate,
            qubits,
            params,
        } if qubits.len() == 1 => match form {
            Form::Lits(l) if l.len() == 1 => controlled(gate, params).is_some(),
            Form::Lits(l) if l.len() == 2 => *gate == Gate::X,
            Form::Lits(_) => false,
            Form::Xor(_) => matches!(gate, Gate::X | Gate::Y | Gate::Z),
        },
        _ => false,
    })
}

/// The deferrable top-level Ifs of `prog`, in program order.
pub fn candidates(prog: &Program, noise: &Noise) -> Vec<Candidate> {
    let mut out = Vec::new();
    // Top-level measure that last wrote each bit, or None if a nested op
    // wrote it since.
    let mut last: BTreeMap<Bit, Option<(usize, Qubit)>> = BTreeMap::new();
    for (i, op) in prog.body.iter().enumerate() {
        if let Op::If { cond, then_, else_ } = op {
            let f = form(cond);
            let mut sources = BTreeMap::new();
            let found = cond.bits().into_iter().all(|b| match last.get(&b) {
                Some(Some(src)) if !noise.bits.contains(&b) => {
                    sources.insert(b, *src);
                    true
                }
                _ => false,
            });
            if let Some(f) = f {
                let else_ok = else_.is_empty() || matches!(&f, Form::Lits(l) if l.len() == 1);
                if found
                    && else_ok
                    && !noise.is_noise_if(cond)
                    && arm_ok(then_, &f)
                    && arm_ok(else_, &f)
                {
                    out.push(Candidate {
                        index: i,
                        form: f,
                        sources,
                    });
                }
            }
        }
        match op {
            Op::Measure { q, b } => {
                last.insert(*b, Some((i, *q)));
            }
            other => {
                for b in other.footprint().writes {
                    last.insert(b, None);
                }
            }
        }
    }
    out
}

/// How a deferred If reads one of its bits.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Source {
    Direct(Qubit),
    Copy(Qubit),
}

/// Applies `choices` (one per candidate) to `prog`.
pub fn apply(prog: &Program, cands: &[Candidate], choices: &[Choice]) -> Variant {
    assert_eq!(cands.len(), choices.len(), "one choice per candidate");
    let body = &prog.body;
    let deferred: BTreeMap<usize, &Candidate> = cands
        .iter()
        .zip(choices)
        .filter(|(_, c)| **c == Choice::Defer)
        .map(|(c, _)| (c.index, c))
        .collect();

    // For each (bit, measure index): which deferred users read it directly
    // and which need a copy.
    let mut users: BTreeMap<(Bit, usize), Vec<usize>> = BTreeMap::new();
    for c in deferred.values() {
        for (b, (mi, _)) in &c.sources {
            users.entry((*b, *mi)).or_default().push(c.index);
        }
    }
    let mut source: BTreeMap<(usize, Bit), Source> = BTreeMap::new();
    // Measures that move: measure index -> index after which it goes.
    let mut moved_after: BTreeMap<usize, usize> = BTreeMap::new();
    let mut copies: BTreeMap<usize, Vec<(Qubit, Qubit)>> = BTreeMap::new();
    let mut next_qubit = prog.n_qubits;
    let mut added_2q = 0;
    for ((b, mi), idxs) in &users {
        let Op::Measure { q, .. } = body[*mi] else {
            unreachable!("candidate sources are top-level measures")
        };
        let blocked = (mi + 1..body.len()).find(|&k| {
            if deferred.get(&k).is_some_and(|c| c.sources.contains_key(b)) {
                return false;
            }
            let fp = body[k].footprint();
            fp.qubits.contains(&q) || fp.reads.contains(b) || fp.writes.contains(b)
        });
        let mut last_direct = None;
        let mut anc = None;
        for &k in idxs {
            // A gate that targets the measured qubit cannot use it as the
            // control, so that user reads a copy.
            let targets_q = body[k].footprint().qubits.contains(&q);
            if blocked.is_none_or(|x| k < x) && !targets_q {
                source.insert((k, *b), Source::Direct(q));
                last_direct = Some(last_direct.map_or(k, |d: usize| d.max(k)));
            } else {
                let a = *anc.get_or_insert_with(|| {
                    next_qubit += 1;
                    Qubit(next_qubit - 1)
                });
                source.insert((k, *b), Source::Copy(a));
            }
        }
        if let Some(a) = anc {
            copies.entry(*mi).or_default().push((q, a));
            added_2q += 1;
        }
        if let Some(d) = last_direct {
            moved_after.insert(*mi, d);
        }
    }

    let relaxed_idx: BTreeSet<usize> = cands
        .iter()
        .zip(choices)
        .filter(|(_, c)| **c == Choice::Relaxed)
        .map(|(c, _)| c.index)
        .collect();
    let mut out = Block::new();
    let mut relaxed = BTreeSet::new();
    let emit_measure = |out: &mut Block, mi: usize| {
        for (q, a) in copies.get(&mi).into_iter().flatten() {
            out.push(Op::Gate {
                gate: Gate::Cx,
                qubits: vec![*q, *a],
                params: vec![],
            });
        }
        out.push(body[mi].clone());
    };
    for (k, op) in body.iter().enumerate() {
        if moved_after.contains_key(&k) {
            // Emitted after its last direct user.
        } else if copies.contains_key(&k) {
            emit_measure(&mut out, k);
        } else if let Some(c) = deferred.get(&k) {
            let Op::If { then_, else_, .. } = op else {
                unreachable!("candidates are Ifs")
            };
            let ctrl = |b: &Bit| match source[&(k, *b)] {
                Source::Direct(q) | Source::Copy(q) => q,
            };
            added_2q += emit_deferred(&c.form, then_, else_, &ctrl, &mut out);
        } else {
            if relaxed_idx.contains(&k) {
                relaxed.insert(vec![out.len()]);
            }
            out.push(op.clone());
        }
        for (&mi, _) in moved_after.iter().filter(|(_, &after)| after == k) {
            emit_measure(&mut out, mi);
        }
    }
    Variant {
        prog: Program {
            n_qubits: next_qubit,
            n_bits: prog.n_bits,
            body: out,
        },
        relaxed,
        added_2q,
        added_qubits: (next_qubit - prog.n_qubits) as usize,
    }
}

fn x(q: Qubit) -> Op {
    Op::Gate {
        gate: Gate::X,
        qubits: vec![q],
        params: vec![],
    }
}

/// Emits the coherent form of one If. Returns the multi-qubit gates added.
fn emit_deferred(
    form: &Form,
    then_: &Block,
    else_: &Block,
    ctrl: &dyn Fn(&Bit) -> Qubit,
    out: &mut Block,
) -> usize {
    let target = |op: &Op| match op {
        Op::Gate { qubits, .. } => qubits[0],
        _ => unreachable!("candidate arms hold 1-qubit gates"),
    };
    let base = |op: &Op| match op {
        Op::Gate { gate, params, .. } => (gate.clone(), params.clone()),
        _ => unreachable!("candidate arms hold 1-qubit gates"),
    };
    let mut added = 0;
    match form {
        Form::Lits(lits) => {
            // A 0-literal is flipped to 1 by X on its control, then back.
            let arms: [(&Block, bool); 2] = [(then_, true), (else_, false)];
            for (arm, sense) in arms {
                if arm.is_empty() {
                    continue;
                }
                let flips: Vec<Qubit> = lits
                    .iter()
                    .filter(|(_, v)| *v != sense)
                    .map(|(b, _)| ctrl(b))
                    .collect();
                out.extend(flips.iter().map(|&q| x(q)));
                for op in arm {
                    let (g, p) = base(op);
                    let t = target(op);
                    let (gate, params, mut qubits) = if lits.len() == 1 {
                        let (cg, cp) = controlled(&g, &p).expect("checked by candidates");
                        (cg, cp, vec![ctrl(&lits[0].0)])
                    } else {
                        (
                            Gate::Ccx,
                            vec![],
                            lits.iter().map(|(b, _)| ctrl(b)).collect(),
                        )
                    };
                    qubits.push(t);
                    out.push(Op::Gate {
                        gate,
                        qubits,
                        params,
                    });
                    added += 1;
                }
                out.extend(flips.iter().map(|&q| x(q)));
            }
        }
        Form::Xor(bits) => {
            for op in then_ {
                let (g, p) = base(op);
                let (cg, cp) = controlled(&g, &p).expect("checked by candidates");
                for b in bits {
                    out.push(Op::Gate {
                        gate: cg.clone(),
                        qubits: vec![ctrl(b), target(op)],
                        params: cp.clone(),
                    });
                    added += 1;
                }
            }
        }
    }
    added
}
