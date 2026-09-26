//! qlin command-line interface.

use std::collections::BTreeMap;
use std::process::ExitCode;

use qlin::import::jeff::{import_jeff, ImportOptions};
use qlin::ir::Program;
use qlin::sim::{basis_state, simulate};
use qlin::stats::stats_with_noise;
use qlin::text::{parse, print};

const USAGE: &str = "\
usage:
  qlin import [--max-iters K] FILE.jeff   print the program as .qlin
  qlin stats [--json] [--noise-qubits I,J] FILE.qlin
                                          print program metrics, without
                                          the error-injection ops on noise qubits
  qlin sim FILE.qlin                      print the output distribution from |0...0> as JSON
  qlin fmt FILE.qlin                      print the program in canonical form
  qlin json FILE.qlin                     print the program tree as JSON";

/// Branch limit for `qlin sim`.
const SIM_LIMIT: usize = 1 << 16;

fn load(path: &str) -> Result<Program, String> {
    let src = std::fs::read_to_string(path).map_err(|e| format!("{path}: {e}"))?;
    parse(&src).map_err(|e| format!("{path}: {e}"))
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
            let (file, flags) = rest.split_last().ok_or(USAGE)?;
            let (mut json, mut noise) = (false, std::collections::BTreeSet::new());
            let mut it = flags.iter();
            for _ in 0..flags.len() {
                match it.next().map(String::as_str) {
                    Some("--json") => json = true,
                    Some("--noise-qubits") => {
                        let list = it.next().ok_or(USAGE)?;
                        for q in list.split(',').filter(|x| !x.is_empty()) {
                            let q = q.parse().map_err(|_| format!("bad qubit `{q}`"))?;
                            noise.insert(qlin::ir::Qubit(q));
                        }
                    }
                    Some(other) => return Err(format!("unknown flag `{other}`\n{USAGE}")),
                    None => {}
                }
            }
            let s = stats_with_noise(&load(file)?, &noise);
            if json {
                serde_json::to_string(&s).map_err(|e| e.to_string())
            } else {
                Ok(format!("{s:#?}"))
            }
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
