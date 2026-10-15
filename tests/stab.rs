//! The stabilizer backend against the dense simulator. On every benchmark
//! with at most 12 qubits that the backend supports, both give the same
//! branches (outcomes, bits, probabilities) and the same branch states.

use std::path::{Path, PathBuf};

use num_complex::Complex64 as C;
use qlin::ir::{Gate, Program, Qubit};
use qlin::sim::{basis_state, simulate_state, QState, SimError, MAX_QUBITS};
use qlin::stab::Tableau;
use qlin::text::parse;

const LIMIT: usize = 1 << 16;

fn load(path: &Path) -> Program {
    parse(&std::fs::read_to_string(path).unwrap()).unwrap()
}

fn small_benchmarks() -> Vec<(PathBuf, Program)> {
    let mut out = Vec::new();
    for dir in ["benchmarks/hand", "benchmarks/jeff", "benchmarks/dynamarq"] {
        for e in std::fs::read_dir(dir).unwrap() {
            let p = e.unwrap().path();
            if p.extension().is_some_and(|x| x == "qlin") {
                let prog = load(&p);
                if prog.n_qubits <= MAX_QUBITS {
                    out.push((p, prog));
                }
            }
        }
    }
    out.sort_by(|a, b| a.0.cmp(&b.0));
    out
}

/// The state vector of a pure stabilizer state, from its generators:
/// prod_i (1 + P_i)/2 applied to a fixed vector, normalized.
fn stab_vector(gens: &[(Vec<bool>, Vec<bool>, bool)], n: usize) -> Vec<C> {
    let dim = 1usize << n;
    let mut v: Vec<C> = (0..dim)
        .map(|i| C::new(1.0 + (i as f64 * 0.37).sin(), (i as f64 * 0.91).cos()))
        .collect();
    for (x, z, r) in gens {
        let xm: usize = (0..n).filter(|&j| x[j]).map(|j| 1 << j).sum();
        let zm: usize = (0..n).filter(|&j| z[j]).map(|j| 1 << j).sum();
        let y = (0..n).filter(|&j| x[j] && z[j]).count();
        let phase = C::new(0.0, 1.0).powu(y as u32) * if *r { -1.0 } else { 1.0 };
        let mut pv = vec![C::new(0.0, 0.0); dim];
        for (i, a) in v.iter().enumerate() {
            let sign = if (i & zm).count_ones() % 2 == 1 {
                -1.0
            } else {
                1.0
            };
            pv[i ^ xm] += phase * sign * a;
        }
        for i in 0..dim {
            v[i] = (v[i] + pv[i]) * 0.5;
        }
    }
    let norm = v.iter().map(|a| a.norm_sqr()).sum::<f64>().sqrt();
    v.iter().map(|a| a / norm).collect()
}

/// One of the six one-qubit stabilizer states, as gates on |0>.
fn prep(k: u64) -> Vec<Gate> {
    match k % 6 {
        0 => vec![],
        1 => vec![Gate::X],
        2 => vec![Gate::H],
        3 => vec![Gate::X, Gate::H],
        4 => vec![Gate::H, Gate::S],
        _ => vec![Gate::X, Gate::H, Gate::S],
    }
}

/// Compares the two backends on `prog` from the product state `ks`.
/// Returns false when the stabilizer backend does not support `prog`.
fn compare(path: &Path, prog: &Program, ks: &[u64]) -> bool {
    let n = prog.n_qubits as usize;
    let mut tab = Tableau::zero(n);
    let mut dense = basis_state(prog.n_qubits, 0);
    for (q, &k) in ks.iter().enumerate() {
        for g in prep(k) {
            tab.apply(&g, &[Qubit(q as u32)], &[]).unwrap();
            dense.apply(&g, &[Qubit(q as u32)], &[]).unwrap();
        }
    }
    let sb = match simulate_state(prog, tab, LIMIT) {
        Ok(b) => b,
        Err(SimError::Unsupported(_)) => return false,
        Err(e) => panic!("{}: {e}", path.display()),
    };
    let db = simulate_state(prog, dense, LIMIT).unwrap();
    // Group by (outcomes, bits): a reset splits a branch without recording
    // its outcome, so a group can hold several branches. Compare each
    // group's total probability and its density operator on witness
    // vectors. The dense run may hold extra branches from rounding (an
    // outcome of probability ~1e-13 that is exactly 0); each must be tiny.
    type Key = (Vec<(qlin::ir::Bit, bool)>, Vec<bool>);
    type Mix = Vec<(f64, Vec<C>)>;
    let mut groups: std::collections::BTreeMap<Key, (Mix, Mix)> = Default::default();
    for s in &sb {
        let Some(gens) = s.state.canonical() else {
            panic!("{}: branch ends in a non-stabilizer state", path.display());
        };
        let g = groups
            .entry((s.outcomes.clone(), s.bits.clone()))
            .or_default();
        g.0.push((s.prob, stab_vector(&gens, n)));
    }
    for d in &db {
        let g = groups
            .entry((d.outcomes.clone(), d.bits.clone()))
            .or_default();
        g.1.push((d.prob, d.state.clone()));
    }
    let witnesses: Vec<Vec<C>> = (0..3)
        .map(|w| {
            (0..1usize << n)
                .map(|i| {
                    C::new(
                        ((i * (w + 2)) as f64 * 0.73).cos(),
                        ((i + w) as f64 * 1.3).sin(),
                    )
                })
                .collect()
        })
        .collect();
    for (key, (st, de)) in &groups {
        let (ps, pd): (f64, f64) = (st.iter().map(|x| x.0).sum(), de.iter().map(|x| x.0).sum());
        if st.is_empty() {
            assert!(
                pd < 1e-9,
                "{}: dense-only branch {key:?} with prob {pd}",
                path.display()
            );
            continue;
        }
        assert!(
            (ps - pd).abs() < 1e-9,
            "{}: prob {ps} vs {pd}",
            path.display()
        );
        for w in &witnesses {
            let val = |bs: &Mix| -> f64 {
                bs.iter()
                    .map(|(p, v)| {
                        p * w
                            .iter()
                            .zip(v)
                            .map(|(a, b)| a.conj() * b)
                            .sum::<C>()
                            .norm_sqr()
                    })
                    .sum()
            };
            let (vs, vd) = (val(st), val(de));
            assert!(
                (vs - vd).abs() < 1e-8 * (1.0 + vd.abs()),
                "{}: witness {vs} vs {vd}",
                path.display()
            );
        }
    }
    true
}

#[test]
fn stab_matches_dense_from_zero() {
    let mut compared = Vec::new();
    for (path, prog) in small_benchmarks() {
        if compare(&path, &prog, &vec![0; prog.n_qubits as usize]) {
            compared.push(path.file_stem().unwrap().to_string_lossy().to_string());
        }
    }
    println!("compared {}: {compared:?}", compared.len());
    // 28 of the benchmarks with at most 12 qubits run on the tableau from
    // |0...0>. The rest use a non-Clifford gate on an entangled qubit.
    assert_eq!(compared.len(), 28);
}

#[test]
fn stab_matches_dense_from_product_states() {
    let mut runs = 0;
    for (path, prog) in small_benchmarks() {
        for seed in 1..=4u64 {
            let ks: Vec<u64> = (0..prog.n_qubits as u64)
                .map(|q| (seed * 7 + q * 13 + seed * q) % 6)
                .collect();
            if compare(&path, &prog, &ks) {
                runs += 1;
            }
        }
    }
    println!("runs {runs}");
    // 114 of the 4 x 47 runs (benchmarks with at most 12 qubits). In the
    // others a non-Clifford gate meets an entangled qubit: the qft, qpe, iqpe,
    // and adder programs, ipe3, mbqc_chain4, and repeat-until-success.
    assert_eq!(runs, 114);
}

#[test]
fn canonical_form_tells_states_apart() {
    // |+> and |0> differ, and so do |+> and |->.
    let mut plus = Tableau::zero(1);
    plus.apply(&Gate::H, &[Qubit(0)], &[]).unwrap();
    let mut minus = Tableau::zero(1);
    minus.apply(&Gate::X, &[Qubit(0)], &[]).unwrap();
    minus.apply(&Gate::H, &[Qubit(0)], &[]).unwrap();
    let zero = Tableau::zero(1);
    assert_ne!(plus.canonical(), zero.canonical());
    assert_ne!(plus.canonical(), minus.canonical());
    // A Bell pair made two ways has one canonical form.
    let mut a = Tableau::zero(2);
    a.apply(&Gate::H, &[Qubit(0)], &[]).unwrap();
    a.apply(&Gate::Cx, &[Qubit(0), Qubit(1)], &[]).unwrap();
    let mut b = Tableau::zero(2);
    b.apply(&Gate::H, &[Qubit(1)], &[]).unwrap();
    b.apply(&Gate::Cx, &[Qubit(1), Qubit(0)], &[]).unwrap();
    assert_eq!(a.canonical(), b.canonical());
}

/// A seeded random Clifford program on `n` qubits with mid-circuit
/// measurements, resets, and one feedforward If, in the text format.
fn random_clifford(n: u32, len: usize, seed: u64) -> String {
    let mut x = seed
        .wrapping_mul(6364136223846793005)
        .wrapping_add(1442695040888963407);
    let mut next = |m: u64| {
        x = x
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        (x >> 33) % m
    };
    let one = [
        "h",
        "s",
        "sdg",
        "x",
        "y",
        "z",
        "sx",
        "rz(1.5707963267948966)",
        "rx(3.141592653589793)",
        "ry(4.71238898038469)",
        "p(1.5707963267948966)",
    ];
    let two = ["cx", "cy", "cz", "swap"];
    let mut t = format!("qubits {n}\nbits 2\n");
    for _ in 0..len {
        let a = next(n as u64);
        match next(10) {
            0..=4 => t += &format!("{} q{a}\n", one[next(one.len() as u64) as usize]),
            5..=8 => {
                let b = (a + 1 + next(n as u64 - 1)) % n as u64;
                t += &format!("{} q{a} q{b}\n", two[next(two.len() as u64) as usize]);
            }
            _ => t += &format!("reset q{a}\n"),
        }
    }
    t += &format!(
        "measure q0 -> c0\nif c0 {{ x q{} }}\nmeasure q{} -> c1\n",
        n - 1,
        n - 1
    );
    t
}

#[test]
fn stab_matches_dense_on_random_cliffords() {
    let mut runs = 0;
    for seed in 0..300u64 {
        let n = 2 + (seed % 4) as u32;
        let prog = parse(&random_clifford(n, 25, seed)).unwrap();
        let ks: Vec<u64> = (0..n as u64).map(|q| (seed + 5 * q) % 6).collect();
        let path = PathBuf::from(format!("random_clifford_{seed}"));
        assert!(compare(&path, &prog, &ks), "seed {seed}: unsupported");
        runs += 1;
    }
    assert_eq!(runs, 300);
}

fn tele(corrections: &str) -> Program {
    parse(&format!(
        "qubits 3\nbits 2\nh q1\ncx q1 q2\ncx q0 q1\nh q0\nmeasure q0 -> c0\nmeasure q1 -> c1\n{corrections}"
    ))
    .unwrap()
}

#[test]
fn stab_check_passes_on_equal_programs() {
    use qlin::check::equivalent_stab;
    use qlin::transform::m0::normal_form;
    let mut checked = 0;
    for (path, prog) in small_benchmarks() {
        let nf = normal_form(&prog);
        match equivalent_stab(&prog, &nf, 4, 7, LIMIT) {
            Ok(k) => {
                assert!(k >= 1);
                checked += 1;
            }
            Err(qlin::check::CheckError::Sim(SimError::Unsupported(_))) => {}
            Err(e) => panic!("{}: {e}", path.display()),
        }
    }
    // The 28 benchmarks that the tableau runs from |0...0>.
    assert_eq!(checked, 28);
    let src = tele("if c1 { x q2 }\nif c0 { z q2 }\n");
    let swapped = tele("if c0 { z q2 }\nif c1 { x q2 }\n");
    // X and Z anticommute, so the order changes only a global phase.
    assert!(equivalent_stab(&src, &swapped, 8, 3, LIMIT).is_ok());
}

#[test]
fn stab_check_rejects_planted_errors() {
    use qlin::check::{equivalent_stab, CheckError};
    let src = tele("if c1 { x q2 }\nif c0 { z q2 }\n");
    // The bits agree in every case below. Only the state of q2 differs.
    for wrong in [
        "if c1 { x q2 }\n",
        "if c1 { x q2 }\nif c0 { x q2 }\n",
        "if c0 { x q2 }\nif c1 { z q2 }\n",
    ] {
        let r = equivalent_stab(&src, &tele(wrong), 8, 3, LIMIT);
        assert!(
            matches!(r, Err(CheckError::Mismatch { .. })),
            "{wrong:?}: {r:?}"
        );
    }
    // Deferred with a copy ancilla q3, but the copy feeds the wrong gate.
    let src1 = tele("if c1 { x q2 }\n");
    let good = parse(
        "qubits 4\nbits 2\nh q1\ncx q1 q2\ncx q0 q1\nh q0\nmeasure q0 -> c0\ncx q1 q3\nmeasure q1 -> c1\ncx q3 q2\n",
    )
    .unwrap();
    let bad = parse(
        "qubits 4\nbits 2\nh q1\ncx q1 q2\ncx q0 q1\nh q0\nmeasure q0 -> c0\ncx q1 q3\nmeasure q1 -> c1\ncz q3 q2\n",
    )
    .unwrap();
    assert!(equivalent_stab(&src1, &good, 8, 3, LIMIT).is_ok());
    let r = equivalent_stab(&src1, &bad, 8, 3, LIMIT);
    assert!(matches!(r, Err(CheckError::Mismatch { .. })), "{r:?}");
}

#[test]
fn non_clifford_on_unentangled_qubit_matches_dense() {
    // Qiskit O3's form of the noise source: sx, rz, sx, rz, measure. The
    // first rz meets a Y eigenstate. Also an X eigenstate and a T gate.
    let prog = parse(
        "qubits 3\nbits 3\nh q1\ncx q1 q2\nreset q0\nsx q0\nrz(3.5926194653860555) q0\nsx q0\n\
         rz(9.42477796076938) q0\nmeasure q0 -> c0\nif c0 { x q1 }\nh q0\nt q0\nh q0\n\
         measure q0 -> c1\nif c1 { z q2 }\nmeasure q2 -> c2\n",
    )
    .unwrap();
    for ks in [vec![0, 0, 0], vec![2, 0, 1], vec![4, 0, 0]] {
        assert!(
            compare(Path::new("non_clifford"), &prog, &ks),
            "{ks:?}: unsupported"
        );
    }
}
