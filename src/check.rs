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

use std::collections::BTreeMap;
use std::fmt;

use num_complex::Complex64 as C;

use crate::ir::Program;
use crate::sim::{basis_state, distribution, simulate, Branch, SimError};

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
