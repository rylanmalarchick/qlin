//! Dynamic-core analysis under move set M0 (hoist, sink, merge, unroll).
//!
//! Rule, for `If(c, A, B)`:
//! 1. Fold `c` with the bits whose classical value is known. A bit is known
//!    only before any op writes it (it holds 0). The analysis never infers a
//!    bit from a quantum state.
//! 2. If `c` is constant, the If is not dynamic. The live arm is analyzed in
//!    place, and every leaf in the other arm is dead.
//! 3. Else hoist the common prefix and merge the common suffix of A and B.
//!    Ops match by structural equality. An op may move past other ops in its
//!    arm only when their footprints are disjoint (no shared qubit, no bit
//!    conflict). A hoisted op may not write a bit that `c` reads.
//! 4. Matched ops are movable. Every leaf in an unmatched op is core.
//!
//! For `Loop`, the first iteration is unconditional (unroll peels it). Every
//! leaf in the body also runs again on a measured condition, so it is core
//! with kind [`CoreKind::LoopRepeat`]. A loop whose exit folds to `true`
//! runs once and is not dynamic.
//!
//! Counts: `feedforward` is the number of dynamic conditions. `measurements`
//! is the number of live measure ops, with a matched pair counted once.

use std::collections::BTreeSet;

use crate::ir::{Bit, BitExpr, Block, Footprint, Op, OpPath, Program};

/// Conditions with more unknown bits than this are not folded.
const MAX_FOLD_BITS: usize = 16;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum CoreKind {
    /// In an arm of a dynamic If, with no match in the other arm.
    Branch,
    /// In the body of a dynamic loop, so it repeats on a measured bit.
    LoopRepeat,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct CoreReport {
    /// Core leaves, sorted by path.
    pub core: Vec<(OpPath, CoreKind)>,
    /// Matched leaf pairs (then-arm path, else-arm path), sorted.
    pub movable: Vec<(OpPath, OpPath)>,
    /// Leaves in arms that constant folding proves never run, sorted.
    pub dead: Vec<OpPath>,
    pub feedforward: usize,
    pub measurements: usize,
}

pub fn core(prog: &Program) -> CoreReport {
    let mut w = Walker::default();
    let mut known: Known = vec![Some(false); prog.n_bits as usize];
    w.block(&prog.body, &[], &mut known, Mode::Static);
    w.report.core.sort();
    w.report.movable.sort();
    w.report.dead.sort();
    w.report
}

/// Per bit: `Some(v)` when its classical value is known, else `None`.
pub type Known = Vec<Option<bool>>;

/// Returns the constant value of `cond` over every value of its unknown
/// bits, or `None` if it is not constant.
pub fn fold(cond: &BitExpr, known: &Known) -> Option<bool> {
    let unknown: Vec<Bit> = cond
        .bits()
        .into_iter()
        .filter(|b| known[b.0 as usize].is_none())
        .collect();
    if unknown.len() > MAX_FOLD_BITS {
        return None;
    }
    let mut seen = [false; 2];
    for mask in 0u32..(1u32 << unknown.len()) {
        let value = |b: Bit| match known[b.0 as usize] {
            Some(v) => v,
            None => {
                let i = unknown
                    .iter()
                    .position(|u| *u == b)
                    .expect("every unknown bit of cond is in `unknown`");
                (mask >> i) & 1 == 1
            }
        };
        seen[cond.eval(&value) as usize] = true;
    }
    match seen {
        [true, false] => Some(false),
        [false, true] => Some(true),
        _ => None,
    }
}

pub fn writes(blocks: &[&Block]) -> BTreeSet<Bit> {
    blocks
        .iter()
        .flat_map(|b| b.iter())
        .flat_map(|op| op.footprint().writes)
        .collect()
}

fn forget(known: &mut Known, bits: &BTreeSet<Bit>) {
    for b in bits {
        known[b.0 as usize] = None;
    }
}

fn child(path: &[usize], arm: usize, idx: usize) -> OpPath {
    let mut p = path.to_vec();
    p.push(arm);
    p.push(idx);
    p
}

/// Paths of every leaf inside `op`, relative to `op`.
fn leaf_rel_paths(op: &Op) -> Vec<OpPath> {
    let arms: Vec<&Block> = match op {
        Op::If { then_, else_, .. } => vec![then_, else_],
        Op::Loop { body, .. } => vec![body],
        _ => return vec![vec![]],
    };
    let mut out = Vec::new();
    for (arm, block) in arms.into_iter().enumerate() {
        for (i, inner) in block.iter().enumerate() {
            for rel in leaf_rel_paths(inner) {
                let mut p = vec![arm, i];
                p.extend(rel);
                out.push(p);
            }
        }
    }
    out
}

/// Indices in `rem` whose op may move to the front of `rem`.
fn front_candidates(rem: &[usize], fps: &[Footprint]) -> Vec<usize> {
    (0..rem.len())
        .filter(|&k| rem[..k].iter().all(|&e| fps[rem[k]].disjoint(&fps[e])))
        .collect()
}

/// Indices in `rem` whose op may move to the back of `rem`, last first.
fn back_candidates(rem: &[usize], fps: &[Footprint]) -> Vec<usize> {
    (0..rem.len())
        .rev()
        .filter(|&k| rem[k + 1..].iter().all(|&e| fps[rem[k]].disjoint(&fps[e])))
        .collect()
}

/// The result of matching two arms. Pairs are `(index in a, index in b)`,
/// in the order they were matched.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Matches {
    /// Moved to the front, in order: place them before the If in this order.
    pub hoisted: Vec<(usize, usize)>,
    /// Moved to the back, last first: place them after the If in reverse.
    pub merged: Vec<(usize, usize)>,
    pub rest_a: Vec<usize>,
    pub rest_b: Vec<usize>,
}

/// Matches ops of `a` and `b` by hoist, then merge.
pub fn match_arms(cond: &BitExpr, a: &Block, b: &Block) -> Matches {
    let fa: Vec<Footprint> = a.iter().map(Op::footprint).collect();
    let fb: Vec<Footprint> = b.iter().map(Op::footprint).collect();
    let cond_bits = cond.bits();
    let mut rem_a: Vec<usize> = (0..a.len()).collect();
    let mut rem_b: Vec<usize> = (0..b.len()).collect();
    let (mut hoisted, mut merged) = (Vec::new(), Vec::new());

    for _ in 0..a.len().min(b.len()) {
        let cb = front_candidates(&rem_b, &fb);
        let found = front_candidates(&rem_a, &fa)
            .into_iter()
            .filter(|&ka| fa[rem_a[ka]].writes.is_disjoint(&cond_bits))
            .find_map(|ka| {
                cb.iter()
                    .find(|&&kb| a[rem_a[ka]] == b[rem_b[kb]])
                    .map(|&kb| (ka, kb))
            });
        let Some((ka, kb)) = found else { break };
        hoisted.push((rem_a.remove(ka), rem_b.remove(kb)));
    }

    for _ in 0..rem_a.len().min(rem_b.len()) {
        let cb = back_candidates(&rem_b, &fb);
        let found = back_candidates(&rem_a, &fa).into_iter().find_map(|ka| {
            cb.iter()
                .find(|&&kb| a[rem_a[ka]] == b[rem_b[kb]])
                .map(|&kb| (ka, kb))
        });
        let Some((ka, kb)) = found else { break };
        merged.push((rem_a.remove(ka), rem_b.remove(kb)));
    }

    Matches {
        hoisted,
        merged,
        rest_a: rem_a,
        rest_b: rem_b,
    }
}

#[derive(Clone, Copy, Debug)]
enum Mode {
    /// Outside any dynamic region. Leaves are not core.
    Static,
    /// Inside a dynamic loop body. Leaves are core as `LoopRepeat`.
    Loop,
    /// Inside an unmatched op of a dynamic If. Leaves are core.
    Core(CoreKind),
}

#[derive(Default)]
struct Walker {
    report: CoreReport,
}

impl Walker {
    fn block(&mut self, block: &Block, prefix: &[usize], known: &mut Known, mode: Mode) {
        for (i, op) in block.iter().enumerate() {
            let mut p = prefix.to_vec();
            p.push(i);
            self.op(op, &p, known, mode);
        }
    }

    fn arm(&mut self, block: &Block, path: &[usize], arm: usize, known: &mut Known, mode: Mode) {
        for (i, op) in block.iter().enumerate() {
            self.op(op, &child(path, arm, i), known, mode);
        }
    }

    fn leaf(&mut self, path: &[usize], mode: Mode) {
        let kind = match mode {
            Mode::Static => return,
            Mode::Loop => CoreKind::LoopRepeat,
            Mode::Core(k) => k,
        };
        self.report.core.push((path.to_vec(), kind));
    }

    fn dead(&mut self, block: &Block, path: &[usize], arm: usize) {
        for (i, op) in block.iter().enumerate() {
            let base = child(path, arm, i);
            for rel in leaf_rel_paths(op) {
                let mut p = base.clone();
                p.extend(rel);
                self.report.dead.push(p);
            }
        }
    }

    fn op(&mut self, op: &Op, path: &[usize], known: &mut Known, mode: Mode) {
        match op {
            Op::Gate { .. } | Op::Reset { .. } => self.leaf(path, mode),
            Op::Measure { b, .. } => {
                self.leaf(path, mode);
                self.report.measurements += 1;
                known[b.0 as usize] = None;
            }
            Op::If { cond, then_, else_ } => {
                match fold(cond, known) {
                    Some(true) => {
                        self.arm(then_, path, 0, known, mode);
                        self.dead(else_, path, 1);
                    }
                    Some(false) => {
                        self.arm(else_, path, 1, known, mode);
                        self.dead(then_, path, 0);
                    }
                    None => {
                        self.report.feedforward += 1;
                        let mut entry = known.clone();
                        forget(&mut entry, &writes(&[then_, else_]));
                        match mode {
                            Mode::Core(_) => {
                                self.arm(then_, path, 0, &mut entry.clone(), mode);
                                self.arm(else_, path, 1, &mut entry.clone(), mode);
                            }
                            Mode::Static | Mode::Loop => {
                                self.dynamic_if(cond, then_, else_, path, &entry, mode)
                            }
                        }
                    }
                }
                forget(known, &writes(&[then_, else_]));
            }
            Op::Loop { body, until, .. } => {
                let w = writes(&[body]);
                let mut after = known.clone();
                forget(&mut after, &w);
                if fold(until, &after) == Some(true) {
                    self.arm(body, path, 0, known, mode);
                } else {
                    self.report.feedforward += 1;
                    let inner = match mode {
                        Mode::Core(k) => Mode::Core(k),
                        Mode::Static | Mode::Loop => Mode::Loop,
                    };
                    self.arm(body, path, 0, &mut after.clone(), inner);
                }
                forget(known, &w);
            }
        }
    }

    fn dynamic_if(
        &mut self,
        cond: &BitExpr,
        then_: &Block,
        else_: &Block,
        path: &[usize],
        entry: &Known,
        mode: Mode,
    ) {
        let m = match_arms(cond, then_, else_);
        let (rest_a, rest_b) = (m.rest_a, m.rest_b);
        let pairs: Vec<(usize, usize)> = m.hoisted.into_iter().chain(m.merged).collect();
        for i in rest_a {
            self.op(
                &then_[i],
                &child(path, 0, i),
                &mut entry.clone(),
                Mode::Core(CoreKind::Branch),
            );
        }
        for j in rest_b {
            self.op(
                &else_[j],
                &child(path, 1, j),
                &mut entry.clone(),
                Mode::Core(CoreKind::Branch),
            );
        }
        for (i, j) in pairs {
            let (pa, pb) = (child(path, 0, i), child(path, 1, j));
            let (n_core, n_dead) = (self.report.core.len(), self.report.dead.len());
            // The matched op runs once, outside the If, in the same mode as
            // the If itself. Only the then-arm copy is walked.
            self.op(&then_[i], &pa, &mut entry.clone(), mode);
            let excluded: BTreeSet<&OpPath> = self.report.core[n_core..]
                .iter()
                .filter(|(_, k)| *k == CoreKind::Branch)
                .map(|(p, _)| p)
                .chain(self.report.dead[n_dead..].iter())
                .collect();
            let mut found = Vec::new();
            for rel in leaf_rel_paths(&then_[i]) {
                let mut a = pa.clone();
                a.extend(&rel);
                if !excluded.contains(&a) {
                    let mut b = pb.clone();
                    b.extend(&rel);
                    found.push((a, b));
                }
            }
            self.report.movable.extend(found);
        }
    }
}
