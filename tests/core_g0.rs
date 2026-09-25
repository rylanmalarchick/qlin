//! Gate G0: the dynamic core under move set M0 matches the hand analysis.

use qlin::analysis::core::{core, CoreKind, CoreReport};
use qlin::text::parse;

fn load(path: &str) -> qlin::ir::Program {
    let src = std::fs::read_to_string(path).unwrap();
    parse(&src).unwrap()
}

fn branch(paths: &[&[usize]]) -> Vec<(Vec<usize>, CoreKind)> {
    paths
        .iter()
        .map(|p| (p.to_vec(), CoreKind::Branch))
        .collect()
}

#[test]
fn teleportation_core_is_the_two_corrections() {
    let r = core(&load("benchmarks/hand/teleportation.qlin"));
    assert_eq!(r.core, branch(&[&[6, 0, 0], &[7, 0, 0]]));
    assert!(r.movable.is_empty());
    assert!(r.dead.is_empty());
    assert_eq!(r.feedforward, 2);
    assert_eq!(r.measurements, 2);
}

#[test]
fn repetition_round_core_is_the_three_lookup_flips() {
    let r = core(&load("benchmarks/hand/repetition3.qlin"));
    assert_eq!(r.core, branch(&[&[9, 0, 0], &[10, 0, 0], &[11, 0, 0]]));
    assert!(r.movable.is_empty());
    assert_eq!(r.feedforward, 3);
    assert_eq!(r.measurements, 2);
}

fn run(src: &str) -> CoreReport {
    core(&parse(src).unwrap())
}

#[test]
fn common_prefix_hoists() {
    let r = run("qubits 3\nbits 1\nh q0\nmeasure q0 -> c0\n\
                 if c0 { h q1  x q2 } else { h q1  z q2 }\n");
    assert_eq!(r.movable, vec![(vec![2, 0, 0], vec![2, 1, 0])]);
    assert_eq!(r.core, branch(&[&[2, 0, 1], &[2, 1, 1]]));
}

#[test]
fn disjoint_op_commutes_to_the_front() {
    let r = run("qubits 3\nbits 1\nh q0\nmeasure q0 -> c0\n\
                 if c0 { x q2  h q1  y q2 } else { h q1 }\n");
    // `h q1` sits between two q2 ops, so only commutation can match it.
    assert_eq!(r.movable, vec![(vec![2, 0, 1], vec![2, 1, 0])]);
    assert_eq!(r.core, branch(&[&[2, 0, 0], &[2, 0, 2]]));
}

#[test]
fn overlapping_ops_do_not_commute() {
    let r = run("qubits 2\nbits 1\nh q0\nmeasure q0 -> c0\n\
                 if c0 { h q1  x q1 } else { x q1  h q1 }\n");
    assert!(r.movable.is_empty());
    assert_eq!(
        r.core,
        branch(&[&[2, 0, 0], &[2, 0, 1], &[2, 1, 0], &[2, 1, 1]])
    );
}

#[test]
fn common_suffix_merges() {
    let r = run("qubits 3\nbits 1\nh q0\nmeasure q0 -> c0\n\
                 if c0 { h q1  x q1 } else { z q1  x q1 }\n");
    // `x q1` cannot hoist past `h q1` or `z q1`, so this match is a merge.
    assert_eq!(r.movable, vec![(vec![2, 0, 1], vec![2, 1, 1])]);
    assert_eq!(r.core, branch(&[&[2, 0, 0], &[2, 1, 0]]));
}

#[test]
fn hoist_may_not_write_a_condition_bit() {
    // The measure writes c0, which the If reads, so it cannot move above
    // the If. Here `x q1` and `y q1` also block it from moving below.
    let r = run("qubits 3\nbits 1\nh q0\nmeasure q0 -> c0\n\
                 if c0 { measure q1 -> c0  x q1 } else { measure q1 -> c0  y q1 }\n");
    assert!(r.movable.is_empty());
    assert_eq!(r.core.len(), 4);
    // Without the shared qubit, it merges below the If, past `x q2`.
    let r = run("qubits 3\nbits 1\nh q0\nmeasure q0 -> c0\n\
                 if c0 { measure q1 -> c0  x q2 } else { measure q1 -> c0 }\n");
    assert_eq!(r.movable, vec![(vec![2, 0, 0], vec![2, 1, 0])]);
    assert_eq!(r.core, branch(&[&[2, 0, 1]]));
}

#[test]
fn unmeasured_bit_folds_to_zero() {
    let r = run("qubits 1\nbits 1\nif c0 { x q0 } else { h q0 }\n");
    assert!(r.core.is_empty());
    assert_eq!(r.dead, vec![vec![0, 0, 0]]);
    assert_eq!(r.feedforward, 0);
}

#[test]
fn measured_bit_never_folds_from_the_quantum_state() {
    // q0 is |0>, so c0 is always 0 on hardware. The analysis does not
    // infer that. BQCP-style propagation is a separate pre-pass.
    let r = run("qubits 2\nbits 1\nmeasure q0 -> c0\nif c0 { x q1 }\n");
    assert_eq!(r.core, branch(&[&[1, 0, 0]]));
    assert_eq!(r.feedforward, 1);
}

#[test]
fn loop_body_repeats_on_a_measured_bit() {
    let r = run("qubits 1\nbits 1\nloop max 4 { h q0  measure q0 -> c0 } until c0\n");
    assert_eq!(
        r.core,
        vec![
            (vec![0, 0, 0], CoreKind::LoopRepeat),
            (vec![0, 0, 1], CoreKind::LoopRepeat),
        ]
    );
    assert_eq!(r.feedforward, 1);
    assert_eq!(r.measurements, 1);
}
