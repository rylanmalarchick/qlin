//! M0 normal form: fold constant Ifs, hoist common prefixes, and merge
//! common suffixes out of dynamic Ifs.
//!
//! [`apply_prefixes`] applies only a prefix of the hoist and merge
//! sequences at each top-level dynamic If. Nested Ifs always get the full
//! normal form. The certifier compares the normal form against every
//! prefix choice.

use crate::analysis::core::{fold, match_arms, writes, Known};
use crate::ir::{BitExpr, Block, Op, Program};

/// Applies every hoist and merge.
pub fn normal_form(prog: &Program) -> Program {
    apply_prefixes(prog, &|_| (usize::MAX, usize::MAX))
}

/// For each top-level dynamic If, in order: how many hoists and merges are
/// available.
pub fn move_counts(prog: &Program) -> Vec<(usize, usize)> {
    let mut known: Known = vec![Some(false); prog.n_bits as usize];
    let mut out = Vec::new();
    for op in &prog.body {
        if let Op::If { cond, then_, else_ } = op {
            if fold(cond, &known).is_none() {
                let m = match_arms(cond, then_, else_);
                out.push((m.hoisted.len(), m.merged.len()));
            }
        }
        forget_op(&mut known, op);
    }
    out
}

/// `choose(k)` gives the (hoists, merges) to apply at the k-th top-level
/// dynamic If.
pub fn apply_prefixes(prog: &Program, choose: &dyn Fn(usize) -> (usize, usize)) -> Program {
    let mut known: Known = vec![Some(false); prog.n_bits as usize];
    let mut k = 0;
    let body = block(&prog.body, &mut known, Some((choose, &mut k)));
    Program {
        n_qubits: prog.n_qubits,
        n_bits: prog.n_bits,
        body,
    }
}

fn forget_op(known: &mut Known, op: &Op) {
    for b in op.footprint().writes {
        known[b.0 as usize] = None;
    }
}

type Top<'a, 'k> = Option<(&'a dyn Fn(usize) -> (usize, usize), &'k mut usize)>;

fn block(ops: &[Op], known: &mut Known, mut top: Top<'_, '_>) -> Block {
    let mut out = Block::new();
    for op in ops {
        match op {
            Op::If { cond, then_, else_ } => match fold(cond, known) {
                Some(true) => out.extend(block(then_, known, None)),
                Some(false) => out.extend(block(else_, known, None)),
                None => {
                    let (h, m) = match top.as_mut() {
                        Some((choose, k)) => {
                            let c = choose(**k);
                            **k += 1;
                            c
                        }
                        None => (usize::MAX, usize::MAX),
                    };
                    dynamic_if(cond, then_, else_, h, m, known, &mut out);
                    for b in writes(&[then_, else_]) {
                        known[b.0 as usize] = None;
                    }
                }
            },
            Op::Loop {
                body,
                until,
                max_iters,
            } => {
                let mut inner = known.clone();
                for b in writes(&[body]) {
                    inner[b.0 as usize] = None;
                }
                let body = block(body, &mut inner, None);
                out.push(Op::Loop {
                    body,
                    until: until.clone(),
                    max_iters: *max_iters,
                });
                forget_op(known, op);
            }
            leaf => {
                out.push(leaf.clone());
                forget_op(known, leaf);
            }
        }
    }
    out
}

/// Normalizes one dynamic If with the first `h` hoists and `m` merges.
fn dynamic_if(
    cond: &BitExpr,
    then_: &Block,
    else_: &Block,
    h: usize,
    m: usize,
    known: &Known,
    out: &mut Block,
) {
    let matches = match_arms(cond, then_, else_);
    let hoisted = &matches.hoisted[..h.min(matches.hoisted.len())];
    let merged = &matches.merged[..m.min(matches.merged.len())];
    let moved_a: Vec<usize> = hoisted.iter().chain(merged).map(|p| p.0).collect();
    let moved_b: Vec<usize> = hoisted.iter().chain(merged).map(|p| p.1).collect();
    let mut entry = known.clone();
    for b in writes(&[then_, else_]) {
        entry[b.0 as usize] = None;
    }
    for &(i, _) in hoisted {
        out.extend(block(
            std::slice::from_ref(&then_[i]),
            &mut entry.clone(),
            None,
        ));
    }
    let keep = |arm: &Block, moved: &[usize]| -> Block {
        let rest: Block = arm
            .iter()
            .enumerate()
            .filter(|(i, _)| !moved.contains(i))
            .map(|(_, o)| o.clone())
            .collect();
        block(&rest, &mut entry.clone(), None)
    };
    let (a, b) = (keep(then_, &moved_a), keep(else_, &moved_b));
    if !a.is_empty() || !b.is_empty() {
        out.push(Op::If {
            cond: cond.clone(),
            then_: a,
            else_: b,
        });
    }
    for &(i, _) in merged.iter().rev() {
        out.extend(block(
            std::slice::from_ref(&then_[i]),
            &mut entry.clone(),
            None,
        ));
    }
}
