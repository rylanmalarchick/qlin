//! Gate G2: branch and bound matches exhaustive search, and the
//! relaxation bound never exceeds the best completion.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use qlin::cost::CostModel;
use qlin::ir::{Program, Qubit};
use qlin::latency::Noise;
use qlin::search::{Problem, EPS, MAX_EXHAUSTIVE};
use qlin::sim::MAX_QUBITS;
use qlin::text::parse;
use qlin::transform::m0::normal_form;

const LIMIT: usize = 1 << 16;

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

#[test]
fn teleportation_best_is_both_deferred() {
    let p = load(Path::new("benchmarks/hand/teleportation.qlin"));
    let mut prob = Problem::new(&p, CostModel::HERON_LIKE, Noise::none(), LIMIT).unwrap();
    prob.check_leaves = true;
    let ex = prob.exhaustive().unwrap();
    assert_eq!(ex.best.defer, vec![true, true]);
    assert_eq!(ex.best.mean, 1104.0);
    assert_eq!(ex.bound_violations, 0);
    assert_eq!(ex.prefixes, 7);
    let bnb = prob.branch_and_bound().unwrap();
    assert_eq!(bnb.best, ex.best);
    // The floor is the classical program with no feedforward wait.
    assert_eq!(prob.floor().unwrap(), 1000.0);
}

#[test]
#[ignore = "full suite: run by CI job full"]
fn bnb_matches_exhaustive_on_every_small_benchmark() {
    let (mut certified, mut skipped) = (Vec::new(), Vec::new());
    for dir in ["benchmarks/hand", "benchmarks/jeff", "benchmarks/dynamarq"] {
        let mut paths: Vec<PathBuf> = std::fs::read_dir(dir)
            .unwrap()
            .map(|e| e.unwrap().path())
            .filter(|p| p.extension().is_some_and(|x| x == "qlin"))
            .collect();
        paths.sort();
        for path in paths {
            let p = load(&path);
            let name = path.display().to_string();
            if p.n_qubits > MAX_QUBITS {
                skipped.push(format!("{name}: {} qubits", p.n_qubits));
                continue;
            }
            let prob =
                Problem::new(&p, CostModel::HERON_LIKE, noise_for(&path, &p), LIMIT).unwrap();
            if prob.cands.is_empty() || prob.cands.len() > MAX_EXHAUSTIVE {
                skipped.push(format!("{name}: {} candidates", prob.cands.len()));
                continue;
            }
            let ex = prob.exhaustive().unwrap();
            let bnb = prob.branch_and_bound().unwrap();
            assert_eq!(ex.bound_violations, 0, "{name}");
            assert!(
                (bnb.best.mean - ex.best.mean).abs() <= EPS,
                "{name}: {} vs {}",
                bnb.best.mean,
                ex.best.mean
            );
            assert!(
                !ex.best.better(&bnb.best),
                "{name}: exhaustive tie-break is better"
            );
            assert!(prob.floor().unwrap() <= ex.best.mean + EPS, "{name}");
            certified.push(name);
        }
    }
    // Pinned. Skips: 25 with no candidates, 4 over 12 qubits, and iqft_7
    // and iqpe_7 with 21 candidates (branch and bound only, not certified).
    assert_eq!(certified.len(), 19, "{certified:#?}");
    assert_eq!(skipped.len(), 31, "{skipped:#?}");
}
