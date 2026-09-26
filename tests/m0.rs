//! M0 normal form: semantics, and optimality among prefix applications.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use qlin::analysis::core::core;
use qlin::check::{equivalent, inputs, CheckError};
use qlin::cost::CostModel;
use qlin::ir::{Program, Qubit};
use qlin::latency::{expected, records, Noise};
use qlin::sim::MAX_QUBITS;
use qlin::text::{parse, print};
use qlin::transform::m0::{apply_prefixes, move_counts, normal_form};

const LIMIT: usize = 1 << 16;
/// Upper bound on prefix combinations the certifier enumerates.
const MAX_COMBOS: usize = 4096;

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

#[test]
fn mbqc_normal_form_moves_the_shared_measurements_out() {
    let p = load(&PathBuf::from("benchmarks/hand/mbqc_chain4.qlin"));
    assert_eq!(core(&p).movable.len(), 4);
    let n = normal_form(&p);
    assert!(core(&n).movable.is_empty());
    let text = print(&n);
    assert!(text.contains("}\nh q1\nmeasure q1 -> c1\n"), "{text}");
    assert!(text.contains("}\nh q2\nmeasure q2 -> c2\n"), "{text}");
    equivalent(&p, &n, &inputs(p.n_qubits, 8, 1), LIMIT).unwrap();
}

#[test]
fn checker_rejects_a_wrong_rewrite() {
    let p = load(&PathBuf::from("benchmarks/hand/teleportation.qlin"));
    let wrong = parse(&print(&p).replace("if c0 {\n  z q2\n}", "if c0 {\n  x q2\n}")).unwrap();
    let err = equivalent(&p, &wrong, &inputs(p.n_qubits, 8, 1), LIMIT).unwrap_err();
    assert!(matches!(err, CheckError::Mismatch { .. }), "{err}");
}

#[test]
fn normal_form_is_equivalent_on_every_small_benchmark() {
    let all = small_benchmarks();
    assert!(all.len() >= 45, "{}", all.len());
    for (path, p) in &all {
        let n = normal_form(p);
        equivalent(p, &n, &inputs(p.n_qubits, 8, 7), LIMIT)
            .unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    }
}

#[test]
fn normal_form_is_optimal_among_prefix_applications() {
    let c = CostModel::HERON_LIKE;
    let mut certified = 0;
    for (path, p) in small_benchmarks() {
        let counts = move_counts(&p);
        let combos: usize = counts.iter().map(|(h, m)| (h + 1) * (m + 1)).product();
        assert!(combos <= MAX_COMBOS, "{}: {combos} combos", path.display());
        let recs = records(&p, LIMIT).unwrap();
        let noise = noise_for(&path, &p);
        let none = BTreeSet::new();
        let best = expected(&normal_form(&p), &recs, &c, &noise, &none)
            .unwrap()
            .mean;
        for code in 0..combos {
            let mut rest = code;
            let pick: Vec<(usize, usize)> = counts
                .iter()
                .map(|(h, m)| {
                    let (hh, mm) = (rest % (h + 1), (rest / (h + 1)) % (m + 1));
                    rest /= (h + 1) * (m + 1);
                    (hh, mm)
                })
                .collect();
            let v = apply_prefixes(&p, &|k| pick[k]);
            let e = expected(&v, &recs, &c, &noise, &none).unwrap().mean;
            assert!(
                best <= e + 1e-9,
                "{}: prefix {pick:?} gives {e} < {best}",
                path.display()
            );
        }
        certified += 1;
    }
    assert!(certified >= 45);
}
