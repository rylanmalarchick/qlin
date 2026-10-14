//! Stabilizer state for the branch simulator, for programs past
//! [`crate::sim::MAX_QUBITS`].
//!
//! An Aaronson-Gottesman tableau (destabilizers and stabilizers with
//! signs). Clifford gates act on the tableau, and rotations by a multiple
//! of pi/2 count as Clifford. A non-Clifford one-qubit gate is allowed only
//! on a qubit in a Z basis state, which is therefore unentangled. That
//! qubit then holds a pending 2-vector until its next measurement or reset,
//! which resolves it with the exact probabilities. This covers the error
//! source of the `_noisy` benchmarks (`ry`, then `measure`). Any other
//! non-Clifford use is `SimError::Unsupported`.
//!
//! Global phases are dropped. Each branch state is pure, so the density
//! operator of a branch is exact.

use std::collections::BTreeMap;
use std::f64::consts::FRAC_PI_2;

use num_complex::Complex64 as C;

use crate::ir::{Gate, Qubit};
use crate::sim::{matrix_1q, QState, SimError, M2, PROB_EPS};

/// One Pauli row: X part, Z part, and the sign (true is -1).
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
struct Row {
    x: Vec<bool>,
    z: Vec<bool>,
    r: bool,
}

impl Row {
    fn zero(n: usize) -> Row {
        Row {
            x: vec![false; n],
            z: vec![false; n],
            r: false,
        }
    }
}

/// The exponent of i in the product of single-qubit Paulis
/// (x1, z1) * (x2, z2) (Aaronson and Gottesman, the function g).
fn g(x1: bool, z1: bool, x2: bool, z2: bool) -> i32 {
    let (x2i, z2i) = (x2 as i32, z2 as i32);
    match (x1, z1) {
        (false, false) => 0,
        (true, true) => z2i - x2i,
        (true, false) => z2i * (2 * x2i - 1),
        (false, true) => x2i * (1 - 2 * z2i),
    }
}

/// h <- i * h (the rowsum of Aaronson and Gottesman).
fn rowsum(h: &mut Row, i: &Row) {
    let mut sum = 2 * h.r as i32 + 2 * i.r as i32;
    for j in 0..h.x.len() {
        sum += g(i.x[j], i.z[j], h.x[j], h.z[j]);
        h.x[j] ^= i.x[j];
        h.z[j] ^= i.z[j];
    }
    h.r = sum.rem_euclid(4) == 2;
}

/// Canonical stabilizer generators: (X part, Z part, sign) per row.
pub type Generators = Vec<(Vec<bool>, Vec<bool>, bool)>;

#[derive(Clone, Debug)]
pub struct Tableau {
    n: usize,
    /// Rows 0..n are destabilizers, rows n..2n stabilizers.
    rows: Vec<Row>,
    /// A one-qubit state held outside the tableau (see the module doc).
    /// The tableau holds that qubit in a Z basis state meanwhile.
    pending: Vec<Option<[C; 2]>>,
}

/// `k` when `theta` is k * pi/2 (k mod 4), else None.
fn quarter_turns(theta: f64) -> Option<u8> {
    let k = theta / FRAC_PI_2;
    if (k - k.round()).abs() < 1e-9 {
        Some((k.round() as i64).rem_euclid(4) as u8)
    } else {
        None
    }
}

fn mat_vec(m: &M2, v: &[C; 2]) -> [C; 2] {
    [
        m[0][0] * v[0] + m[0][1] * v[1],
        m[1][0] * v[0] + m[1][1] * v[1],
    ]
}

impl Tableau {
    /// |0...0> on `n` qubits.
    pub fn zero(n: usize) -> Tableau {
        let mut rows = Vec::with_capacity(2 * n);
        for i in 0..2 * n {
            let mut r = Row::zero(n);
            if i < n {
                r.x[i] = true;
            } else {
                r.z[i - n] = true;
            }
            rows.push(r);
        }
        Tableau {
            n,
            rows,
            pending: vec![None; n],
        }
    }

    fn h(&mut self, a: usize) {
        for r in &mut self.rows {
            r.r ^= r.x[a] & r.z[a];
            std::mem::swap(&mut r.x[a], &mut r.z[a]);
        }
    }

    fn s(&mut self, a: usize) {
        for r in &mut self.rows {
            r.r ^= r.x[a] & r.z[a];
            r.z[a] ^= r.x[a];
        }
    }

    fn x_gate(&mut self, a: usize) {
        for r in &mut self.rows {
            r.r ^= r.z[a];
        }
    }

    fn z_gate(&mut self, a: usize) {
        for r in &mut self.rows {
            r.r ^= r.x[a];
        }
    }

    fn cx(&mut self, a: usize, b: usize) {
        for r in &mut self.rows {
            r.r ^= r.x[a] & r.z[b] & !(r.x[b] ^ r.z[a]);
            r.x[b] ^= r.x[a];
            r.z[a] ^= r.z[b];
        }
    }

    fn s_pow(&mut self, a: usize, k: u8) {
        for _ in 0..k {
            self.s(a);
        }
    }

    /// The stabilizer row with an X or Y on `a`, if the outcome is random.
    fn random_pivot(&self, a: usize) -> Option<usize> {
        (self.n..2 * self.n).find(|&p| self.rows[p].x[a])
    }

    /// The Z outcome of qubit `a` when it is deterministic.
    fn det_outcome(&self, a: usize) -> bool {
        let mut acc = Row::zero(self.n);
        for i in 0..self.n {
            if self.rows[i].x[a] {
                rowsum(&mut acc, &self.rows[i + self.n]);
            }
        }
        acc.r
    }

    /// Projects the tableau qubit `a` onto `outcome`. The caller knows the
    /// outcome has nonzero probability.
    fn measure_forced(&mut self, a: usize, outcome: bool) {
        match self.random_pivot(a) {
            Some(p) => {
                let pivot = self.rows[p].clone();
                for i in 0..2 * self.n {
                    if i != p && self.rows[i].x[a] {
                        rowsum(&mut self.rows[i], &pivot);
                    }
                }
                self.rows[p - self.n] = pivot;
                let mut new = Row::zero(self.n);
                new.z[a] = true;
                new.r = outcome;
                self.rows[p] = new;
            }
            None => debug_assert_eq!(self.det_outcome(a), outcome),
        }
    }

    /// Moves a pending qubit back into the tableau when its 2-vector is a
    /// Z basis state (up to phase). Fails otherwise.
    fn settle(&mut self, a: usize, name: &str) -> Result<(), SimError> {
        let Some(v) = self.pending[a] else {
            return Ok(());
        };
        let one = if v[0].norm_sqr() < PROB_EPS {
            true
        } else if v[1].norm_sqr() < PROB_EPS {
            false
        } else {
            return Err(SimError::Unsupported(format!(
                "{name} on a qubit in a non-stabilizer state"
            )));
        };
        if self.det_outcome(a) != one {
            self.x_gate(a);
        }
        self.pending[a] = None;
        Ok(())
    }

    fn clifford_1q(&mut self, gate: &Gate, a: usize, params: &[f64]) -> bool {
        match gate {
            Gate::H => self.h(a),
            Gate::S => self.s(a),
            Gate::Sdg => self.s_pow(a, 3),
            Gate::X => self.x_gate(a),
            Gate::Z => self.z_gate(a),
            Gate::Y => {
                self.x_gate(a);
                self.z_gate(a);
            }
            Gate::Sx => {
                self.h(a);
                self.s(a);
                self.h(a);
            }
            Gate::Rz | Gate::P => match quarter_turns(params[0]) {
                Some(k) => self.s_pow(a, k),
                None => return false,
            },
            Gate::Rx => match quarter_turns(params[0]) {
                Some(k) => {
                    self.h(a);
                    self.s_pow(a, k);
                    self.h(a);
                }
                None => return false,
            },
            // Ry(t) = S Rx(t) Sdg, so in time order: Sdg, Rx(t), S.
            Gate::Ry => match quarter_turns(params[0]) {
                Some(k) => {
                    self.s_pow(a, 3);
                    self.h(a);
                    self.s_pow(a, k);
                    self.h(a);
                    self.s(a);
                }
                None => return false,
            },
            _ => return false,
        }
        true
    }

    /// The canonical generators of the stabilizer group: reduced row
    /// echelon form over the X part, then the Z part, with signs. Two pure
    /// stabilizer states are equal iff their canonical forms are equal.
    /// None when a qubit still holds a non-basis pending state.
    pub fn canonical(&self) -> Option<Generators> {
        let mut t = self.clone();
        for a in 0..t.n {
            if t.settle(a, "canonical").is_err() {
                return None;
            }
        }
        let n = t.n;
        let mut rows: Vec<Row> = t.rows[n..].to_vec();
        let mut top = 0;
        for part in 0..2 {
            for j in 0..n {
                let has = |r: &Row| if part == 0 { r.x[j] } else { r.z[j] };
                let Some(k) = (top..n).find(|&k| has(&rows[k])) else {
                    continue;
                };
                rows.swap(top, k);
                let pivot = rows[top].clone();
                for (i, row) in rows.iter_mut().enumerate() {
                    if i != top && has(row) {
                        rowsum(row, &pivot);
                    }
                }
                top += 1;
            }
        }
        Some(rows.into_iter().map(|r| (r.x, r.z, r.r)).collect())
    }
}

impl QState for Tableau {
    fn apply(&mut self, gate: &Gate, qubits: &[Qubit], params: &[f64]) -> Result<(), SimError> {
        let q: Vec<usize> = qubits.iter().map(|q| q.0 as usize).collect();
        if q.len() == 1 {
            let a = q[0];
            if let Some(v) = self.pending[a] {
                let m = matrix_1q(gate, params)
                    .ok_or_else(|| SimError::Unsupported(gate.name().to_string()))?;
                self.pending[a] = Some(mat_vec(&m, &v));
                return Ok(());
            }
            if self.clifford_1q(gate, a, params) {
                return Ok(());
            }
            let m = matrix_1q(gate, params)
                .ok_or_else(|| SimError::Unsupported(gate.name().to_string()))?;
            if self.random_pivot(a).is_some() {
                return Err(SimError::Unsupported(format!(
                    "{} on an entangled qubit",
                    gate.name()
                )));
            }
            let mut basis = [C::new(0.0, 0.0); 2];
            basis[self.det_outcome(a) as usize] = C::new(1.0, 0.0);
            self.pending[a] = Some(mat_vec(&m, &basis));
            return Ok(());
        }
        for &a in &q {
            self.settle(a, gate.name())?;
        }
        match (gate, q.as_slice()) {
            (Gate::Cx, &[a, b]) => self.cx(a, b),
            (Gate::Cz, &[a, b]) => {
                self.h(b);
                self.cx(a, b);
                self.h(b);
            }
            (Gate::Cy, &[a, b]) => {
                self.s_pow(b, 3);
                self.cx(a, b);
                self.s(b);
            }
            (Gate::Swap, &[a, b]) => {
                self.cx(a, b);
                self.cx(b, a);
                self.cx(a, b);
            }
            (g, _) => return Err(SimError::Unsupported(g.name().to_string())),
        }
        Ok(())
    }

    fn prob_one(&self, q: Qubit) -> f64 {
        let a = q.0 as usize;
        if let Some(v) = self.pending[a] {
            v[1].norm_sqr()
        } else if self.random_pivot(a).is_some() {
            0.5
        } else if self.det_outcome(a) {
            1.0
        } else {
            0.0
        }
    }

    fn collapse(&mut self, q: Qubit, outcome: bool, _p: f64) {
        let a = q.0 as usize;
        if self.pending[a].take().is_some() {
            if self.det_outcome(a) != outcome {
                self.x_gate(a);
            }
        } else {
            self.measure_forced(a, outcome);
        }
    }

    fn flip(&mut self, q: Qubit) {
        let a = q.0 as usize;
        match self.pending[a] {
            Some(v) => self.pending[a] = Some([v[1], v[0]]),
            None => self.x_gate(a),
        }
    }
}

/// One of the six one-qubit stabilizer states, as gates on |0>:
/// |0>, |1>, |+>, |->, |+i>, |-i> for `k` mod 6.
pub fn prep_gates(k: u64) -> Vec<Gate> {
    match k % 6 {
        0 => vec![],
        1 => vec![Gate::X],
        2 => vec![Gate::H],
        3 => vec![Gate::X, Gate::H],
        4 => vec![Gate::H, Gate::S],
        _ => vec![Gate::X, Gate::H, Gate::S],
    }
}

/// The product state on `n` qubits with qubit `q` in state `ks[q]` of
/// [`prep_gates`]. Qubits past `ks` start in |0>.
pub fn product(n: usize, ks: &[u64]) -> Tableau {
    let mut t = Tableau::zero(n);
    for (q, &k) in ks.iter().enumerate() {
        for g in prep_gates(k) {
            t.apply(&g, &[Qubit(q as u32)], &[])
                .expect("prep gates are Clifford");
        }
    }
    t
}

/// Groups branch states by final bits: for each bit vector, the total
/// probability of each canonical stabilizer state. Two equal maps give
/// equal cq states. None when a branch ends in a non-stabilizer state.
pub fn state_map(
    branches: &[crate::sim::Branch<Tableau>],
) -> Option<BTreeMap<Vec<bool>, BTreeMap<Generators, f64>>> {
    let mut out: BTreeMap<_, BTreeMap<_, f64>> = BTreeMap::new();
    for b in branches {
        let key = b.state.canonical()?;
        *out.entry(b.bits.clone())
            .or_default()
            .entry(key)
            .or_insert(0.0) += b.prob;
    }
    Some(out)
}
