//! `stats_with_noise` removes error-injection ops before it counts.

use std::collections::BTreeSet;

use qlin::ir::Qubit;
use qlin::stats::{stats, stats_with_noise};
use qlin::text::parse;

const CLEAN: &str = "qubits 5\nbits 2\nx q0\ncx q0 q1\ncx q1 q2\n\
    cx q0 q3\ncx q1 q3\ncx q1 q4\ncx q2 q4\nmeasure q3 -> c0\nmeasure q4 -> c1\n\
    if c0 & !c1 { x q0 }\nif c0 & c1 { x q1 }\nif !c0 & c1 { x q2 }\n";

// The same round with a random X on q1 from noise qubit q5 (bit c2).
const NOISY: &str = "qubits 6\nbits 3\nx q0\ncx q0 q1\ncx q1 q2\n\
    ry(0.4510268117962624) q5\nmeasure q5 -> c2\nif c2 { x q1 }\nreset q5\n\
    cx q0 q3\ncx q1 q3\ncx q1 q4\ncx q2 q4\nmeasure q3 -> c0\nmeasure q4 -> c1\n\
    if c0 & !c1 { x q0 }\nif c0 & c1 { x q1 }\nif !c0 & c1 { x q2 }\n";

#[test]
fn noise_ops_do_not_count() {
    let clean = stats(&parse(CLEAN).unwrap());
    let noisy = parse(NOISY).unwrap();
    let raw = stats(&noisy);
    assert_eq!(raw.feedforward, 4);
    let s = stats_with_noise(&noisy, &BTreeSet::from([Qubit(5)]));
    assert_eq!(s.feedforward, clean.feedforward);
    assert_eq!(s.core_branch, clean.core_branch);
    assert_eq!(s.gates, clean.gates);
    assert_eq!(s.measurements, clean.measurements);
    assert_eq!(s.qubits, clean.qubits);
}
