//! Fast path over M_t: structure, exit probability, soundness, latency.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use qlin::check::{equivalent, inputs, CheckError};
use qlin::cost::{CostModel, Sync};
use qlin::ir::{Op, Program, Qubit};
use qlin::latency::{expected, records, Noise};
use qlin::sim::MAX_QUBITS;
use qlin::text::parse;
use qlin::transform::fastpath::fast_path;
use qlin::transform::m0::normal_form;

const LIMIT: usize = 1 << 16;
const SIZE: usize = 4096;

fn load(path: &Path) -> Program {
    normal_form(&parse(&std::fs::read_to_string(path).unwrap()).unwrap())
}

fn noise_for(path: &Path, prog: &Program) -> Noise {
    if path
        .file_stem()
        .unwrap()
        .to_string_lossy()
        .ends_with("_noisy")
    {
        Noise::new(prog, &BTreeSet::from([Qubit(prog.n_qubits - 1)]))
    } else {
        Noise::none()
    }
}

fn switches(p: &Program) -> Vec<&Op> {
    p.body
        .iter()
        .filter(|o| matches!(o, Op::Switch { .. }))
        .collect()
}

#[test]
fn repetition_lookup_becomes_one_switch() {
    let p = load(Path::new("benchmarks/hand/repetition3.qlin"));
    let recs = records(&p, LIMIT).unwrap();
    let f0 = fast_path(&p, &recs, &Noise::none(), 0, SIZE);
    assert_eq!((f0.groups, f0.size, f0.exit_prob), (1, 1, 0.0));
    let sw = switches(&f0.prog);
    assert_eq!(sw.len(), 1);
    let Op::Switch { cases, default, .. } = sw[0] else {
        unreachable!()
    };
    assert_eq!(cases[0].0, vec![false, false]);
    assert_eq!(default.len(), 3, "the fallback is the original 3 Ifs");
    let f2 = fast_path(&p, &recs, &Noise::none(), 2, SIZE);
    assert_eq!(f2.size, 4);
}

#[test]
fn exit_probability_matches_the_error_model() {
    // Random X on each data qubit with p = 0.05. Syndrome 00: no error or
    // all three, 0.95^3 + 0.05^3. Syndrome 11 (weight 2): an error on the
    // middle qubit only, or on both outer qubits.
    let path = Path::new("benchmarks/dynamarq/repetition3_0_noisy.qlin");
    let p = load(path);
    let noise = noise_for(path, &p);
    let recs = records(&p, LIMIT).unwrap();
    let q = 0.05f64;
    let want = [
        1.0 - (0.95f64.powi(3) + q.powi(3)),
        q * 0.95f64.powi(2) + q * q * 0.95,
        0.0,
    ];
    for (t, w) in want.iter().enumerate() {
        let f = fast_path(&p, &recs, &noise, t, SIZE);
        assert!(
            (f.exit_prob - w).abs() < 1e-12,
            "t={t}: {} vs {w}",
            f.exit_prob
        );
        equivalent(&p, &f.prog, &inputs(p.n_qubits, 8, 4), LIMIT).unwrap();
    }
}

#[test]
fn checker_rejects_swapped_cases() {
    let path = Path::new("benchmarks/dynamarq/repetition3_0_noisy.qlin");
    let p = load(path);
    let recs = records(&p, LIMIT).unwrap();
    let mut f = fast_path(&p, &recs, &noise_for(path, &p), 2, SIZE).prog;
    for op in &mut f.body {
        if let Op::Switch { cases, .. } = op {
            let (a, b) = (cases[1].1.clone(), cases[2].1.clone());
            cases[1].1 = b;
            cases[2].1 = a;
        }
    }
    let err = equivalent(&p, &f, &inputs(p.n_qubits, 8, 4), LIMIT).unwrap_err();
    assert!(matches!(err, CheckError::Mismatch { .. }), "{err}");
}

#[test]
fn fast_path_is_faster_when_branches_cost_time() {
    let path = Path::new("benchmarks/dynamarq/repetition3_0_noisy.qlin");
    let p = load(path);
    let noise = noise_for(path, &p);
    let recs = records(&p, LIMIT).unwrap();
    let f = fast_path(&p, &recs, &noise, 0, SIZE);
    let c = CostModel {
        sync: Sync::Block,
        t_branch: 200.0,
        ..CostModel::HERON_LIKE
    };
    let none = BTreeSet::new();
    let src = expected(&p, &recs, &c, &noise, &none).unwrap().mean;
    let fast = expected(&f.prog, &recs, &c, &noise, &none).unwrap().mean;
    assert!(fast < src, "{fast} vs {src}");
}

#[test]
#[ignore = "full suite: run by CI job full"]
fn fast_path_is_sound_on_every_small_benchmark() {
    let (mut checked, mut too_big) = (0, Vec::new());
    for dir in ["benchmarks/hand", "benchmarks/jeff", "benchmarks/dynamarq"] {
        let mut paths: Vec<PathBuf> = std::fs::read_dir(dir)
            .unwrap()
            .map(|e| e.unwrap().path())
            .filter(|p| p.extension().is_some_and(|x| x == "qlin"))
            .collect();
        paths.sort();
        for path in paths {
            let p = load(&path);
            if p.n_qubits > MAX_QUBITS {
                too_big.push(path.display().to_string());
                continue;
            }
            let noise = noise_for(&path, &p);
            let recs = records(&p, LIMIT).unwrap();
            // Every t up to the bit count when it is at most 6, else t <= 3.
            // The bit count bounds the dispatched bits m from above.
            let bits = p.n_bits as usize;
            let top = if bits <= 6 { bits } else { 3 };
            for t in 0..=top {
                let f = fast_path(&p, &recs, &noise, t, SIZE);
                equivalent(&p, &f.prog, &inputs(p.n_qubits, 8, 9), LIMIT)
                    .unwrap_or_else(|e| panic!("{} t={t}: {e}", path.display()));
                checked += 1;
            }
        }
    }
    // Pinned: 209 variants. Too big: qft-adder-quantum_7, steane,
    // steane_noisy.
    assert_eq!(too_big.len(), 3, "{too_big:?}");
    assert_eq!(checked, 209);
}
