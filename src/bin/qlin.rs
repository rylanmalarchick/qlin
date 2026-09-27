//! qlin command-line interface.

use std::collections::{BTreeMap, BTreeSet};
use std::process::ExitCode;

use qlin::check::{equivalent, inputs};
use qlin::cost::{CostModel, Sync};
use qlin::import::jeff::{import_jeff, ImportOptions};
use qlin::ir::{Program, Qubit};
use qlin::latency::{expected, records, Expected, Noise};
use qlin::search::{Problem, SearchError};
use qlin::sim::{basis_state, simulate};
use qlin::stats::stats_with_noise;
use qlin::text::{parse, print};
use qlin::transform::defer::{apply, Choice};
use qlin::transform::fastpath::fast_path;
use qlin::transform::m0::normal_form;
use qlin::transform::sink::sink;

const USAGE: &str = "\
usage:
  qlin import [--max-iters K] FILE.jeff   print the program as .qlin
  qlin stats [--json] [--noise-qubits I,J] FILE.qlin
                                          print program metrics, without
                                          the error-injection ops on noise qubits
  qlin sim FILE.qlin                      print the output distribution from |0...0> as JSON
  qlin fmt FILE.qlin                      print the program in canonical form
  qlin json FILE.qlin                     print the program tree as JSON
  qlin opt [MODEL] [--noise-qubits I,J] [--check] [--json] FILE.qlin
                                          choose which Ifs to defer. Prints
                                          the best program, or a JSON report
  qlin fastpath [--t T] [--size S] [--sink] [--check] [MODEL] [--noise-qubits I,J] [--json] FILE.qlin
                                          fast path over the outcome budget t
                                          (default 1), at most S cases (4096)
  qlin lat [MODEL] [--noise-qubits I,J] FILE.qlin
                                          expected latency as JSON
  qlin sweep [--preset P] [--tmeas-list A,B] [--tff-list A,B] [--tbranch-list A,B]
             [--noise-qubits I,J] FILE.qlin
                                          score fixed variants over a cost grid
MODEL: [--preset heron_like|heron_kingston] [--model ideal|block] [--tff NS] [--tbranch NS] [--tmeas NS]
       (default preset heron_like; see notes/cost-sources.txt)";

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
    sink: bool,
    noise: BTreeSet<Qubit>,
    tff: Option<f64>,
    tbranch: Option<f64>,
    block: bool,
    t: Option<usize>,
    size: Option<usize>,
    kingston: bool,
    tmeas: Option<f64>,
    /// Grid for `sweep`: t_meas, t_ff, t_branch values.
    grid: [Vec<f64>; 3],
}

impl Flags {
    fn cost(&self) -> Result<CostModel, String> {
        let mut c = if self.kingston {
            CostModel::HERON_KINGSTON
        } else {
            CostModel::HERON_LIKE
        };
        if let Some(t) = self.tff {
            c.t_ff = t;
        }
        if let Some(t) = self.tbranch {
            c.t_branch = t;
        }
        if let Some(t) = self.tmeas {
            c.t_meas = t;
        }
        if self.block {
            c.sync = Sync::Block;
        }
        c.validate().map_err(|e| e.to_string())?;
        Ok(c)
    }
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
            Some("--sink") => f.sink = true,
            Some("--preset") => {
                f.kingston = match it.next().map(String::as_str) {
                    Some("heron_kingston") => true,
                    Some("heron_like") => false,
                    other => return Err(format!("bad --preset `{other:?}`")),
                }
            }
            Some(flag @ ("--tmeas-list" | "--tff-list" | "--tbranch-list")) => {
                let v = it.next().ok_or(USAGE)?;
                let list: Vec<f64> = v
                    .split(',')
                    .map(|x| x.parse().map_err(|_| format!("bad {flag} `{v}`")))
                    .collect::<Result<_, _>>()?;
                let slot = match flag {
                    "--tmeas-list" => 0,
                    "--tff-list" => 1,
                    _ => 2,
                };
                f.grid[slot] = list;
            }
            Some(flag @ ("--tff" | "--tbranch" | "--tmeas" | "--t" | "--size" | "--model")) => {
                let v = it.next().ok_or(USAGE)?;
                let bad = || format!("bad {flag} `{v}`");
                match flag {
                    "--tmeas" => f.tmeas = Some(v.parse().map_err(|_| bad())?),
                    "--tff" => f.tff = Some(v.parse().map_err(|_| bad())?),
                    "--tbranch" => f.tbranch = Some(v.parse().map_err(|_| bad())?),
                    "--t" => f.t = Some(v.parse().map_err(|_| bad())?),
                    "--size" => f.size = Some(v.parse().map_err(|_| bad())?),
                    _ => {
                        f.block = match v.as_str() {
                            "block" => true,
                            "ideal" => false,
                            _ => return Err(bad()),
                        }
                    }
                }
            }
            Some(other) => return Err(format!("unknown flag `{other}`\n{USAGE}")),
            None => {}
        }
    }
    Ok((file, f))
}

/// Runs the defer search on the M0 normal form of `prog`.
fn opt(prog: &Program, f: &Flags) -> Result<String, String> {
    let cost = f.cost()?;
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

/// Scores fixed variants of `prog` at every point of the grid
/// (t_meas x t_ff x t_branch, each under the Ideal and Block models). The
/// variants: source, M0, best defer (searched at each point), and fast
/// path with and without sink for t = 0..min(m, 6).
fn sweep(prog: &Program, f: &Flags) -> Result<String, String> {
    let normal = normal_form(prog);
    let noise = Noise::new(&normal, &f.noise);
    let base = f.cost()?;
    let mut problem =
        Problem::new(&normal, base, noise.clone(), SIM_LIMIT).map_err(|e| e.to_string())?;
    let recs = problem.recs.clone();
    let sunk = sink(&normal, &noise).prog;
    let m = fast_path(&normal, &recs, &noise, 0, 4096).group_bits;
    let mut variants: Vec<(String, Program)> = vec![
        ("source".into(), prog.clone()),
        ("m0".into(), normal.clone()),
        ("sink_only".into(), sunk.clone()),
    ];
    for t in 0..=m.min(6) {
        variants.push((
            format!("fast_t{t}"),
            fast_path(&normal, &recs, &noise, t, 4096).prog,
        ));
        variants.push((
            format!("sink_fast_t{t}"),
            fast_path(&sunk, &recs, &noise, t, 4096).prog,
        ));
    }
    let pick = |grid: &Vec<f64>, default: f64| {
        if grid.is_empty() {
            vec![default]
        } else {
            grid.clone()
        }
    };
    let none = BTreeSet::new();
    let mut points = Vec::new();
    for tmeas in pick(&f.grid[0], base.t_meas) {
        for tff in pick(&f.grid[1], base.t_ff) {
            for tbranch in pick(&f.grid[2], base.t_branch) {
                for sync in [Sync::Ideal, Sync::Block] {
                    let cost = CostModel {
                        t_meas: tmeas,
                        t_ff: tff,
                        t_branch: tbranch,
                        sync,
                        ..base
                    };
                    cost.validate().map_err(|e| e.to_string())?;
                    let mut scores = serde_json::Map::new();
                    for (name, v) in &variants {
                        let e = expected(v, &recs, &cost, &Noise::new(v, &f.noise), &none)
                            .map_err(|e| e.to_string())?;
                        scores.insert(name.clone(), e.mean.into());
                    }
                    problem.cost = cost;
                    let bnb = problem.branch_and_bound().map_err(|e| e.to_string())?;
                    scores.insert("best_defer".into(), bnb.best.mean.into());
                    points.push(serde_json::json!({
                        "t_meas": tmeas, "t_ff": tff, "t_branch": tbranch,
                        "sync": cost.sync, "scores": scores,
                    }));
                }
            }
        }
    }
    let out =
        serde_json::json!({ "group_bits": m, "candidates": problem.cands.len(), "points": points });
    Ok(out.to_string())
}

/// Expected latency of `prog` on its own outcome records.
fn lat(prog: &Program, f: &Flags) -> Result<Expected, String> {
    let recs = records(prog, SIM_LIMIT).map_err(|e| e.to_string())?;
    expected(
        prog,
        &recs,
        &f.cost()?,
        &Noise::new(prog, &f.noise),
        &BTreeSet::new(),
    )
    .map_err(|e| e.to_string())
}

/// Normal form, optional sink, then the fast path.
fn fastpath(prog: &Program, f: &Flags) -> Result<String, String> {
    let cost = f.cost()?;
    let normal = normal_form(prog);
    let noise = Noise::new(&normal, &f.noise);
    let (base, moved) = if f.sink {
        let s = sink(&normal, &noise);
        (s.prog, s.moved)
    } else {
        (normal.clone(), 0)
    };
    let recs = records(&base, SIM_LIMIT).map_err(|e| e.to_string())?;
    let fp = fast_path(
        &base,
        &recs,
        &noise,
        f.t.unwrap_or(1),
        f.size.unwrap_or(4096),
    );
    let checked = if f.check && prog.n_qubits <= qlin::sim::MAX_QUBITS {
        equivalent(prog, &fp.prog, &inputs(prog.n_qubits, 8, 31), SIM_LIMIT)
            .map_err(|e| format!("fast path failed the equivalence check: {e}"))?;
        true
    } else {
        false
    };
    if !f.json {
        return Ok(print(&fp.prog));
    }
    let none = BTreeSet::new();
    let score = |p: &Program| {
        expected(p, &recs, &cost, &Noise::new(p, &f.noise), &none).map_err(|e| e.to_string())
    };
    let report = serde_json::json!({
        "cost": cost,
        "source": score(prog)?,
        "m0": score(&normal)?,
        "base": score(&base)?,
        "fast": score(&fp.prog)?,
        "sink_moved": moved,
        "checked": checked,
        "fastpath": fp,
        "program": print(&fp.prog),
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
        "fastpath" => {
            let (file, f) = flags(rest)?;
            fastpath(&load(file)?, &f)
        }
        "sweep" => {
            let (file, f) = flags(rest)?;
            sweep(&load(file)?, &f)
        }
        "lat" => {
            let (file, f) = flags(rest)?;
            serde_json::to_string(&lat(&load(file)?, &f)?).map_err(|e| e.to_string())
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
