//! Export of translation-validation jobs for the Lean checker
//! (`lean/QlinCheck.lean`, `lean/Qlin/Check.lean`).
//!
//! A leaf becomes `[kind, qubits, writes, params]`: `kind` is a code
//! interned per export (equal codes iff equal gate names, or both measure,
//! or both reset), `params` are the exact bit patterns of the f64 angles.
//! Two leaves get equal JSON iff they are the same operation.

use std::collections::BTreeMap;

use serde_json::{json, Value};

use crate::ir::{BitExpr, Op, Program};

/// Interns leaf kinds to small codes.
#[derive(Default)]
pub struct Kinds(BTreeMap<String, usize>);

impl Kinds {
    fn code(&mut self, name: String) -> usize {
        let n = self.0.len();
        *self.0.entry(name).or_insert(n)
    }
}

fn expr(e: &BitExpr) -> Value {
    match e {
        BitExpr::Const(v) => json!({ "c": v }),
        BitExpr::Bit(b) => json!({ "v": b.0 }),
        BitExpr::Not(a) => json!({ "not": expr(a) }),
        BitExpr::And(a, b) => json!({ "and": [expr(a), expr(b)] }),
        BitExpr::Or(a, b) => json!({ "or": [expr(a), expr(b)] }),
        BitExpr::Xor(a, b) => json!({ "xor": [expr(a), expr(b)] }),
    }
}

/// A block in the checker's JSON form.
pub fn block(ops: &[Op], k: &mut Kinds) -> Value {
    Value::Array(ops.iter().map(|o| op(o, k)).collect())
}

fn op(o: &Op, k: &mut Kinds) -> Value {
    match o {
        Op::Gate {
            gate,
            qubits,
            params,
        } => {
            let code = k.code(format!("gate:{}", gate.name()));
            let qs: Vec<u32> = qubits.iter().map(|q| q.0).collect();
            let ps: Vec<u64> = params.iter().map(|p| p.to_bits()).collect();
            json!({ "leaf": [code, qs, [], ps] })
        }
        Op::Measure { q, b } => json!({ "leaf": [k.code("measure".into()), [q.0], [b.0], []] }),
        Op::Reset { q } => json!({ "leaf": [k.code("reset".into()), [q.0], [], []] }),
        Op::If { cond, then_, else_ } => {
            json!({ "ite": [expr(cond), block(then_, k), block(else_, k)] })
        }
        Op::Loop {
            body,
            until,
            max_iters,
        } => json!({ "loop": [max_iters, block(body, k), expr(until)] }),
        Op::Switch {
            bits,
            cases,
            default,
        } => {
            let g: Vec<u32> = bits.iter().map(|b| b.0).collect();
            let cs: Vec<Value> = cases
                .iter()
                .map(|(v, blk)| json!([v, block(blk, k)]))
                .collect();
            json!({ "switch": [g, cs, block(default, k)] })
        }
    }
}

/// One job: `kind` is "m0" (the M0 checker from the all-zero bits) or "fp"
/// (the fast-path checker).
pub fn job(name: &str, kind: &str, src: &Program, tgt: &Program, k: &mut Kinds) -> Value {
    json!({
        "name": name,
        "kind": kind,
        "bits": src.n_bits,
        "src": block(&src.body, k),
        "tgt": block(&tgt.body, k),
    })
}
