//! Sampled records give the exact expected latency within a few standard
//! errors. The seeds are fixed, so the test is deterministic.

use std::collections::BTreeSet;

use qlin::cost::{CostModel, Sync};
use qlin::latency::{expected, records, sampled_records, Noise, Record};
use qlin::text::parse;

fn mean_and_se(
    prog: &qlin::ir::Program,
    recs: &[Record],
    cost: &CostModel,
    n: usize,
) -> (f64, f64) {
    let none = BTreeSet::new();
    let lats: Vec<(f64, f64)> = recs
        .iter()
        .map(|r| {
            let one = Record {
                prob: 1.0,
                ..r.clone()
            };
            (
                r.prob,
                expected(prog, &[one], cost, &Noise::none(), &none)
                    .unwrap()
                    .mean,
            )
        })
        .collect();
    let mean: f64 = lats.iter().map(|(w, l)| w * l).sum();
    let var: f64 = lats.iter().map(|(w, l)| w * (l - mean).powi(2)).sum();
    (mean, (var / (n as f64 - 1.0)).sqrt())
}

#[test]
fn sampled_mean_matches_exact() {
    let cost = CostModel {
        sync: Sync::Block,
        t_branch: 3450.0,
        ..CostModel::HERON_KINGSTON
    };
    let none = BTreeSet::new();
    for file in [
        "benchmarks/dynamarq/five_qubit_code.qlin",
        "benchmarks/hand/mbqc_chain4.qlin",
        "benchmarks/dynamarq/repetition5_1_noisy.qlin",
        "benchmarks/qec/repetition7_1_noisy.qlin",
    ] {
        let prog = parse(&std::fs::read_to_string(file).unwrap()).unwrap();
        let exact = expected(
            &prog,
            &records(&prog, 1 << 16).unwrap(),
            &cost,
            &Noise::none(),
            &none,
        )
        .unwrap()
        .mean;
        let n = 3000;
        let recs = sampled_records(&prog, n, 11).unwrap();
        let total: f64 = recs.iter().map(|r| r.prob).sum();
        assert!((total - 1.0).abs() < 1e-9, "{file}: weights sum to {total}");
        let (mean, se) = mean_and_se(&prog, &recs, &cost, n);
        // Deterministic program timing gives se = 0: then the sample must
        // match exactly.
        assert!(
            (mean - exact).abs() <= 4.0 * se + 1e-6,
            "{file}: {mean} +- {se} vs {exact}"
        );
    }
}
