//! Defer: legality, the direct and copy forms, soundness, and latency.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use qlin::check::{equivalent, inputs, CheckError};
use qlin::cost::CostModel;
use qlin::ir::{Gate, Op, Program, Qubit};
use qlin::latency::{expected, records, Noise};
use qlin::sim::MAX_QUBITS;
use qlin::text::{parse, print};
use qlin::transform::defer::{apply, candidates, Choice};
use qlin::transform::m0::normal_form;

const LIMIT: usize = 1 << 16;

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

fn small_benchmarks() -> Vec<(PathBuf, Program)> {
    let mut out = Vec::new();
    for dir in ["benchmarks/hand", "benchmarks/jeff", "benchmarks/dynamarq"] {
        for e in std::fs::read_dir(dir).unwrap() {
            let p = e.unwrap().path();
            if p.extension().is_some_and(|x| x == "qlin") {
                let prog = normal_form(&load(&p));
                if prog.n_qubits <= MAX_QUBITS {
                    out.push((p, prog));
                }
            }
        }
    }
    out.sort_by(|a, b| a.0.cmp(&b.0));
    out
}

#[test]
fn teleportation_defers_both_corrections_directly() {
    let p = load(Path::new("benchmarks/hand/teleportation.qlin"));
    let cands = candidates(&p, &Noise::none());
    assert_eq!(
        cands.iter().map(|c| c.index).collect::<Vec<_>>(),
        vec![6, 7]
    );
    let v = apply(&p, &cands, &[Choice::Defer, Choice::Defer]);
    assert_eq!(v.added_qubits, 0);
    assert_eq!(v.added_2q, 2);
    let want = "qubits 3\nbits 2\nh q1\ncx q1 q2\ncx q0 q1\nh q0\n\
                cx q1 q2\nmeasure q1 -> c1\ncz q0 q2\nmeasure q0 -> c0\n";
    assert_eq!(print(&v.prog), want);
    equivalent(&p, &v.prog, &inputs(3, 8, 3), LIMIT).unwrap();
    // cx q1 q2 168-236, measure q1 236-1036, cz 236-304, measure q0 304-1104.
    let recs = records(&p, LIMIT).unwrap();
    let e = expected(
        &v.prog,
        &recs,
        &CostModel::HERON_LIKE,
        &Noise::none(),
        &v.relaxed,
    )
    .unwrap();
    assert_eq!((e.mean, e.worst), (1104.0, 1104.0));
}

#[test]
fn reused_qubits_need_a_copy() {
    // iqft resets q0 after each measure, so later corrections read copies.
    let p = normal_form(&load(Path::new("benchmarks/jeff/iqft_3.qlin")));
    let cands = candidates(&p, &Noise::none());
    assert_eq!(cands.len(), 3);
    let v = apply(&p, &cands, &[Choice::Defer; 3]);
    assert_eq!(v.added_qubits, 2, "{}", print(&v.prog));
    equivalent(&p, &v.prog, &inputs(p.n_qubits, 8, 5), LIMIT).unwrap();
}

#[test]
fn relaxed_ifs_are_marked_and_unchanged() {
    let p = load(Path::new("benchmarks/hand/teleportation.qlin"));
    let cands = candidates(&p, &Noise::none());
    let v = apply(&p, &cands, &[Choice::Relaxed, Choice::Classical]);
    assert_eq!(v.prog, p);
    assert_eq!(v.relaxed, BTreeSet::from([vec![6]]));
}

#[test]
fn checker_rejects_a_defer_with_the_wrong_control() {
    let p = load(Path::new("benchmarks/hand/teleportation.qlin"));
    let cands = candidates(&p, &Noise::none());
    let mut v = apply(&p, &cands, &[Choice::Defer, Choice::Defer]).prog;
    for op in &mut v.body {
        if let Op::Gate {
            gate: Gate::Cz,
            qubits,
            ..
        } = op
        {
            qubits[0] = Qubit(1);
        }
    }
    let err = equivalent(&p, &v, &inputs(3, 8, 3), LIMIT).unwrap_err();
    assert!(matches!(err, CheckError::Mismatch { .. }), "{err}");
}

#[test]
#[ignore = "full suite: run by CI job full"]
fn every_defer_is_sound_on_every_small_benchmark() {
    let (mut checked, mut too_big) = (0, Vec::new());
    let mut with_candidates = 0;
    for (path, p) in small_benchmarks() {
        let noise = noise_for(&path, &p);
        let cands = candidates(&p, &noise);
        if !cands.is_empty() {
            with_candidates += 1;
        }
        let mut choice_sets: Vec<Vec<Choice>> = (0..cands.len())
            .map(|i| {
                let mut c = vec![Choice::Classical; cands.len()];
                c[i] = Choice::Defer;
                c
            })
            .collect();
        choice_sets.push(vec![Choice::Defer; cands.len()]);
        for choices in choice_sets {
            let v = apply(&p, &cands, &choices);
            if v.prog.n_qubits > MAX_QUBITS {
                // The copies push the variant past the simulator limit.
                too_big.push(format!("{} {choices:?}", path.display()));
                continue;
            }
            equivalent(&p, &v.prog, &inputs(p.n_qubits, 8, 11), LIMIT)
                .unwrap_or_else(|e| panic!("{} {choices:?}: {e}", path.display()));
            checked += 1;
        }
    }
    // Pinned: 159 variants checked. 4 are over the simulator limit, all
    // single defers on five_qubit_code_noisy (one copy qubit makes 13).
    assert_eq!(checked, 159);
    assert_eq!(too_big.len(), 4, "{too_big:#?}");
    assert!(too_big.iter().all(|t| t.contains("five_qubit_code_noisy")));
    assert_eq!(with_candidates, 21);
}
