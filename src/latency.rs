//! Replay latency.
//!
//! For one executed trace, each op starts when its qubits are free. An op
//! inside a classical If or Switch, or in a loop iteration after the
//! first, also waits until each condition bit's measurement ends plus
//! `t_ff`. In the `Block` model, each executed branch is also one step of
//! a serial controller (see `Replay::stall`). The makespan is the finish
//! time of the last op. This is the longest path in a max-plus dependency
//! graph, so it never grows when an edge or a branch is removed or a
//! duration shrinks.
//!
//! Outcome records come from one exact simulation of the source program.
//! Every semantically equal variant is scored on the same records.

use std::collections::{BTreeMap, BTreeSet};
use std::fmt;

use serde::Serialize;

use crate::cost::{CostModel, Sync};
use crate::ir::{Bit, BitExpr, Block, Op, OpPath, Program, Qubit};
use crate::sim::{basis_state, simulate, SimError, MAX_QUBITS};
use crate::stats::noise_bits;

/// One outcome of the source program: each bit's measured values in order.
#[derive(Clone, Debug, PartialEq)]
pub struct Record {
    pub prob: f64,
    pub outcomes: BTreeMap<Bit, Vec<bool>>,
    /// True when a loop hit `max_iters` on this outcome.
    pub truncated: bool,
}

/// Per-bit outcome sequences plus the truncated flag.
type RecordKey = (Vec<(Bit, Vec<bool>)>, bool);

/// Simulates `prog` from |0...0> and returns its outcome records, with
/// equal records merged.
pub fn records(prog: &Program, limit: usize) -> Result<Vec<Record>, SimError> {
    if prog.n_qubits > MAX_QUBITS {
        return Err(SimError::TooManyQubits(prog.n_qubits));
    }
    let branches = simulate(prog, &basis_state(prog.n_qubits, 0), limit)?;
    let mut merged: BTreeMap<RecordKey, f64> = BTreeMap::new();
    for b in branches {
        let mut per_bit: BTreeMap<Bit, Vec<bool>> = BTreeMap::new();
        for (bit, v) in b.outcomes {
            per_bit.entry(bit).or_default().push(v);
        }
        *merged
            .entry((per_bit.into_iter().collect(), b.truncated))
            .or_insert(0.0) += b.prob;
    }
    Ok(merged
        .into_iter()
        .map(|((outcomes, truncated), prob)| Record {
            prob,
            outcomes: outcomes.into_iter().collect(),
            truncated,
        })
        .collect())
}

/// Error-injection ops: ops on noise qubits, and Ifs whose condition reads
/// only bits measured from noise qubits. They cost no time.
#[derive(Clone, Debug, Default)]
pub struct Noise {
    pub qubits: BTreeSet<Qubit>,
    pub bits: BTreeSet<Bit>,
}

impl Noise {
    pub fn none() -> Noise {
        Noise::default()
    }

    pub fn new(prog: &Program, qubits: &BTreeSet<Qubit>) -> Noise {
        Noise {
            qubits: qubits.clone(),
            bits: noise_bits(prog, qubits),
        }
    }

    pub fn is_noise_if(&self, cond: &BitExpr) -> bool {
        let bits = cond.bits();
        !bits.is_empty() && bits.is_subset(&self.bits)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ReplayError {
    /// The variant measures a bit more often than the record has values.
    MissingOutcome(Bit),
}

impl fmt::Display for ReplayError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ReplayError::MissingOutcome(b) => write!(f, "record has no more values for c{}", b.0),
        }
    }
}

impl std::error::Error for ReplayError {}

struct Replay<'a> {
    cost: &'a CostModel,
    noise: &'a Noise,
    relaxed: &'a BTreeSet<OpPath>,
    rec: &'a Record,
    cursor: BTreeMap<Bit, usize>,
    vals: Vec<bool>,
    meas_end: Vec<Option<f64>>,
    ready: Vec<f64>,
    /// Block model: when the controller can decide the next branch.
    controller_free: f64,
    /// Set when a loop hits `max_iters` without its exit. The run stops
    /// there, as in the simulator.
    stopped: bool,
}

impl Replay<'_> {
    fn gate_time(&self, gates: &[Bit]) -> f64 {
        gates
            .iter()
            .filter_map(|b| self.meas_end[b.0 as usize])
            .map(|t| t + self.cost.t_ff)
            .fold(0.0, f64::max)
    }

    /// Block model: the controller decides one branch at a time. A branch
    /// starts when its condition (and any enclosing condition) is known
    /// and the controller is free, and takes `t_branch`. Every qubit of
    /// the branch waits for the decision, taken or not.
    fn stall(&mut self, op: &Op, bits: &[Bit], gates: &[Bit]) {
        if self.cost.sync != Sync::Block {
            return;
        }
        let start = self
            .gate_time(bits)
            .max(self.gate_time(gates))
            .max(self.controller_free);
        let at = start + self.cost.t_branch;
        self.controller_free = at;
        for q in op.footprint().qubits {
            if !self.noise.qubits.contains(&q) {
                let r = &mut self.ready[q.0 as usize];
                *r = r.max(at);
            }
        }
    }

    fn run_leaf(&mut self, qubits: &[Qubit], dur: f64, gates: &[Bit]) -> f64 {
        let start = qubits
            .iter()
            .map(|q| self.ready[q.0 as usize])
            .fold(self.gate_time(gates), f64::max);
        let end = start + dur;
        for q in qubits {
            self.ready[q.0 as usize] = end;
        }
        end
    }

    fn next_outcome(&mut self, b: Bit) -> Result<bool, ReplayError> {
        let i = self.cursor.entry(b).or_insert(0);
        let v = self
            .rec
            .outcomes
            .get(&b)
            .and_then(|vs| vs.get(*i))
            .copied()
            .ok_or(ReplayError::MissingOutcome(b))?;
        *i += 1;
        Ok(v)
    }

    fn block(
        &mut self,
        block: &Block,
        path: &mut OpPath,
        gates: &[Bit],
    ) -> Result<(), ReplayError> {
        for (i, op) in block.iter().enumerate() {
            if self.stopped {
                return Ok(());
            }
            path.push(i);
            self.op(op, path, gates)?;
            path.pop();
        }
        Ok(())
    }

    fn arm(
        &mut self,
        block: &Block,
        path: &mut OpPath,
        arm: usize,
        gates: &[Bit],
    ) -> Result<(), ReplayError> {
        path.push(arm);
        let r = self.block(block, path, gates);
        path.pop();
        r
    }

    fn op(&mut self, op: &Op, path: &mut OpPath, gates: &[Bit]) -> Result<(), ReplayError> {
        let noisy = |qs: &[Qubit]| qs.iter().any(|q| self.noise.qubits.contains(q));
        match op {
            Op::Gate { qubits, .. } => {
                if !noisy(qubits) {
                    self.run_leaf(qubits, self.cost.duration(op), gates);
                }
            }
            Op::Reset { q } => {
                if !noisy(&[*q]) {
                    self.run_leaf(&[*q], self.cost.t_reset, gates);
                }
            }
            Op::Measure { q, b } => {
                let v = self.next_outcome(*b)?;
                self.vals[b.0 as usize] = v;
                if !noisy(&[*q]) {
                    let end = self.run_leaf(&[*q], self.cost.t_meas, gates);
                    self.meas_end[b.0 as usize] = Some(end);
                }
            }
            Op::If { cond, then_, else_ } => {
                let vals = &self.vals;
                let taken = cond.eval(&|b: Bit| vals[b.0 as usize]);
                if self.noise.is_noise_if(cond) {
                    // The injected error is modeled, not scheduled. Its
                    // measurements still consume their recorded values.
                    return self.noise_arm(if taken { then_ } else { else_ });
                }
                let mut inner = gates.to_vec();
                if !self.relaxed.contains(path) {
                    let bits: Vec<Bit> = cond.bits().into_iter().collect();
                    self.stall(op, &bits, gates);
                    inner.extend(bits);
                }
                if taken {
                    self.arm(then_, path, 0, &inner)?;
                } else {
                    self.arm(else_, path, 1, &inner)?;
                }
            }
            Op::Loop {
                body,
                until,
                max_iters,
            } => {
                let mut inner = gates.to_vec();
                let mut exited = false;
                for iter in 0..*max_iters {
                    if iter == 1 {
                        inner.extend(until.bits());
                    }
                    self.arm(body, path, 0, &inner)?;
                    if !self.stopped {
                        let bits: Vec<Bit> = until.bits().into_iter().collect();
                        self.stall(op, &bits, gates);
                    }
                    let vals = &self.vals;
                    exited = self.stopped || until.eval(&|b: Bit| vals[b.0 as usize]);
                    if exited {
                        break;
                    }
                }
                self.stopped |= !exited;
            }
            Op::Switch {
                bits,
                cases,
                default,
            } => {
                let vals = &self.vals;
                let (arm, block) =
                    Op::switch_arm(bits, cases, default, &|b: Bit| vals[b.0 as usize]);
                if bits.iter().all(|b| self.noise.bits.contains(b)) {
                    return self.noise_arm(block);
                }
                let mut inner = gates.to_vec();
                if !self.relaxed.contains(path) {
                    self.stall(op, bits, gates);
                    inner.extend(bits.iter().copied());
                }
                self.arm(block, path, arm, &inner)?;
            }
        }
        Ok(())
    }

    /// Walks a noise arm only to keep the outcome cursors in step.
    fn noise_arm(&mut self, block: &Block) -> Result<(), ReplayError> {
        for op in block {
            if let Op::Measure { b, .. } = op {
                let v = self.next_outcome(*b)?;
                self.vals[b.0 as usize] = v;
            }
        }
        Ok(())
    }
}

/// Makespan of `prog` on one outcome record. Ifs at a path in `relaxed`
/// add no feedforward wait.
pub fn replay(
    prog: &Program,
    rec: &Record,
    cost: &CostModel,
    noise: &Noise,
    relaxed: &BTreeSet<OpPath>,
) -> Result<f64, ReplayError> {
    let mut r = Replay {
        cost,
        noise,
        relaxed,
        rec,
        cursor: BTreeMap::new(),
        vals: vec![false; prog.n_bits as usize],
        meas_end: vec![None; prog.n_bits as usize],
        ready: vec![0.0; prog.n_qubits as usize],
        controller_free: 0.0,
        stopped: false,
    };
    r.block(&prog.body, &mut Vec::new(), &[])?;
    Ok(r.ready.iter().copied().fold(0.0, f64::max))
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
pub struct Expected {
    pub mean: f64,
    pub worst: f64,
    /// Probability mass of records where a loop hit `max_iters`.
    pub truncated_prob: f64,
}

/// Expected and worst-case makespan over the records.
pub fn expected(
    prog: &Program,
    recs: &[Record],
    cost: &CostModel,
    noise: &Noise,
    relaxed: &BTreeSet<OpPath>,
) -> Result<Expected, ReplayError> {
    let mut e = Expected {
        mean: 0.0,
        worst: 0.0,
        truncated_prob: 0.0,
    };
    for r in recs {
        let t = replay(prog, r, cost, noise, relaxed)?;
        e.mean += r.prob * t;
        e.worst = e.worst.max(t);
        if r.truncated {
            e.truncated_prob += r.prob;
        }
    }
    Ok(e)
}
