//! The Switch op: text, validation, simulation, trace, and core analysis.

use qlin::analysis::core::{core, CoreKind};
use qlin::check::{equivalent, inputs};
use qlin::ir::{Bit, ValidateError};
use qlin::text::{parse, print, LoadError};
use qlin::trace::enumerate;

/// The 3-qubit repetition round with its lookup table as one Switch.
const REP3_SWITCH: &str = "qubits 5\nbits 2\nx q0\ncx q0 q1\ncx q1 q2\n\
    cx q0 q3\ncx q1 q3\ncx q1 q4\ncx q2 q4\nmeasure q3 -> c0\nmeasure q4 -> c1\n\
    switch c0 c1 { case 1 0 { x q0 } case 1 1 { x q1 } case 0 1 { x q2 } }\n";

#[test]
fn print_is_a_fixed_point() {
    let p = parse(REP3_SWITCH).unwrap();
    let once = print(&p);
    assert!(
        once.contains("switch c0 c1 {\n  case 1 0 {\n    x q0\n  }\n"),
        "{once}"
    );
    assert_eq!(print(&parse(&once).unwrap()), once);
    let with_default = "qubits 1\nbits 2\nswitch c0 c1 { case 0 0 { x q0 } default { h q0 } }\n";
    let p = parse(with_default).unwrap();
    assert_eq!(parse(&print(&p)).unwrap(), p);
}

#[test]
fn validation_rejects_bad_switches() {
    let bad = |src: &str| match parse(src).unwrap_err() {
        LoadError::Invalid(ValidateError::BadSwitch(why)) => why,
        other => panic!("{other}"),
    };
    assert!(
        bad("qubits 1\nbits 2\nswitch c0 c1 { case 1 0 { x q0 } case 1 0 { } }\n")
            .contains("repeated case")
    );
    assert!(bad("qubits 1\nbits 2\nswitch c0 c0 { case 1 0 { x q0 } }\n").contains("repeated bit"));
}

#[test]
fn switch_equals_the_if_chain() {
    let ifs = parse(&std::fs::read_to_string("benchmarks/hand/repetition3.qlin").unwrap()).unwrap();
    let sw = parse(REP3_SWITCH).unwrap();
    equivalent(&ifs, &sw, &inputs(5, 8, 2), 1 << 12).unwrap();
}

#[test]
fn trace_runs_the_selected_case() {
    let p = parse(
        "qubits 3\nbits 2\nh q0\nh q1\nmeasure q0 -> c0\nmeasure q1 -> c1\n\
                   switch c0 c1 { case 1 0 { x q2 } default { z q2 } }\n",
    )
    .unwrap();
    let traces = enumerate(&p, 64).unwrap();
    assert_eq!(traces.len(), 4);
    for t in traces {
        let last = qlin::text::format_leaf(t.ops.last().unwrap()).unwrap();
        let want = if t.outcomes == vec![(Bit(0), true), (Bit(1), false)] {
            "x q2"
        } else {
            "z q2"
        };
        assert_eq!(last, want, "{:?}", t.outcomes);
    }
}

#[test]
fn every_case_leaf_is_core_and_the_switch_is_one_feedforward() {
    let r = core(&parse(REP3_SWITCH).unwrap());
    assert_eq!(r.feedforward, 1);
    let paths: Vec<Vec<usize>> = r.core.iter().map(|(p, _)| p.clone()).collect();
    assert_eq!(paths, vec![vec![9, 0, 0], vec![9, 1, 0], vec![9, 2, 0]]);
    assert!(r.core.iter().all(|(_, k)| *k == CoreKind::Branch));
}
