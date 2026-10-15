//! Semantic equivalence check by simulation.
//!
//! Two programs are compared from |0...0> and from seeded random product
//! states. For each input they must give the same distribution of the
//! classical bits and, for each classical outcome, the same value of
//! <v|rho|v> for a few seeded random vectors v, where rho is the
//! unnormalized output state on the first program's qubits. The second
//! program may have extra qubits (ancillas), appended at the end and
//! starting in |0>. They are traced out. The check is sound but not
//! complete: it tests finite inputs and finite witnesses.
//!
//! Past [`MAX_QUBITS`] qubits, [`check`] uses the stabilizer backend
//! ([`equivalent_stab`]) on programs it supports: inputs are |0...0> and
//! seeded products of one-qubit stabilizer states, and the states are
//! compared exactly, as mixtures of canonical stabilizer states.

use std::collections::BTreeMap;
use std::fmt;

use num_complex::Complex64 as C;

use crate::ir::{Op, Program, Qubit};
use crate::sim::{
    basis_state, distribution, simulate, simulate_state, Branch, SimError, MAX_QUBITS,
};
use crate::stab::{product, state_map};

/// Random witness vectors per check.
const WITNESSES: usize = 4;

/// Distributions are sums of branch probabilities, exact up to rounding.
pub const TOL: f64 = 1e-9;

#[derive(Clone, Debug, PartialEq)]
pub enum CheckError {
    Sim(SimError),
    Shape(String),
    Mismatch { input: usize, diff: f64 },
}

impl fmt::Display for CheckError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CheckError::Sim(e) => write!(f, "simulation failed: {e}"),
            CheckError::Shape(s) => write!(f, "programs differ in shape: {s}"),
            CheckError::Mismatch { input, diff } => {
                write!(f, "distributions differ on input {input} by {diff:.3e}")
            }
        }
    }
}

impl std::error::Error for CheckError {}

/// xorshift64*, for seeded inputs without a dependency.
struct Rng(u64);

impl Rng {
    fn unit(&mut self) -> f64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        (self.0.wrapping_mul(0x2545_F491_4F6C_DD1D) >> 11) as f64 / (1u64 << 53) as f64
    }
}

/// A random product state on `n` qubits.
fn product_state(n: u32, rng: &mut Rng) -> Vec<C> {
    let mut s = vec![C::new(1.0, 0.0)];
    for _ in 0..n {
        let theta = rng.unit() * std::f64::consts::PI;
        let phi = rng.unit() * std::f64::consts::TAU;
        let (a0, a1) = (
            C::new((theta / 2.0).cos(), 0.0),
            C::from_polar((theta / 2.0).sin(), phi),
        );
        // New qubit is the highest bit of the index.
        let mut next = s.iter().map(|x| x * a0).collect::<Vec<_>>();
        next.extend(s.iter().map(|x| x * a1));
        s = next;
    }
    s
}

/// Inputs for a check: |0...0> first, then `n_random` product states.
pub fn inputs(n: u32, n_random: usize, seed: u64) -> Vec<Vec<C>> {
    let mut rng = Rng(seed.max(1));
    let mut out = vec![basis_state(n, 0)];
    for _ in 0..n_random {
        out.push(product_state(n, &mut rng));
    }
    out
}

/// Per classical outcome: sum over branches of p * <v|rho_branch|v>, with
/// qubits at or above `n` traced out.
fn witness(branches: &[Branch], n: u32, vs: &[Vec<C>]) -> BTreeMap<Vec<bool>, Vec<f64>> {
    let low = 1usize << n;
    let mut out: BTreeMap<Vec<bool>, Vec<f64>> = BTreeMap::new();
    for br in branches {
        let w = out
            .entry(br.bits.clone())
            .or_insert_with(|| vec![0.0; vs.len()]);
        for slice in br.state.chunks(low) {
            for (k, v) in vs.iter().enumerate() {
                let amp: C = v.iter().zip(slice).map(|(x, y)| x.conj() * y).sum();
                w[k] += br.prob * amp.norm_sqr();
            }
        }
    }
    out
}

/// Seeded random unit vectors of length 2^n.
fn witness_vectors(n: u32, seed: u64) -> Vec<Vec<C>> {
    let mut rng = Rng(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15).max(1));
    (0..WITNESSES)
        .map(|_| {
            let v: Vec<C> = (0..1usize << n)
                .map(|_| C::new(rng.unit() - 0.5, rng.unit() - 0.5))
                .collect();
            let norm = v.iter().map(|x| x.norm_sqr()).sum::<f64>().sqrt();
            v.into_iter().map(|x| x / norm).collect()
        })
        .collect()
}

fn max_diff(a: &BTreeMap<Vec<bool>, Vec<f64>>, b: &BTreeMap<Vec<bool>, Vec<f64>>) -> f64 {
    let zeros = vec![0.0; WITNESSES];
    a.keys()
        .chain(b.keys())
        .map(|k| {
            let (x, y) = (a.get(k).unwrap_or(&zeros), b.get(k).unwrap_or(&zeros));
            x.iter()
                .zip(y)
                .map(|(p, q)| (p - q).abs())
                .fold(0.0, f64::max)
        })
        .fold(0.0, f64::max)
}

/// Compares `a` and `b` on `inputs` (states on `a`'s qubits).
pub fn equivalent(
    a: &Program,
    b: &Program,
    inputs: &[Vec<C>],
    limit: usize,
) -> Result<(), CheckError> {
    if a.n_bits != b.n_bits || b.n_qubits < a.n_qubits {
        return Err(CheckError::Shape(format!(
            "{}q/{}c vs {}q/{}c",
            a.n_qubits, a.n_bits, b.n_qubits, b.n_bits
        )));
    }
    for (k, init) in inputs.iter().enumerate() {
        let mut init_b = vec![C::new(0.0, 0.0); 1usize << b.n_qubits.min(crate::sim::MAX_QUBITS)];
        if b.n_qubits > crate::sim::MAX_QUBITS {
            return Err(CheckError::Sim(SimError::TooManyQubits(b.n_qubits)));
        }
        init_b[..init.len()].copy_from_slice(init);
        let ra = simulate(a, init, limit).map_err(CheckError::Sim)?;
        let rb = simulate(b, &init_b, limit).map_err(CheckError::Sim)?;
        let trunc = |r: &[crate::sim::Branch]| -> f64 {
            r.iter().filter(|x| x.truncated).map(|x| x.prob).sum()
        };
        let (da, db) = (distribution(&ra), distribution(&rb));
        let diff = da
            .keys()
            .chain(db.keys())
            .map(|key| (da.get(key).unwrap_or(&0.0) - db.get(key).unwrap_or(&0.0)).abs())
            .fold(0.0, f64::max);
        let vs = witness_vectors(a.n_qubits, k as u64 + 1);
        let wdiff = max_diff(
            &witness(&ra, a.n_qubits, &vs),
            &witness(&rb, a.n_qubits, &vs),
        );
        let diff = diff.max(wdiff);
        if diff > TOL + trunc(&ra) + trunc(&rb) {
            return Err(CheckError::Mismatch { input: k, diff });
        }
    }
    Ok(())
}

/// Which simulator a [`check`] used.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Checked {
    Dense,
    /// The number of inputs compared (|0...0> and the supported products).
    Stabilizer(usize),
}

/// Compares `a` and `b` with the dense simulator when `b` has at most
/// [`MAX_QUBITS`] qubits, else with the stabilizer backend. A program that
/// neither backend runs gives `CheckError::Sim(SimError::TooManyQubits)`.
pub fn check(
    a: &Program,
    b: &Program,
    n_random: usize,
    seed: u64,
    limit: usize,
) -> Result<Checked, CheckError> {
    if b.n_qubits <= MAX_QUBITS {
        return equivalent(a, b, &inputs(a.n_qubits, n_random, seed), limit)
            .map(|_| Checked::Dense);
    }
    match equivalent_stab(a, b, n_random, seed, limit) {
        Err(CheckError::Sim(SimError::Unsupported(_))) => {
            Err(CheckError::Sim(SimError::TooManyQubits(b.n_qubits)))
        }
        r => r.map(Checked::Stabilizer),
    }
}

/// Qubits per random input of the stabilizer check that start in an X or
/// Y basis state. The others start in |0> or |1>.
const SUPERPOSED: usize = 3;

/// The stabilizer check. Returns the number of inputs compared. An input
/// on which `a` uses a non-Clifford gate on a qubit in superposition, or on
/// which either program has more than `limit` branches, is skipped, except
/// |0...0>, which must run.
pub fn equivalent_stab(
    a: &Program,
    b: &Program,
    n_random: usize,
    seed: u64,
    limit: usize,
) -> Result<usize, CheckError> {
    if a.n_bits != b.n_bits || b.n_qubits < a.n_qubits {
        return Err(CheckError::Shape(format!(
            "{}q/{}c vs {}q/{}c",
            a.n_qubits, a.n_bits, b.n_qubits, b.n_bits
        )));
    }
    // Tracing out an ancilla equals measuring it and dropping the outcome.
    // The reset does that and returns it to |0>, its state in `a`.
    let mut b2 = b.clone();
    for q in a.n_qubits..b.n_qubits {
        b2.body.push(Op::Reset { q: Qubit(q) });
    }
    let n = b.n_qubits as usize;
    let mut rng = Rng(seed.max(1));
    let mut compared = 0;
    for k in 0..=n_random {
        // Each qubit in |0> or |1>, and up to SUPERPOSED of them in an X or
        // Y basis state. Superposed inputs make measurements random, and
        // the branch count grows as 2^(random measurements).
        let ks: Vec<u64> = if k == 0 {
            Vec::new()
        } else {
            let mut ks: Vec<u64> = (0..a.n_qubits)
                .map(|_| (rng.unit() * 2.0) as u64 % 2)
                .collect();
            for _ in 0..SUPERPOSED.min(ks.len()) {
                let q = (rng.unit() * ks.len() as f64) as usize % ks.len();
                ks[q] = 2 + (rng.unit() * 4.0) as u64 % 4;
            }
            ks
        };
        let init = product(n, &ks);
        let ra = match simulate_state(a, init.clone(), limit) {
            Ok(r) => r,
            Err(SimError::Unsupported(_) | SimError::TooManyBranches { .. }) if k > 0 => continue,
            Err(e) => return Err(CheckError::Sim(e)),
        };
        let rb = match simulate_state(&b2, init, limit) {
            Ok(r) => r,
            Err(SimError::TooManyBranches { .. }) if k > 0 => continue,
            Err(e) => return Err(CheckError::Sim(e)),
        };
        let trunc: f64 = ra
            .iter()
            .chain(&rb)
            .filter(|x| x.truncated)
            .map(|x| x.prob)
            .sum();
        let (da, db) = (distribution(&ra), distribution(&rb));
        let mut diff = da
            .keys()
            .chain(db.keys())
            .map(|key| (da.get(key).unwrap_or(&0.0) - db.get(key).unwrap_or(&0.0)).abs())
            .fold(0.0, f64::max);
        let non_stab =
            || CheckError::Sim(SimError::Unsupported("non-stabilizer final state".into()));
        let (sa, sb) = (
            state_map(&ra).ok_or_else(non_stab)?,
            state_map(&rb).ok_or_else(non_stab)?,
        );
        let empty = BTreeMap::new();
        for bits in sa.keys().chain(sb.keys()) {
            let (ma, mb) = (
                sa.get(bits).unwrap_or(&empty),
                sb.get(bits).unwrap_or(&empty),
            );
            for key in ma.keys().chain(mb.keys()) {
                let d = (ma.get(key).unwrap_or(&0.0) - mb.get(key).unwrap_or(&0.0)).abs();
                diff = diff.max(d);
            }
        }
        if diff > TOL + trunc {
            return Err(CheckError::Mismatch { input: k, diff });
        }
        compared += 1;
    }
    Ok(compared)
}
