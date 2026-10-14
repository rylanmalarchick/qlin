//! Certifiers on the benchmarks past 12 qubits, with the stabilizer
//! backend: exact records, the M0 normal form, the fast path with and
//! without the Pauli sink, and the defer search leaves, each compared with
//! the source by `check`.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use qlin::check::{check, Checked};
use qlin::cost::CostModel;
use qlin::ir::{Program, Qubit};
use qlin::latency::{records, Noise};
use qlin::search::Problem;
use qlin::sim::{SimError, MAX_QUBITS};
use qlin::text::parse;
use qlin::transform::fastpath::fast_path;
use qlin::transform::m0::normal_form;
use qlin::transform::sink::sink;

const LIMIT: usize = 1 << 16;
const SIZE: usize = 4096;

fn load(path: &Path) -> Program {
    parse(&std::fs::read_to_string(path).unwrap()).unwrap()
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

fn large_benchmarks() -> Vec<(PathBuf, Program)> {
    let mut out = Vec::new();
    for dir in [
        "benchmarks/hand",
        "benchmarks/jeff",
        "benchmarks/dynamarq",
        "benchmarks/qec",
    ] {
        for e in std::fs::read_dir(dir).unwrap() {
            let p = e.unwrap().path();
            if p.extension().is_some_and(|x| x == "qlin") {
                let prog = load(&p);
                if prog.n_qubits > MAX_QUBITS {
                    out.push((p, prog));
                }
            }
        }
    }
    out.sort_by(|a, b| a.0.cmp(&b.0));
    out
}

fn must_check(a: &Program, b: &Program, what: &str) {
    match check(a, b, 8, 9, LIMIT) {
        Ok(Checked::Stabilizer(k)) => assert!(k >= 1, "{what}: no input compared"),
        Ok(Checked::Dense) => panic!("{what}: past 12 qubits but checked dense"),
        Err(e) => panic!("{what}: {e}"),
    }
}

#[test]
#[ignore = "full suite: run by CI job full"]
fn certifiers_hold_past_twelve_qubits() {
    let (mut variants, mut unsupported, mut searched) = (0, Vec::new(), 0);
    let (mut leaves_checked, mut leaves_unchecked) = (0, 0);
    for (path, p) in large_benchmarks() {
        let name = path.display().to_string();
        let recs = match records(&p, LIMIT) {
            Ok(r) => r,
            Err(SimError::TooManyQubits(_)) => {
                unsupported.push(name);
                continue;
            }
            Err(e) => panic!("{name}: {e}"),
        };
        let total: f64 = recs.iter().map(|r| r.prob).sum();
        assert!((total - 1.0).abs() < 1e-9, "{name}: records sum to {total}");
        let noise = noise_for(&path, &p);
        must_check(&p, &normal_form(&p), &format!("{name} M0"));
        variants += 1;
        let sunk = sink(&p, &noise).prog;
        for (label, base) in [("plain", &p), ("sink", &sunk)] {
            let base_recs = records(base, LIMIT).unwrap();
            for t in 0..=2 {
                let f = fast_path(base, &base_recs, &noise, t, SIZE);
                must_check(&p, &f.prog, &format!("{name} {label} t={t}"));
                variants += 1;
            }
        }
        let mut prob = Problem::new(&p, CostModel::HERON_LIKE, noise, LIMIT).unwrap();
        if prob.cands.len() <= 12 {
            prob.check_leaves = true;
            let ex = prob.exhaustive().unwrap();
            assert_eq!(ex.bound_violations, 0, "{name}");
            let bnb = prob.branch_and_bound().unwrap();
            assert_eq!(bnb.best.mean, ex.best.mean, "{name}");
            searched += 1;
            leaves_checked += prob.checked.get();
            leaves_unchecked += prob.unchecked.get();
        }
    }
    println!(
        "variants {variants}, searched {searched}, leaves {leaves_checked} checked \
         {leaves_unchecked} unchecked, unsupported {unsupported:?}"
    );
    // Pinned. 15 benchmarks past 12 qubits: steane, steane_noisy, the 12
    // repetition codes of benchmarks/qec, and qft-adder-quantum_7, which
    // uses non-Clifford gates on entangled qubits. 14 x 7 variants (M0,
    // plus t = 0, 1, 2 with and without the sink). None has a defer
    // candidate (their conditions read several bits), so the exhaustive
    // search and branch and bound each check one leaf per benchmark.
    assert_eq!(
        unsupported,
        vec!["benchmarks/jeff/qft-adder-quantum_7.qlin"]
    );
    assert_eq!(variants, 98);
    assert_eq!(searched, 14);
    assert_eq!((leaves_checked, leaves_unchecked), (28, 0));
}
