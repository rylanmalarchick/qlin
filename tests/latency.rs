//! Replay latency against hand-computed schedules (cost model HERON_LIKE:
//! 1q 32, 2q 68, measure 800, feedforward 600 ns).

use std::collections::BTreeSet;

use qlin::cost::CostModel;
use qlin::ir::{Bit, Qubit};
use qlin::latency::{expected, records, replay, Noise};
use qlin::text::parse;

const C: CostModel = CostModel::HERON_LIKE;
const LIMIT: usize = 1 << 12;

fn load(path: &str) -> qlin::ir::Program {
    parse(&std::fs::read_to_string(path).unwrap()).unwrap()
}

#[test]
fn teleportation_per_outcome_makespans() {
    // h q1 0-32, cx q1 q2 32-100, cx q0 q1 100-168, h q0 168-200,
    // measure q0 200-1000, measure q1 168-968.
    // x q2 waits for c1: 968 + 600 = 1568, ends 1600.
    // z q2 waits for c0: 1000 + 600 = 1600, ends 1632.
    let p = load("benchmarks/hand/teleportation.qlin");
    let recs = records(&p, LIMIT).unwrap();
    assert_eq!(recs.len(), 4);
    let none = Noise::none();
    let relaxed = BTreeSet::new();
    for r in &recs {
        let (c0, c1) = (r.outcomes[&Bit(0)][0], r.outcomes[&Bit(1)][0]);
        let want = match (c0, c1) {
            (false, false) => 1000.0,
            (false, true) => 1600.0,
            (true, _) => 1632.0,
        };
        assert_eq!(
            replay(&p, r, &C, &none, &relaxed).unwrap(),
            want,
            "{c0} {c1}"
        );
    }
    let e = expected(&p, &recs, &C, &none, &relaxed).unwrap();
    assert!((e.mean - 1466.0).abs() < 1e-9, "{}", e.mean);
    assert_eq!(e.worst, 1632.0);
}

#[test]
fn relaxed_ifs_skip_the_feedforward_wait() {
    // Relax both corrections: x q2 starts when q2 is free (100), and z q2
    // follows it. The makespan is set by measure q0 (1000).
    let p = load("benchmarks/hand/teleportation.qlin");
    let recs = records(&p, LIMIT).unwrap();
    let relaxed = BTreeSet::from([vec![6], vec![7]]);
    for r in &recs {
        assert_eq!(replay(&p, r, &C, &Noise::none(), &relaxed).unwrap(), 1000.0);
    }
}

#[test]
fn loop_iterations_wait_for_the_exit_bit() {
    // Try 1 ends 832. Try 2: h at 832 + 600 = 1432, measure ends 2264.
    // Try 3: h at 2864, measure ends 3696. The 4th outcome is the
    // truncated run (3 failures), which also ends at 3696.
    let p = parse("qubits 1\nbits 1\nloop max 3 { h q0  measure q0 -> c0 } until c0\n").unwrap();
    let recs = records(&p, LIMIT).unwrap();
    let e = expected(&p, &recs, &C, &Noise::none(), &BTreeSet::new()).unwrap();
    let want = 0.5 * 832.0 + 0.25 * 2264.0 + 0.25 * 3696.0;
    assert!((e.mean - want).abs() < 1e-9, "{} vs {want}", e.mean);
    assert!((e.truncated_prob - 0.125).abs() < 1e-12);
}

#[test]
fn noise_ops_take_no_time() {
    let clean = parse("qubits 2\nbits 1\nh q0\nmeasure q0 -> c0\nif c0 { x q1 }\n").unwrap();
    let noisy = parse(
        "qubits 3\nbits 2\nry(0.45) q2\nmeasure q2 -> c1\nif c1 { x q0 }\nreset q2\n\
         h q0\nmeasure q0 -> c0\nif c0 { x q1 }\n",
    )
    .unwrap();
    let rc = records(&clean, LIMIT).unwrap();
    let rn = records(&noisy, LIMIT).unwrap();
    let ec = expected(&clean, &rc, &C, &Noise::none(), &BTreeSet::new()).unwrap();
    let noise = Noise::new(&noisy, &BTreeSet::from([Qubit(2)]));
    let en = expected(&noisy, &rn, &C, &noise, &BTreeSet::new()).unwrap();
    // Both: h 0-32, measure 32-832, x at 1432-1464 when c0 = 1.
    assert_eq!(ec.worst, 1464.0);
    assert_eq!(en.worst, 1464.0);
}
