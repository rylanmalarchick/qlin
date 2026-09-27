//! Fast path over the outcome budget M_t.
//!
//! A dispatch group is a maximal run of consecutive top-level dynamic Ifs
//! whose condition bits are all written before the run and not written
//! inside it. At each group the fast path emits one Switch over the group
//! bits. It has a case for every assignment whose weight (bits that differ
//! from the reference r) fits the remaining budget. A case runs the arms
//! that the assignment selects, then the fast path of the rest with the
//! budget reduced. The default is the exit edge: the original group and
//! the rest, unchanged (the fallback). Nothing specialized runs before the
//! exit, so no compensation is needed.
//!
//! The reference r at a group is, per bit, the more likely value at that
//! point (from the outcome records, ties to 0).

use std::collections::BTreeMap;

use serde::Serialize;

use crate::analysis::core::{fold, Known};
use crate::ir::{Bit, Block, Op, Program};
use crate::latency::{Noise, Record};

/// Groups with more bits than this stay generic.
pub const MAX_GROUP_BITS: usize = 12;

#[derive(Clone, Debug, Serialize)]
pub struct FastPath {
    #[serde(skip)]
    pub prog: Program,
    pub t: usize,
    /// Case blocks emitted in the whole tree.
    pub size: usize,
    /// Groups found in the source.
    pub groups: usize,
    /// Times a group was left generic in some branch of the tree (too many
    /// bits, or the size limit).
    pub generic_groups: usize,
    /// Probability that an outcome leaves M_t (takes a default).
    pub exit_prob: f64,
}

/// A group: top-level index range and its sorted bits.
#[derive(Clone, Debug, PartialEq)]
struct Group {
    start: usize,
    end: usize,
    bits: Vec<Bit>,
}

/// Finds the dispatch groups in `prog`. Noise Ifs end a run.
fn groups(prog: &Program, noise: &Noise) -> Vec<Group> {
    let body = &prog.body;
    let mut known: Known = vec![Some(false); prog.n_bits as usize];
    // Written so far, at top level or nested.
    let mut written = vec![false; prog.n_bits as usize];
    let mut out: Vec<Group> = Vec::new();
    let mut run: Option<Group> = None;
    for (i, op) in body.iter().enumerate() {
        let dynamic_if = match op {
            Op::If { cond, .. } => !noise.is_noise_if(cond) && fold(cond, &known).is_none(),
            _ => false,
        };
        let fp = op.footprint();
        if dynamic_if {
            let bits: Vec<Bit> = fp.reads.iter().copied().collect();
            let ready = bits.iter().all(|b| written[b.0 as usize]);
            let extend = match &run {
                Some(g) => {
                    // The run must not write its own bits.
                    let mut all = g.bits.clone();
                    all.extend(&bits);
                    all.sort();
                    all.dedup();
                    let clash = body[g.start..=i]
                        .iter()
                        .any(|o| all.iter().any(|b| o.footprint().writes.contains(b)));
                    (!clash).then_some(all)
                }
                None => None,
            };
            match (extend, ready) {
                (Some(all), true) => {
                    let g = run.as_mut().expect("extend implies a run");
                    g.end = i + 1;
                    g.bits = all;
                }
                (_, true) if !fp.writes.iter().any(|b| bits.contains(b)) => {
                    out.extend(run.take());
                    run = Some(Group {
                        start: i,
                        end: i + 1,
                        bits,
                    });
                }
                _ => out.extend(run.take()),
            }
        } else {
            out.extend(run.take());
        }
        for b in fp.writes {
            written[b.0 as usize] = true;
            known[b.0 as usize] = None;
        }
    }
    out.extend(run);
    out
}

/// Bit values before each top-level op, for one record, and whether the
/// run took the default arm of a Switch. Stops early if a loop hits its
/// bound.
fn snapshots(prog: &Program, rec: &Record) -> (Vec<Vec<bool>>, bool) {
    struct Walk<'a> {
        rec: &'a Record,
        cursor: BTreeMap<Bit, usize>,
        vals: Vec<bool>,
        stopped: bool,
        took_default: bool,
    }
    impl Walk<'_> {
        fn block(&mut self, ops: &Block) {
            for op in ops {
                if self.stopped {
                    return;
                }
                self.op(op);
            }
        }
        fn op(&mut self, op: &Op) {
            let vals = self.vals.clone();
            let value = |b: Bit| vals[b.0 as usize];
            match op {
                Op::Measure { b, .. } => {
                    let i = self.cursor.entry(*b).or_insert(0);
                    self.vals[b.0 as usize] = self.rec.outcomes[b][*i];
                    *i += 1;
                }
                Op::If { cond, then_, else_ } => {
                    self.block(if cond.eval(&value) { then_ } else { else_ })
                }
                Op::Switch {
                    bits,
                    cases,
                    default,
                } => {
                    let (arm, block) = Op::switch_arm(bits, cases, default, &value);
                    self.took_default |= arm == cases.len();
                    self.block(block)
                }
                Op::Loop {
                    body,
                    until,
                    max_iters,
                } => {
                    let mut exited = false;
                    for _ in 0..*max_iters {
                        self.block(body);
                        let vals = &self.vals;
                        exited = self.stopped || until.eval(&|b: Bit| vals[b.0 as usize]);
                        if exited {
                            break;
                        }
                    }
                    self.stopped |= !exited;
                }
                Op::Gate { .. } | Op::Reset { .. } => {}
            }
        }
    }
    let mut w = Walk {
        rec,
        cursor: BTreeMap::new(),
        vals: vec![false; prog.n_bits as usize],
        stopped: false,
        took_default: false,
    };
    let mut out = Vec::with_capacity(prog.body.len() + 1);
    for op in &prog.body {
        out.push(w.vals.clone());
        if !w.stopped {
            w.op(op);
        }
    }
    out.push(w.vals.clone());
    (out, w.took_default)
}

fn weight(v: &[bool], r: &[bool]) -> usize {
    v.iter().zip(r).filter(|(a, b)| a != b).count()
}

/// The arms that assignment `v` of `bits` selects in `ops`, in order.
fn selected(ops: &[Op], bits: &[Bit], v: &[bool]) -> Block {
    let value = |b: Bit| v[bits.iter().position(|x| *x == b).expect("group bit")];
    let mut out = Block::new();
    for op in ops {
        let Op::If { cond, then_, else_ } = op else {
            unreachable!("groups hold Ifs only")
        };
        out.extend(
            if cond.eval(&value) { then_ } else { else_ }
                .iter()
                .cloned(),
        );
    }
    out
}

struct Builder<'a> {
    body: &'a [Op],
    groups: Vec<(Group, Vec<bool>)>,
    limit: usize,
    size: usize,
    generic: usize,
}

impl Builder<'_> {
    /// Fast path for the ops from `from`, starting at group `g`.
    fn build(&mut self, from: usize, g: usize, budget: usize) -> Block {
        let mut out = Block::new();
        let Some((group, r)) = self.groups.get(g).cloned() else {
            out.extend(self.body[from..].iter().cloned());
            return out;
        };
        out.extend(self.body[from..group.start].iter().cloned());
        let n = group.bits.len();
        let mut assignments: Vec<Vec<bool>> = (0..1usize << n.min(MAX_GROUP_BITS))
            .map(|code| (0..n).map(|i| (code >> i) & 1 == 1).collect())
            .filter(|v: &Vec<bool>| weight(v, &r) <= budget)
            .collect();
        assignments.sort_by_key(|v| (weight(v, &r), v.clone()));
        if n > MAX_GROUP_BITS || self.size + assignments.len() > self.limit {
            self.generic += 1;
            out.extend(self.body[group.start..].iter().cloned());
            return out;
        }
        self.size += assignments.len();
        let mut cases = Vec::with_capacity(assignments.len());
        for v in assignments {
            let mut body = selected(&self.body[group.start..group.end], &group.bits, &v);
            body.extend(self.build(group.end, g + 1, budget - weight(&v, &r)));
            cases.push((v, body));
        }
        out.push(Op::Switch {
            bits: group.bits.clone(),
            cases,
            default: self.body[group.start..].to_vec(),
        });
        out
    }
}

/// Builds the fast path of `prog` for budget `t`, with at most `limit`
/// case blocks. The records give the reference and the exit probability.
pub fn fast_path(
    prog: &Program,
    recs: &[Record],
    noise: &Noise,
    t: usize,
    limit: usize,
) -> FastPath {
    let gs = groups(prog, noise);
    let snaps: Vec<(f64, Vec<Vec<bool>>)> = recs
        .iter()
        .map(|r| (r.prob, snapshots(prog, r).0))
        .collect();
    let with_ref: Vec<(Group, Vec<bool>)> = gs
        .iter()
        .map(|g| {
            let r = g
                .bits
                .iter()
                .map(|b| {
                    let p1: f64 = snaps
                        .iter()
                        .map(|(p, s)| if s[g.start][b.0 as usize] { *p } else { 0.0 })
                        .sum();
                    p1 > 0.5
                })
                .collect();
            (g.clone(), r)
        })
        .collect();
    let mut b = Builder {
        body: &prog.body,
        groups: with_ref,
        limit,
        size: 0,
        generic: 0,
    };
    let body = b.build(0, 0, t);
    let fast = Program {
        n_qubits: prog.n_qubits,
        n_bits: prog.n_bits,
        body,
    };
    // The source has no Switch, so a default taken in `fast` is an exit.
    let exit_prob = recs
        .iter()
        .filter(|r| snapshots(&fast, r).1)
        .map(|r| r.prob)
        .sum();
    FastPath {
        prog: fast,
        t,
        size: b.size,
        groups: gs.len(),
        generic_groups: b.generic,
        exit_prob,
    }
}
