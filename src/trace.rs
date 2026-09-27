//! Per-outcome trace enumerator.
//!
//! Every measurement splits the run into outcome 0 and outcome 1. A trace
//! is the straight-line leaf sequence that one outcome sequence runs. Loops
//! run up to `max_iters` iterations. A trace that reaches the bound without
//! its exit condition is marked `truncated`.

use std::fmt;

use crate::ir::{Bit, BitExpr, Block, Op, Program};

#[derive(Clone, Debug, PartialEq)]
pub struct Trace {
    /// Measurement outcomes in the order they happen.
    pub outcomes: Vec<(Bit, bool)>,
    /// Leaf ops (gate, measure, reset) in run order.
    pub ops: Vec<Op>,
    /// True when a loop hit `max_iters` before its exit condition held.
    pub truncated: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TraceError {
    TooManyTraces { limit: usize },
}

impl fmt::Display for TraceError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TraceError::TooManyTraces { limit } => {
                write!(f, "program has more than {limit} traces")
            }
        }
    }
}

impl std::error::Error for TraceError {}

#[derive(Clone)]
enum Cont<'a> {
    Ops(&'a [Op]),
    LoopTail {
        body: &'a Block,
        until: &'a BitExpr,
        max_iters: u32,
        done: u32,
    },
}

#[derive(Clone)]
struct Run<'a> {
    conts: Vec<Cont<'a>>,
    bits: Vec<bool>,
    trace: Trace,
}

/// Enumerates every trace of `prog`. Fails when there are more than
/// `limit` traces.
pub fn enumerate(prog: &Program, limit: usize) -> Result<Vec<Trace>, TraceError> {
    let mut work = vec![Run {
        conts: vec![Cont::Ops(&prog.body)],
        bits: vec![false; prog.n_bits as usize],
        trace: Trace {
            outcomes: Vec::new(),
            ops: Vec::new(),
            truncated: false,
        },
    }];
    let mut done = Vec::new();
    while let Some(mut run) = work.pop() {
        while let Some(cont) = run.conts.pop() {
            match cont {
                Cont::Ops([]) => {}
                Cont::Ops([op, rest @ ..]) => {
                    run.conts.push(Cont::Ops(rest));
                    step(op, &mut run, &mut work);
                }
                Cont::LoopTail {
                    body,
                    until,
                    max_iters,
                    done,
                } => {
                    let bits = &run.bits;
                    if until.eval(&|b: Bit| bits[b.0 as usize]) {
                        // The loop exits. The run continues after it.
                    } else if done < max_iters {
                        run.conts.push(Cont::LoopTail {
                            body,
                            until,
                            max_iters,
                            done: done + 1,
                        });
                        run.conts.push(Cont::Ops(body));
                    } else {
                        run.trace.truncated = true;
                        run.conts.clear();
                    }
                }
            }
            if work.len() + done.len() >= limit {
                return Err(TraceError::TooManyTraces { limit });
            }
        }
        done.push(run.trace);
    }
    done.sort_by(|a, b| a.outcomes.cmp(&b.outcomes));
    Ok(done)
}

fn step<'a>(op: &'a Op, run: &mut Run<'a>, work: &mut Vec<Run<'a>>) {
    match op {
        Op::Gate { .. } | Op::Reset { .. } => run.trace.ops.push(op.clone()),
        Op::Measure { b, .. } => {
            run.trace.ops.push(op.clone());
            let mut one = run.clone();
            one.bits[b.0 as usize] = true;
            one.trace.outcomes.push((*b, true));
            work.push(one);
            run.bits[b.0 as usize] = false;
            run.trace.outcomes.push((*b, false));
        }
        Op::If { cond, then_, else_ } => {
            let bits = &run.bits;
            let arm = if cond.eval(&|b: Bit| bits[b.0 as usize]) {
                then_
            } else {
                else_
            };
            run.conts.push(Cont::Ops(arm));
        }
        Op::Switch {
            bits,
            cases,
            default,
        } => {
            let vals = &run.bits;
            let (_, arm) = Op::switch_arm(bits, cases, default, &|b: Bit| vals[b.0 as usize]);
            run.conts.push(Cont::Ops(arm));
        }
        Op::Loop {
            body,
            until,
            max_iters,
        } => {
            run.conts.push(Cont::LoopTail {
                body,
                until,
                max_iters: *max_iters,
                done: 1,
            });
            run.conts.push(Cont::Ops(body));
        }
    }
}
