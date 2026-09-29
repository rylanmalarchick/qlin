//! Gate G0: the per-outcome trace enumerator.

use qlin::ir::{Bit, Op, Program};
use qlin::text::{format_leaf, parse};
use qlin::trace::{enumerate, TraceError};

const LIMIT: usize = 1 << 12;

fn load(path: &str) -> Program {
    parse(&std::fs::read_to_string(path).unwrap()).unwrap()
}

fn names(ops: &[Op]) -> Vec<String> {
    ops.iter().map(|o| format_leaf(o).unwrap()).collect()
}

#[test]
fn teleportation_has_four_traces_with_the_right_corrections() {
    let traces = enumerate(&load("benchmarks/hand/teleportation.qlin"), LIMIT).unwrap();
    assert_eq!(traces.len(), 4);
    let t11 = traces
        .iter()
        .find(|t| t.outcomes == vec![(Bit(0), true), (Bit(1), true)])
        .unwrap();
    assert_eq!(&names(&t11.ops)[6..], ["x q2", "z q2"]);
    let t00 = traces
        .iter()
        .find(|t| t.outcomes == vec![(Bit(0), false), (Bit(1), false)])
        .unwrap();
    assert_eq!(t00.ops.len(), 6);
    assert!(traces.iter().all(|t| !t.truncated));
}

#[test]
fn loop_traces_stop_at_the_bound() {
    let p = parse("qubits 1\nbits 1\nloop max 3 { h q0  measure q0 -> c0 } until c0\n").unwrap();
    let traces = enumerate(&p, LIMIT).unwrap();
    // Exit on try 1, 2, or 3, plus one run that fails all 3 tries.
    assert_eq!(traces.len(), 4);
    let truncated: Vec<_> = traces.iter().filter(|t| t.truncated).collect();
    assert_eq!(truncated.len(), 1);
    assert_eq!(truncated[0].outcomes, vec![(Bit(0), false); 3]);
}

#[test]
fn trace_limit_is_enforced() {
    let p = parse("qubits 1\nbits 1\nrepeat 20 { measure q0 -> c0 }\n").unwrap();
    assert_eq!(
        enumerate(&p, 1000),
        Err(TraceError::TooManyTraces { limit: 1000 })
    );
}
