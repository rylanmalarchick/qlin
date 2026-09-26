//! jeff importer: golden files, expected failures, and semantics.

use std::path::Path;

use qlin::analysis::core::{core, CoreKind};
use qlin::import::jeff::{import_jeff, ImportError, ImportOptions};
use qlin::ir::Program;
use qlin::sim::{basis_state, simulate};
use qlin::stats::stats;
use qlin::text::print;

const SRC: &str = "benchmarks/jeff/src";

fn import(name: &str) -> Result<Program, ImportError> {
    let bytes = std::fs::read(Path::new(SRC).join(format!("{name}.jeff"))).unwrap();
    import_jeff(&bytes, ImportOptions::default())
}

/// Files that must fail, with a substring of the reason.
const EXPECTED_FAILURES: &[(&str, &str)] = &[
    ("controlled-multiplication-modulo-n_3", "R1 with 2 controls"),
    ("controlled-multiplication-modulo-n_5", "R1 with 2 controls"),
    ("controlled-multiplication-modulo-n_7", "R1 with 2 controls"),
    ("grover_5", "Z with 3 controls"),
    ("grover_7", "Z with 5 controls"),
    ("multiplexer_3", "Ry with 1 controls"),
    ("multiplexer_5", "Ry with 1 controls"),
    ("multiplexer_7", "Ry with 1 controls"),
];

#[test]
fn every_file_imports_to_its_golden_qlin_or_fails_as_expected() {
    let mut names: Vec<String> = std::fs::read_dir(SRC)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|x| x == "jeff"))
        .map(|p| p.file_stem().unwrap().to_string_lossy().into_owned())
        .collect();
    names.sort();
    assert_eq!(names.len(), 37);
    let mut ok = 0;
    for name in &names {
        let golden = Path::new("benchmarks/jeff").join(format!("{name}.qlin"));
        match (
            import(name),
            EXPECTED_FAILURES.iter().find(|(n, _)| n == name),
        ) {
            (Ok(p), None) => {
                assert_eq!(
                    print(&p),
                    std::fs::read_to_string(&golden).unwrap(),
                    "{name}"
                );
                ok += 1;
            }
            (Err(e), Some((_, why))) => {
                assert!(e.to_string().contains(why), "{name}: {e}");
                assert!(!golden.exists(), "{name} has a golden file but must fail");
            }
            (Ok(_), Some(_)) => panic!("{name} imports but is listed as a failure"),
            (Err(e), None) => panic!("{name}: {e}"),
        }
    }
    assert_eq!(ok, 29);
}

#[test]
fn teleportation_core_and_output() {
    let p = import("teleportation").unwrap();
    let r = core(&p);
    // Ops: h h cx cx h measure measure if if h measure.
    assert_eq!(
        r.core,
        vec![
            (vec![7, 0, 0], CoreKind::Branch),
            (vec![8, 0, 0], CoreKind::Branch)
        ]
    );
    assert_eq!(r.feedforward, 2);
    // The input is H|0> = |+>. After teleportation and H on q2, c2 is 0.
    let branches = simulate(&p, &basis_state(3, 0), 1 << 10).unwrap();
    let p_c2_one: f64 = branches.iter().filter(|b| b.bits[2]).map(|b| b.prob).sum();
    assert!(p_c2_one < 1e-12, "P(c2 = 1) = {p_c2_one}");
}

#[test]
fn iterative_programs_have_one_feedforward_per_correction() {
    // iQFT and iQPE on n bits: bit k is corrected by the k earlier bits,
    // so there are n(n-1)/2 conditional phases.
    for (name, n) in [("iqft_3", 3), ("iqft_5", 5), ("iqft_7", 7), ("iqpe_5", 5)] {
        let s = stats(&import(name).unwrap());
        assert_eq!(s.measurements, n, "{name}");
        assert_eq!(s.feedforward, n * (n - 1) / 2, "{name}");
        assert_eq!(s.core_branch, n * (n - 1) / 2, "{name}");
        assert_eq!(s.movable, 0, "{name}");
    }
}

#[test]
fn repeat_until_success_becomes_a_measured_loop() {
    let p = import("repeat-until-success_3").unwrap();
    let s = stats(&p);
    // Loop exit plus the reset flip inside the loop.
    assert_eq!(s.feedforward, 2);
    // 10 loop-body leaves repeat. The `x` inside `if c0` is also a branch core op.
    assert_eq!(s.core_loop, 10);
    assert_eq!(s.core_branch, 1);
    let opts = ImportOptions { max_loop_iters: 3 };
    let bytes = std::fs::read(Path::new(SRC).join("repeat-until-success_3.jeff")).unwrap();
    let p3 = import_jeff(&bytes, opts).unwrap();
    assert!(print(&p3).contains("loop max 3 {"));
}
