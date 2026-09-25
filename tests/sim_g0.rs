//! Gate G0: the state-vector simulator oracle.

use num_complex::Complex64 as C;
use qlin::ir::{Bit, Gate, Op, Program, Qubit};
use qlin::sim::{basis_state, distribution, simulate, Branch};
use qlin::text::parse;

const LIMIT: usize = 1 << 12;

fn load(path: &str) -> Program {
    parse(&std::fs::read_to_string(path).unwrap()).unwrap()
}

/// psi on q0, |0> on the other qubits.
fn with_input(n: u32, alpha: C, beta: C) -> Vec<C> {
    let mut s = basis_state(n, 0);
    s[0] = alpha;
    s[1] = beta;
    s
}

/// The amplitudes of q2 in a branch where q0 and q1 are measured.
fn q2_state(b: &Branch) -> (C, C) {
    let bit = |i: u32| b.outcomes.iter().find(|(x, _)| *x == Bit(i)).unwrap().1 as usize;
    let i0 = bit(0) | (bit(1) << 1);
    (b.state[i0], b.state[i0 | 4])
}

fn overlap(a: (C, C), b: (C, C)) -> f64 {
    (a.0.conj() * b.0 + a.1.conj() * b.1).norm()
}

fn inputs() -> Vec<(C, C)> {
    let r = std::f64::consts::FRAC_1_SQRT_2;
    let (s, k) = (1.1f64 / 2.0).sin_cos();
    vec![
        (C::new(1.0, 0.0), C::new(0.0, 0.0)),
        (C::new(r, 0.0), C::new(r, 0.0)),
        (C::new(k, 0.0), C::new(s, 0.0)),
        (C::new(k, 0.0), C::new(0.0, s)),
    ]
}

#[test]
fn teleportation_moves_the_input_to_q2() {
    let prog = load("benchmarks/hand/teleportation.qlin");
    for psi in inputs() {
        let branches = simulate(&prog, &with_input(3, psi.0, psi.1), LIMIT).unwrap();
        assert_eq!(branches.len(), 4);
        let total: f64 = branches.iter().map(|b| b.prob).sum();
        assert!((total - 1.0).abs() < 1e-12);
        for b in &branches {
            assert!((b.prob - 0.25).abs() < 1e-12);
            // Deterministic result, so the tolerance is tight.
            assert!(
                (overlap(psi, q2_state(b)) - 1.0).abs() < 1e-12,
                "{:?}",
                b.outcomes
            );
        }
    }
}

#[test]
fn oracle_rejects_teleportation_without_the_z_correction() {
    let mut prog = load("benchmarks/hand/teleportation.qlin");
    prog.body.pop();
    let r = std::f64::consts::FRAC_1_SQRT_2;
    let psi = (C::new(r, 0.0), C::new(r, 0.0));
    let branches = simulate(&prog, &with_input(3, psi.0, psi.1), LIMIT).unwrap();
    let worst = branches
        .iter()
        .map(|b| overlap(psi, q2_state(b)))
        .fold(1.0f64, f64::min);
    assert!(worst < 0.5, "worst overlap {worst}");
}

#[test]
fn repetition_round_corrects_every_single_flip() {
    let clean = load("benchmarks/hand/repetition3.qlin");
    for flipped in [None, Some(0u32), Some(1), Some(2)] {
        let mut prog = clean.clone();
        if let Some(q) = flipped {
            // After the encoder (ops 0..=2), before the syndrome CNOTs.
            prog.body.insert(
                3,
                Op::Gate {
                    gate: Gate::X,
                    qubits: vec![Qubit(q)],
                    params: vec![],
                },
            );
        }
        let branches = simulate(&prog, &basis_state(5, 0), LIMIT).unwrap();
        assert_eq!(branches.len(), 1, "syndrome is deterministic");
        let b = &branches[0];
        // Data qubits q0..q2 are |111>. The ancillas hold the syndrome.
        let idx = (0..32).find(|i| b.state[*i].norm_sqr() > 0.5).unwrap();
        assert_eq!(idx & 0b111, 0b111, "flip {flipped:?}");
    }
}

#[test]
fn reset_and_distribution() {
    let p = parse("qubits 1\nbits 2\nh q0\nreset q0\nmeasure q0 -> c0\nh q0\nmeasure q0 -> c1\n")
        .unwrap();
    let branches = simulate(&p, &basis_state(1, 0), LIMIT).unwrap();
    let d = distribution(&branches);
    assert_eq!(d.len(), 2);
    assert!((d[&vec![false, false]] - 0.5).abs() < 1e-12);
    assert!((d[&vec![false, true]] - 0.5).abs() < 1e-12);
}

fn unitary_1q(src: &str) -> [[C; 2]; 2] {
    let p = parse(&format!("qubits 1\nbits 0\n{src}\n")).unwrap();
    let cols: Vec<Vec<C>> = (0..2)
        .map(|col| {
            simulate(&p, &basis_state(1, col), LIMIT).unwrap()[0]
                .state
                .clone()
        })
        .collect();
    [[cols[0][0], cols[1][0]], [cols[0][1], cols[1][1]]]
}

/// True when `a` equals `b` up to a global phase.
fn same_up_to_phase(a: [[C; 2]; 2], b: [[C; 2]; 2]) -> bool {
    let (i, j) = (0..4)
        .map(|k| (k / 2, k % 2))
        .max_by(|x, y| b[x.0][x.1].norm().total_cmp(&b[y.0][y.1].norm()))
        .unwrap();
    let phase = a[i][j] / b[i][j];
    (0..4).all(|k| (a[k / 2][k % 2] - phase * b[k / 2][k % 2]).norm() < 1e-12)
}

#[test]
fn gate_identities() {
    let x = unitary_1q("x q0");
    let z = unitary_1q("z q0");
    assert!(same_up_to_phase(unitary_1q("h q0 z q0 h q0"), x));
    assert!(same_up_to_phase(unitary_1q("s q0 s q0"), z));
    assert!(same_up_to_phase(
        unitary_1q("t q0 t q0"),
        unitary_1q("s q0")
    ));
    assert!(same_up_to_phase(
        unitary_1q("sdg q0"),
        unitary_1q("s q0 z q0")
    ));
    assert!(same_up_to_phase(unitary_1q("sx q0 sx q0"), x));
    assert!(same_up_to_phase(unitary_1q("u(pi, 0, pi) q0"), x));
    assert!(same_up_to_phase(
        unitary_1q("rz(0.7) q0"),
        unitary_1q("p(0.7) q0")
    ));
    assert!(same_up_to_phase(unitary_1q("rx(pi) q0"), x));
    assert!(same_up_to_phase(
        unitary_1q("ry(pi) q0"),
        unitary_1q("y q0")
    ));
    assert!(same_up_to_phase(
        unitary_1q("u(0.3, 0.4, 0.5) q0"),
        unitary_1q("rz(0.5) q0 ry(0.3) q0 rz(0.4) q0")
    ));
    assert!(!same_up_to_phase(unitary_1q("h q0"), x));
}

#[test]
fn two_qubit_identities() {
    // CX = (I x H) CZ (I x H) on target q1, and CCX flips only |11x>.
    let a = parse("qubits 2\nbits 0\ncx q0 q1\n").unwrap();
    let b = parse("qubits 2\nbits 0\nh q1\ncz q0 q1\nh q1\n").unwrap();
    let c = parse("qubits 2\nbits 0\nswap q0 q1\ncx q1 q0\nswap q0 q1\n").unwrap();
    for col in 0..4 {
        let sa = &simulate(&a, &basis_state(2, col), LIMIT).unwrap()[0].state;
        let sb = &simulate(&b, &basis_state(2, col), LIMIT).unwrap()[0].state;
        let sc = &simulate(&c, &basis_state(2, col), LIMIT).unwrap()[0].state;
        for k in 0..4 {
            assert!((sa[k] - sb[k]).norm() < 1e-12);
            assert!((sa[k] - sc[k]).norm() < 1e-12);
        }
    }
    let t = parse("qubits 3\nbits 0\nccx q0 q1 q2\n").unwrap();
    for col in 0..8 {
        let s = &simulate(&t, &basis_state(3, col), LIMIT).unwrap()[0].state;
        let want = if col & 3 == 3 { col ^ 4 } else { col };
        assert!((s[want].norm() - 1.0).abs() < 1e-12, "col {col}");
    }
}
