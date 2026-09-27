//! Pauli conjugation and the sink transform.

use std::collections::BTreeSet;
use std::path::PathBuf;

use qlin::check::{equivalent, inputs, CheckError};
use qlin::ir::{Op, Program, Qubit};
use qlin::latency::{records, Noise};
use qlin::pauli::{conjugate, to_ops, PauliString};
use qlin::sim::MAX_QUBITS;
use qlin::text::{parse, print};
use qlin::transform::fastpath::fast_path;
use qlin::transform::m0::normal_form;
use qlin::transform::sink::sink;

const LIMIT: usize = 1 << 16;

fn prog(n: u32, ops: Vec<Op>) -> Program {
    Program {
        n_qubits: n,
        n_bits: 0,
        body: ops,
    }
}

fn gate(src: &str, n: u32) -> Op {
    parse(&format!("qubits {n}\nbits 0\n{src}\n"))
        .unwrap()
        .body
        .remove(0)
}

fn pauli(code: usize, n: usize) -> PauliString {
    // Two bits per qubit: (x, z).
    (0..n)
        .filter_map(|q| {
            let xz = ((code >> (2 * q)) & 1 == 1, (code >> (2 * q + 1)) & 1 == 1);
            (xz != (false, false)).then_some((Qubit(q as u32), xz))
        })
        .collect()
}

/// `p; g` equals `g; p'` on 4 random product states.
fn conjugation_holds(g: &Op, p: &PauliString, p2: &PauliString, n: u32) -> Result<(), CheckError> {
    let mut a = to_ops(p);
    a.push(g.clone());
    let mut b = vec![g.clone()];
    b.extend(to_ops(p2));
    equivalent(&prog(n, a), &prog(n, b), &inputs(n, 4, 3), 64)
}

#[test]
fn conjugation_table_matches_the_simulator() {
    let mut checked = 0;
    for g in ["h q0", "s q0", "sdg q0", "sx q0", "x q0", "y q0", "z q0"] {
        for code in 1..4 {
            let p = pauli(code, 1);
            let mut p2 = p.clone();
            assert!(conjugate(&mut p2, &gate(g, 1)));
            conjugation_holds(&gate(g, 1), &p, &p2, 1).unwrap_or_else(|e| panic!("{g} {p:?}: {e}"));
            checked += 1;
        }
    }
    for g in ["cx q0 q1", "cx q1 q0", "cy q0 q1", "cz q0 q1", "swap q0 q1"] {
        for code in 1..16 {
            let p = pauli(code, 2);
            let mut p2 = p.clone();
            assert!(conjugate(&mut p2, &gate(g, 2)));
            conjugation_holds(&gate(g, 2), &p, &p2, 2).unwrap_or_else(|e| panic!("{g} {p:?}: {e}"));
            checked += 1;
        }
    }
    assert_eq!(checked, 7 * 3 + 5 * 15);
}

#[test]
fn checker_rejects_a_wrong_conjugation() {
    // X through H is Z. Claiming it stays X must fail.
    let p = pauli(1, 1);
    let err = conjugation_holds(&gate("h q0", 1), &p, &p, 1).unwrap_err();
    assert!(matches!(err, CheckError::Mismatch { .. }));
}

#[test]
fn non_clifford_gates_are_refused() {
    let mut p = pauli(1, 1);
    assert!(!conjugate(&mut p, &gate("t q0", 1)));
    assert!(!conjugate(&mut p, &gate("rz(0.3) q0", 1)));
    assert_eq!(p, pauli(1, 1));
}

#[test]
fn x_correction_sinks_through_h_and_cx_to_the_measurement() {
    let src = parse(
        "qubits 3\nbits 2\nh q0\nh q1\nmeasure q0 -> c0\nif c0 { x q1 }\n\
         h q1\ncx q1 q2\nmeasure q1 -> c1\n",
    )
    .unwrap();
    let s = sink(&src, &Noise::none());
    assert_eq!((s.moved, s.steps), (1, 2));
    // X through H is Z. Z on the control of a CX stays Z.
    let want = "qubits 3\nbits 2\nh q0\nh q1\nmeasure q0 -> c0\nh q1\ncx q1 q2\n\
                if c0 {\n  z q1\n}\nmeasure q1 -> c1\n";
    assert_eq!(print(&s.prog), want);
    equivalent(&src, &s.prog, &inputs(3, 8, 6), LIMIT).unwrap();
}

#[test]
#[ignore = "full suite: run by CI job full"]
fn sink_and_sink_then_fast_path_are_sound_on_every_small_benchmark() {
    let (mut checked, mut moved_any) = (0, 0);
    for dir in ["benchmarks/hand", "benchmarks/jeff", "benchmarks/dynamarq"] {
        let mut paths: Vec<PathBuf> = std::fs::read_dir(dir)
            .unwrap()
            .map(|e| e.unwrap().path())
            .filter(|p| p.extension().is_some_and(|x| x == "qlin"))
            .collect();
        paths.sort();
        for path in paths {
            let p = normal_form(&parse(&std::fs::read_to_string(&path).unwrap()).unwrap());
            if p.n_qubits > MAX_QUBITS {
                continue;
            }
            let noise = if path
                .file_stem()
                .unwrap()
                .to_string_lossy()
                .ends_with("_noisy")
            {
                Noise::new(&p, &BTreeSet::from([Qubit(p.n_qubits - 1)]))
            } else {
                Noise::none()
            };
            let s = sink(&p, &noise);
            if s.moved > 0 {
                moved_any += 1;
            }
            let name = path.display().to_string();
            equivalent(&p, &s.prog, &inputs(p.n_qubits, 8, 21), LIMIT)
                .unwrap_or_else(|e| panic!("{name} sink: {e}"));
            let recs = records(&s.prog, LIMIT).unwrap();
            for t in 0..=2 {
                let f = fast_path(&s.prog, &recs, &noise, t, 4096);
                equivalent(&p, &f.prog, &inputs(p.n_qubits, 8, 22), LIMIT)
                    .unwrap_or_else(|e| panic!("{name} sink + fast path t={t}: {e}"));
            }
            checked += 1;
        }
    }
    // Pinned: 47 benchmarks, the sink moves at least one If in 17.
    assert_eq!(checked, 47);
    assert_eq!(moved_any, 17);
}
