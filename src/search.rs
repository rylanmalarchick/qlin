//! Search over defer choices.
//!
//! Each candidate If (see [`crate::transform::defer`]) is either kept
//! classical or deferred. The objective is expected replay latency. Ties
//! break on fewer added multi-qubit gates, then fewer added qubits.
//!
//! The lower bound for a partial assignment keeps the undecided Ifs
//! classical but relaxed (no feedforward wait). On each outcome record,
//! relaxed <= classical because it drops edges, and relaxed <= deferred
//! because the base gate is no slower than its controlled form, runs only
//! when its condition holds, and leaves the measurement early. This
//! argument is hand-derived. [`Problem::exhaustive`] checks it on every
//! prefix.

use serde::Serialize;

use crate::check::{equivalent, inputs, CheckError};
use crate::cost::CostModel;
use crate::ir::Program;
use crate::latency::{expected, records, Noise, Record, ReplayError};
use crate::sim::SimError;
use crate::transform::defer::{apply, candidates, Candidate, Choice, Variant};

/// Two latencies closer than this are equal.
pub const EPS: f64 = 1e-9;
/// Exhaustive search runs only up to this many candidates.
pub const MAX_EXHAUSTIVE: usize = 12;
/// Branch and bound runs only up to this many candidates.
pub const MAX_BNB: usize = 40;

#[derive(Debug)]
pub enum SearchError {
    Sim(SimError),
    Replay(ReplayError),
    Check(CheckError),
    TooManyCandidates(usize),
}

impl std::fmt::Display for SearchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SearchError::Sim(e) => write!(f, "{e}"),
            SearchError::Replay(e) => write!(f, "{e}"),
            SearchError::Check(e) => write!(f, "variant failed the equivalence check: {e}"),
            SearchError::TooManyCandidates(k) => write!(f, "{k} candidates is too many"),
        }
    }
}

impl std::error::Error for SearchError {}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Point {
    /// One flag per candidate: true = deferred.
    pub defer: Vec<bool>,
    pub mean: f64,
    pub worst: f64,
    pub added_2q: usize,
    pub added_qubits: usize,
}

impl Point {
    /// True when `self` is better than `other` in the search order.
    pub fn better(&self, other: &Point) -> bool {
        if (self.mean - other.mean).abs() > EPS {
            return self.mean < other.mean;
        }
        (self.added_2q, self.added_qubits) < (other.added_2q, other.added_qubits)
    }

    fn dominates(&self, other: &Point) -> bool {
        let le = self.mean <= other.mean + EPS
            && self.added_2q <= other.added_2q
            && self.added_qubits <= other.added_qubits;
        let lt = self.mean < other.mean - EPS
            || self.added_2q < other.added_2q
            || self.added_qubits < other.added_qubits;
        le && lt
    }
}

pub struct Problem<'a> {
    pub prog: &'a Program,
    pub cands: Vec<Candidate>,
    pub recs: Vec<Record>,
    pub cost: CostModel,
    pub noise: Noise,
    /// When set, every scored leaf is checked against `prog` by simulation.
    pub check_leaves: bool,
}

#[derive(Clone, Debug, Serialize)]
pub struct Exhaustive {
    pub best: Point,
    pub pareto: Vec<Point>,
    pub leaves: usize,
    /// Prefixes whose bound exceeds the best completion. Must be 0.
    pub bound_violations: usize,
    pub prefixes: usize,
}

#[derive(Clone, Debug, Serialize)]
pub struct BnB {
    pub best: Point,
    /// Bound evaluations, including leaves.
    pub nodes: usize,
    pub leaves: usize,
}

impl<'a> Problem<'a> {
    pub fn new(
        prog: &'a Program,
        cost: CostModel,
        noise: Noise,
        limit: usize,
    ) -> Result<Self, SearchError> {
        let recs = records(prog, limit).map_err(SearchError::Sim)?;
        let cands = candidates(prog, &noise);
        Ok(Problem {
            prog,
            cands,
            recs,
            cost,
            noise,
            check_leaves: false,
        })
    }

    fn variant(&self, choices: &[Choice]) -> Variant {
        apply(self.prog, &self.cands, choices)
    }

    fn mean(&self, v: &Variant) -> Result<(f64, f64), SearchError> {
        let e = expected(&v.prog, &self.recs, &self.cost, &self.noise, &v.relaxed)
            .map_err(SearchError::Replay)?;
        Ok((e.mean, e.worst))
    }

    /// Scores a full assignment.
    pub fn leaf(&self, defer: &[bool]) -> Result<Point, SearchError> {
        let choices: Vec<Choice> = defer
            .iter()
            .map(|&d| if d { Choice::Defer } else { Choice::Classical })
            .collect();
        let v = self.variant(&choices);
        if self.check_leaves {
            equivalent(
                self.prog,
                &v.prog,
                &inputs(self.prog.n_qubits, 8, 13),
                1 << 16,
            )
            .map_err(SearchError::Check)?;
        }
        let (mean, worst) = self.mean(&v)?;
        Ok(Point {
            defer: defer.to_vec(),
            mean,
            worst,
            added_2q: v.added_2q,
            added_qubits: v.added_qubits,
        })
    }

    /// Lower bound on the mean latency of every completion of `prefix`.
    pub fn bound(&self, prefix: &[bool]) -> Result<f64, SearchError> {
        let choices: Vec<Choice> = (0..self.cands.len())
            .map(|i| match prefix.get(i) {
                Some(true) => Choice::Defer,
                Some(false) => Choice::Classical,
                None => Choice::Relaxed,
            })
            .collect();
        Ok(self.mean(&self.variant(&choices))?.0)
    }

    /// Mean latency with every candidate relaxed: the floor if feedforward
    /// on the candidates were free.
    pub fn floor(&self) -> Result<f64, SearchError> {
        self.bound(&[])
    }

    pub fn exhaustive(&self) -> Result<Exhaustive, SearchError> {
        let k = self.cands.len();
        if k > MAX_EXHAUSTIVE {
            return Err(SearchError::TooManyCandidates(k));
        }
        // Leaf `code`: candidate i is deferred when bit (k - 1 - i) is set,
        // so a prefix of length j is the top j bits.
        let decode = |code: usize, len: usize| -> Vec<bool> {
            (0..len).map(|i| (code >> (k - 1 - i)) & 1 == 1).collect()
        };
        let mut points = Vec::with_capacity(1 << k);
        for code in 0..1usize << k {
            points.push(self.leaf(&decode(code, k))?);
        }
        let mut best = points[0].clone();
        for p in &points[1..] {
            if p.better(&best) {
                best = p.clone();
            }
        }
        let pareto: Vec<Point> = points
            .iter()
            .filter(|p| !points.iter().any(|q| q.dominates(p)))
            .cloned()
            .collect();
        let (mut violations, mut prefixes) = (0, 0);
        for j in 0..=k {
            for top in 0..1usize << j {
                let lo = top << (k - j);
                let hi = lo + (1 << (k - j));
                let min = points[lo..hi]
                    .iter()
                    .map(|p| p.mean)
                    .fold(f64::INFINITY, f64::min);
                let prefix = decode(lo, j);
                if self.bound(&prefix)? > min + EPS {
                    violations += 1;
                }
                prefixes += 1;
            }
        }
        Ok(Exhaustive {
            best,
            pareto,
            leaves: points.len(),
            bound_violations: violations,
            prefixes,
        })
    }

    pub fn branch_and_bound(&self) -> Result<BnB, SearchError> {
        let k = self.cands.len();
        if k > MAX_BNB {
            return Err(SearchError::TooManyCandidates(k));
        }
        let mut best: Option<Point> = None;
        let (mut nodes, mut leaves) = (0, 0);
        // Depth-first, deferred branch first. Each stack entry is a prefix.
        // The tree has 2^(k+1) - 1 nodes, which bounds the loop.
        let mut stack: Vec<Vec<bool>> = vec![Vec::new()];
        for _ in 0..(1usize << (k + 1)) - 1 {
            let Some(prefix) = stack.pop() else { break };
            if prefix.len() == k {
                let p = self.leaf(&prefix)?;
                nodes += 1;
                leaves += 1;
                if best.as_ref().is_none_or(|b| p.better(b)) {
                    best = Some(p);
                }
                continue;
            }
            let lb = self.bound(&prefix)?;
            nodes += 1;
            if best.as_ref().is_some_and(|b| lb > b.mean + EPS) {
                continue;
            }
            for choice in [false, true] {
                let mut next = prefix.clone();
                next.push(choice);
                stack.push(next);
            }
        }
        Ok(BnB {
            best: best.expect("the search visits at least one leaf"),
            nodes,
            leaves,
        })
    }
}
