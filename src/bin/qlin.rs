//! qlin command-line interface.

use std::collections::{BTreeMap, BTreeSet};
use std::process::ExitCode;

use qlin::cost::CostModel;
use qlin::import::jeff::{import_jeff, ImportOptions};
use qlin::ir::{Program, Qubit};
use qlin::latency::{expected, Noise};
use qlin::search::{Problem, SearchError};
use qlin::sim::{basis_state, simulate};
use qlin::stats::stats_with_noise;
use qlin::text::{parse, print};
use qlin::transform::defer::{apply, Choice};
use qlin::transform::m0::normal_form;

const USAGE: &str = "\
usage:
  qlin import [--max-iters K] FILE.jeff   print the program as .qlin
  qlin stats [--json] [--noise-qubits I,J] FILE.qlin
                                          print program metrics, without
                                          the error-injection ops on noise qubits
  qlin sim FILE.qlin                      print the output distribution from |0...0> as JSON
  qlin fmt FILE.qlin                      print the program in canonical form
  qlin json FILE.qlin                     print the program tree as JSON
  qlin opt [--tff NS] [--noise-qubits I,J] [--check] [--json] FILE.qlin
                                          choose which Ifs to defer (cost model
                                          HERON_LIKE, t_ff overridable). Prints
                                          the best program, or a JSON report";

/// Branch limit for `qlin sim`.
const SIM_LIMIT: usize = 1 << 16;

fn load(path: &str) -> Result<Program, String> {
    let src = std::fs::read_to_string(path).map_err(|e| format!("{path}: {e}"))?;
    parse(&src).map_err(|e| format!("{path}: {e}"))
}

#[derive(Default)]
struct Flags {
    json: bool,
    check: bool,
    noise: BTreeSet<Qubit>,
    tff: Option<f64>,
}

/// Splits `FLAGS... FILE` and parses the flags.
fn flags(rest: &[String]) -> Result<(&String, Flags), String> {
    let (file, args) = rest.split_last().ok_or(USAGE)?;
    let mut f = Flags::default();
    let mut it = args.iter();
    for _ in 0..args.len() {
        match it.next().map(String::as_str) {
            Some("--json") => f.json = true,
            Some("--check") => f.check = true,
            Some("--noise-qubits") => {
                let list = it.next().ok_or(USAGE)?;
                for q in list.split(',').filter(|x| !x.is_empty()) {
                    let q = q.parse().map_err(|_| format!("bad qubit `{q}`"))?;
                    f.noise.insert(Qubit(q));
                }
            }
            Some("--tff") => {
                let v = it.next().ok_or(USAGE)?;
                f.tff = Some(v.parse().map_err(|_| format!("bad --tff `{v}`"))?);
            }
            Some(other) => return Err(format!("unknown flag `{other}`\n{USAGE}")),
            None => {}
        }
    }
    Ok((file, f))
}

/// Runs the defer search on the M0 normal form of `prog`.
fn opt(prog: &Program, f: &Flags) -> Result<String, String> {
    let mut cost = CostModel::HERON_LIKE;
    if let Some(t) = f.tff {
        cost.t_ff = t;
    }
    cost.validate().map_err(|e| e.to_string())?;
    let normal = normal_form(prog);
    let noise = Noise::new(&normal, &f.noise);
    let mut problem =
        Problem::new(&normal, cost, noise.clone(), SIM_LIMIT).map_err(|e| e.to_string())?;
    problem.check_leaves = f.check;
    let none = BTreeSet::new();
    let source = expected(
        prog,
        &problem.recs,
        &cost,
        &Noise::new(prog, &f.noise),
        &none,
    )
    .map_err(|e| e.to_string())?;
    let m0 = expected(&normal, &problem.recs, &cost, &noise, &none).map_err(|e| e.to_string())?;
    let floor = problem.floor().map_err(|e| e.to_string())?;
    let exhaustive = match problem.exhaustive() {
        Ok(ex) => serde_json::to_value(&ex).map_err(|e| e.to_string())?,
        Err(SearchError::TooManyCandidates(k)) => {
            serde_json::json!({ "skipped": format!("{k} candidates") })
        }
        Err(e) => return Err(e.to_string()),
    };
    let bnb = problem.branch_and_bound().map_err(|e| e.to_string())?;
    let choices: Vec<Choice> = bnb
        .best
        .defer
        .iter()
        .map(|&d| if d { Choice::Defer } else { Choice::Classical })
        .collect();
    let best = apply(&normal, &problem.cands, &choices).prog;
    if !f.json {
        return Ok(print(&best));
    }
    let report = serde_json::json!({
        "cost": cost,
        "candidates": problem.cands.len(),
        "records": problem.recs.len(),
        "source": source,
        "m0": m0,
        "floor": floor,
        "exhaustive": exhaustive,
        "bnb": bnb,
        "leaves_checked": problem.checked.get(),
        "leaves_unchecked": problem.unchecked.get(),
        "program": print(&best),
    });
    Ok(report.to_string())
}

fn run(args: &[String]) -> Result<String, String> {
    let (cmd, rest) = args.split_first().ok_or(USAGE)?;
    match cmd.as_str() {
        "import" => {
            let mut opts = ImportOptions::default();
            let file = match rest {
                [flag, k, file] if flag == "--max-iters" => {
                    opts.max_loop_iters =
                        k.parse().map_err(|_| format!("bad --max-iters `{k}`"))?;
                    file
                }
                [file] => file,
                _ => return Err(USAGE.into()),
            };
            let bytes = std::fs::read(file).map_err(|e| format!("{file}: {e}"))?;
            let prog = import_jeff(&bytes, opts).map_err(|e| format!("{file}: {e}"))?;
            Ok(print(&prog))
        }
        "stats" => {
            let (file, f) = flags(rest)?;
            let s = stats_with_noise(&load(file)?, &f.noise);
            if f.json {
                serde_json::to_string(&s).map_err(|e| e.to_string())
            } else {
                Ok(format!("{s:#?}"))
            }
        }
        "opt" => {
            let (file, f) = flags(rest)?;
            opt(&load(file)?, &f)
        }
        "sim" => {
            let [file] = rest else {
                return Err(USAGE.into());
            };
            let prog = load(file)?;
            let init = basis_state(prog.n_qubits.min(qlin::sim::MAX_QUBITS), 0);
            let branches = simulate(&prog, &init, SIM_LIMIT).map_err(|e| format!("{file}: {e}"))?;
            let mut dist: BTreeMap<String, f64> = BTreeMap::new();
            let mut truncated = 0.0;
            for b in &branches {
                if b.truncated {
                    truncated += b.prob;
                }
                let key: String = b.bits.iter().map(|&x| if x { '1' } else { '0' }).collect();
                *dist.entry(key).or_insert(0.0) += b.prob;
            }
            let out = serde_json::json!({ "dist": dist, "truncated_prob": truncated });
            Ok(out.to_string())
        }
        "fmt" | "json" => {
            let [file] = rest else {
                return Err(USAGE.into());
            };
            let prog = load(file)?;
            if cmd == "fmt" {
                Ok(print(&prog))
            } else {
                serde_json::to_string(&prog).map_err(|e| e.to_string())
            }
        }
        _ => Err(USAGE.into()),
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(out) => {
            println!("{}", out.trim_end());
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("{e}");
            ExitCode::FAILURE
        }
    }
}
