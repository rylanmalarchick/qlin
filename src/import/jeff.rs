//! Import of jeff programs by partial evaluation.
//!
//! The importer runs the classical part of the program at import time:
//! integer and float ops fold, `For` loops with constant bounds unroll,
//! and a `Switch` with a constant selector inlines one branch. What is left
//! depends on a measured bit: a `Switch` on a measured bit becomes an `If`,
//! and a `While` whose condition is a measured bit becomes a `Loop`.
//! Anything else returns [`ImportError::Unsupported`].

use std::collections::HashMap;
use std::fmt;

use jeff::reader::optype::{
    ControlFlowOp, FloatArrayOp, FloatOp, GateOpType, IntArrayOp, IntOp, OpType, QubitOp,
    QubitRegisterOp, WellKnownGate,
};
use jeff::reader::{Function, Module, Operation, ReadJeff, Region};
use jeff::types::Type;

use crate::ir::{Bit, BitExpr, Block, Gate, Op, Program, Qubit, ValidateError};

/// Upper bound on unrolled loop iterations in one import.
const MAX_UNROLL: usize = 1 << 16;
/// Upper bound on nested function calls.
const MAX_CALL_DEPTH: usize = 64;

#[derive(Clone, Copy, Debug)]
pub struct ImportOptions {
    /// `max_iters` for each measured-exit loop.
    pub max_loop_iters: u32,
}

impl Default for ImportOptions {
    fn default() -> Self {
        ImportOptions { max_loop_iters: 8 }
    }
}

#[derive(Debug)]
pub enum ImportError {
    Read(String),
    Unsupported { op: String, reason: String },
    Invalid(ValidateError),
}

impl fmt::Display for ImportError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ImportError::Read(e) => write!(f, "cannot read jeff file: {e}"),
            ImportError::Unsupported { op, reason } => write!(f, "unsupported {op}: {reason}"),
            ImportError::Invalid(e) => write!(f, "imported program is invalid: {e}"),
        }
    }
}

impl std::error::Error for ImportError {}

fn unsupported(op: impl Into<String>, reason: impl Into<String>) -> ImportError {
    ImportError::Unsupported {
        op: op.into(),
        reason: reason.into(),
    }
}

fn read_err(e: impl fmt::Display) -> ImportError {
    ImportError::Read(e.to_string())
}

/// A value during partial evaluation.
#[derive(Clone, Debug, PartialEq)]
enum Val {
    /// An integer of width > 1, stored as its low `bits` bits.
    Int {
        v: u64,
        bits: u8,
    },
    /// A 1-bit integer: a constant or an expression over measured bits.
    Bool(BitExpr),
    Float(f64),
    Qubit(u32),
    QReg(Vec<Option<u32>>),
    IntArr {
        bits: u8,
        items: Vec<Val>,
    },
    FloatArr(Vec<f64>),
}

fn mask(bits: u8) -> u64 {
    if bits >= 64 {
        u64::MAX
    } else {
        (1u64 << bits) - 1
    }
}

fn sext(v: u64, bits: u8) -> i64 {
    if bits >= 64 {
        v as i64
    } else {
        let shift = 64 - bits as u32;
        ((v << shift) as i64) >> shift
    }
}

fn int_val(v: u64, bits: u8) -> Val {
    if bits == 1 {
        Val::Bool(BitExpr::Const(v & 1 == 1))
    } else {
        Val::Int {
            v: v & mask(bits),
            bits,
        }
    }
}

type Env = HashMap<u32, Val>;

struct Importer<'a> {
    module: Module<'a>,
    opts: ImportOptions,
    n_qubits: u32,
    n_bits: u32,
    unrolled: usize,
    depth: usize,
}

/// Imports a jeff file from its bytes.
pub fn import_jeff(bytes: &[u8], opts: ImportOptions) -> Result<Program, ImportError> {
    let mut slice = bytes;
    let file = jeff::Jeff::read_slice(&mut slice).map_err(read_err)?;
    let module = file.module();
    let mut imp = Importer {
        module,
        opts,
        n_qubits: 0,
        n_bits: 0,
        unrolled: 0,
        depth: 0,
    };
    let entry = match module.entrypoint() {
        Function::Definition(f) => f,
        Function::Declaration(_) => return Err(unsupported("entry point", "it is a declaration")),
    };
    if entry.body().source_count() != 0 {
        return Err(unsupported("entry point", "it takes inputs"));
    }
    let mut body = Block::new();
    let mut env = Env::new();
    imp.region(&entry.body(), &mut env, Vec::new(), &mut body)?;
    let prog = Program {
        n_qubits: imp.n_qubits,
        n_bits: imp.n_bits,
        body,
    };
    prog.validate().map_err(ImportError::Invalid)?;
    Ok(prog)
}

impl<'a> Importer<'a> {
    fn region<'r>(
        &mut self,
        r: &Region<'r>,
        env: &mut Env,
        sources: Vec<Val>,
        out: &mut Block,
    ) -> Result<Vec<Val>, ImportError> {
        if r.source_count() != sources.len() {
            return Err(unsupported(
                "region",
                format!("{} sources, {} values", r.source_count(), sources.len()),
            ));
        }
        for (w, v) in r.sources().zip(sources) {
            env.insert(w.map_err(read_err)?.id(), v);
        }
        for op in r.operations() {
            self.operation(&op, env, out)?;
        }
        r.targets()
            .map(|w| {
                let id = w.map_err(read_err)?.id();
                env.get(&id)
                    .cloned()
                    .ok_or_else(|| unsupported("region", format!("target %{id} is undefined")))
            })
            .collect()
    }

    fn operation<'r>(
        &mut self,
        op: &Operation<'r>,
        env: &mut Env,
        out: &mut Block,
    ) -> Result<(), ImportError> {
        let mut ins = Vec::with_capacity(op.input_count());
        for w in op.inputs() {
            let id = w.map_err(read_err)?.id();
            let v = env
                .get(&id)
                .cloned()
                .ok_or_else(|| unsupported("operation", format!("input %{id} is undefined")))?;
            ins.push(v);
        }
        let mut out_ids = Vec::with_capacity(op.output_count());
        let mut out_tys = Vec::with_capacity(op.output_count());
        for w in op.outputs() {
            let w = w.map_err(read_err)?;
            out_ids.push(w.id());
            out_tys.push(w.ty());
        }
        let outs = match op.op_type() {
            OpType::QubitOp(q) => self.qubit_op(q, &ins, out)?,
            OpType::QubitRegisterOp(q) => self.qureg_op(q, ins)?,
            OpType::IntOp(i) => vec![int_op(i, &ins, &out_tys)?],
            OpType::IntArrayOp(a) => int_array_op(a, ins, &out_tys)?,
            OpType::FloatOp(f) => vec![float_op(f, &ins)?],
            OpType::FloatArrayOp(a) => float_array_op(a, ins)?,
            OpType::ControlFlowOp(cf) => self.control_flow(&cf, ins, env, out)?,
            OpType::FuncOp(f) => self.call(u32::from(f.func_idx), ins, out)?,
            other => return Err(unsupported(format!("{other:?}"), "unknown op kind")),
        };
        if outs.len() != out_ids.len() {
            return Err(unsupported(
                "operation",
                format!("{} outputs, {} values", out_ids.len(), outs.len()),
            ));
        }
        for (id, v) in out_ids.into_iter().zip(outs) {
            env.insert(id, v);
        }
        Ok(())
    }

    fn fresh_qubit(&mut self) -> u32 {
        self.n_qubits += 1;
        self.n_qubits - 1
    }

    fn fresh_bit(&mut self) -> Bit {
        self.n_bits += 1;
        Bit(self.n_bits - 1)
    }

    fn qubit_op<'r>(
        &mut self,
        q: QubitOp<'r>,
        ins: &[Val],
        out: &mut Block,
    ) -> Result<Vec<Val>, ImportError> {
        let qubit = |i: usize| match ins.get(i) {
            Some(Val::Qubit(q)) => Ok(*q),
            other => Err(unsupported(
                "qubit op",
                format!("input {i} is {other:?}, not a qubit"),
            )),
        };
        Ok(match q {
            QubitOp::Alloc => vec![Val::Qubit(self.fresh_qubit())],
            QubitOp::Free | QubitOp::FreeZero => vec![],
            QubitOp::Measure | QubitOp::MeasureNd => {
                let q0 = qubit(0)?;
                let b = self.fresh_bit();
                out.push(Op::Measure { q: Qubit(q0), b });
                let bit = Val::Bool(BitExpr::Bit(b));
                if matches!(q, QubitOp::Measure) {
                    vec![bit]
                } else {
                    vec![Val::Qubit(q0), bit]
                }
            }
            QubitOp::Reset => {
                let q0 = qubit(0)?;
                out.push(Op::Reset { q: Qubit(q0) });
                vec![Val::Qubit(q0)]
            }
            QubitOp::Gate(g) => {
                let g = g.normalize();
                let n_ctrl = g.control_qubits as usize;
                let (base, n_tgt, n_par) = match g.gate_type {
                    GateOpType::WellKnown(w) => {
                        let (t, p) = match w {
                            WellKnownGate::GPhase => (0, 1),
                            WellKnownGate::R1
                            | WellKnownGate::Rx
                            | WellKnownGate::Ry
                            | WellKnownGate::Rz => (1, 1),
                            WellKnownGate::U => (1, 3),
                            WellKnownGate::Swap => (2, 0),
                            _ => (1, 0),
                        };
                        (Ok(w), t, p)
                    }
                    GateOpType::Custom {
                        name,
                        num_qubits,
                        num_params,
                    } => (
                        Err(name.to_string()),
                        num_qubits as usize,
                        num_params as usize,
                    ),
                    GateOpType::PauliProdRotation { .. } => {
                        return Err(unsupported("gate", "Pauli-product rotation"))
                    }
                };
                let want = n_tgt + n_ctrl + n_par;
                if ins.len() != want {
                    return Err(unsupported(
                        "gate",
                        format!("{} inputs, expected {want}", ins.len()),
                    ));
                }
                let targets: Vec<u32> = (0..n_tgt).map(qubit).collect::<Result<_, _>>()?;
                let controls: Vec<u32> = (n_tgt..n_tgt + n_ctrl)
                    .map(qubit)
                    .collect::<Result<_, _>>()?;
                let params: Vec<f64> = ins[n_tgt + n_ctrl..]
                    .iter()
                    .map(|v| match v {
                        Val::Float(f) => Ok(*f),
                        other => Err(unsupported(
                            "gate",
                            format!("parameter {other:?} is not a constant float"),
                        )),
                    })
                    .collect::<Result<_, _>>()?;
                let emitted = lower_gate(base, g.adjoint, &targets, &controls, &params)?;
                for _ in 0..g.power {
                    out.extend(emitted.iter().cloned());
                }
                targets
                    .iter()
                    .chain(&controls)
                    .map(|&q| Val::Qubit(q))
                    .collect()
            }
            other => return Err(unsupported(format!("{other:?}"), "unknown qubit op")),
        })
    }

    fn qureg_op(&mut self, q: QubitRegisterOp, ins: Vec<Val>) -> Result<Vec<Val>, ImportError> {
        let name = format!("{q:?}");
        let reg = |i: usize| match ins.get(i) {
            Some(Val::QReg(r)) => Ok(r.clone()),
            other => Err(unsupported(
                &name,
                format!("input {i} is {other:?}, not a register"),
            )),
        };
        let index = |i: usize| match ins.get(i) {
            Some(Val::Int { v, .. }) => Ok(*v as usize),
            other => Err(unsupported(
                &name,
                format!("index {other:?} is not a constant"),
            )),
        };
        let take = |r: &mut Vec<Option<u32>>, i: usize| {
            r.get_mut(i)
                .and_then(Option::take)
                .ok_or_else(|| unsupported(&name, format!("slot {i} is empty or out of range")))
        };
        Ok(match q {
            QubitRegisterOp::Alloc => {
                let n = index(0)?;
                vec![Val::QReg(
                    (0..n).map(|_| Some(self.fresh_qubit())).collect(),
                )]
            }
            QubitRegisterOp::Free | QubitRegisterOp::FreeZero => vec![],
            QubitRegisterOp::ExtractIndex => {
                let mut r = reg(0)?;
                let q = take(&mut r, index(1)?)?;
                vec![Val::QReg(r), Val::Qubit(q)]
            }
            QubitRegisterOp::InsertIndex => {
                let mut r = reg(0)?;
                let i = index(1)?;
                let Some(Val::Qubit(q)) = ins.get(2) else {
                    return Err(unsupported(&name, "inserted value is not a qubit"));
                };
                match r.get_mut(i) {
                    Some(slot @ None) => *slot = Some(*q),
                    _ => {
                        return Err(unsupported(
                            &name,
                            format!("slot {i} is full or out of range"),
                        ))
                    }
                }
                vec![Val::QReg(r)]
            }
            QubitRegisterOp::ExtractSlice => {
                let mut r = reg(0)?;
                let (lo, hi) = (index(1)?, index(2)?);
                let mut s = Vec::new();
                for i in lo..hi {
                    s.push(Some(take(&mut r, i)?));
                }
                vec![Val::QReg(r), Val::QReg(s)]
            }
            QubitRegisterOp::InsertSlice => {
                let mut r = reg(0)?;
                let lo = index(1)?;
                let s = reg(2)?;
                for (k, q) in s.into_iter().enumerate() {
                    match r.get_mut(lo + k) {
                        Some(slot @ None) => *slot = q,
                        _ => return Err(unsupported(&name, "slice slot is full or out of range")),
                    }
                }
                vec![Val::QReg(r)]
            }
            QubitRegisterOp::Length => {
                let r = reg(0)?;
                vec![int_val(r.len() as u64, 32)]
            }
            QubitRegisterOp::Split => {
                let mut r = reg(0)?;
                let i = index(1)?;
                if i > r.len() {
                    return Err(unsupported(&name, "split index out of range"));
                }
                let tail = r.split_off(i);
                vec![Val::QReg(r), Val::QReg(tail)]
            }
            QubitRegisterOp::Join => {
                let mut r = reg(0)?;
                r.extend(reg(1)?);
                vec![Val::QReg(r)]
            }
            QubitRegisterOp::Create => {
                let qs = ins
                    .iter()
                    .map(|v| match v {
                        Val::Qubit(q) => Ok(Some(*q)),
                        other => Err(unsupported(&name, format!("{other:?} is not a qubit"))),
                    })
                    .collect::<Result<_, _>>()?;
                vec![Val::QReg(qs)]
            }
            other => return Err(unsupported(format!("{other:?}"), "unknown register op")),
        })
    }

    fn control_flow<'r>(
        &mut self,
        cf: &ControlFlowOp<'r>,
        ins: Vec<Val>,
        env: &mut Env,
        out: &mut Block,
    ) -> Result<Vec<Val>, ImportError> {
        match cf {
            ControlFlowOp::Switch(s) => {
                let (sel, state) = ins
                    .split_first()
                    .ok_or_else(|| unsupported("switch", "no selector"))?;
                let pick = |v: usize| {
                    s.try_branch(v)
                        .or_else(|| s.default_branch())
                        .ok_or_else(|| unsupported("switch", format!("no branch for {v}")))
                };
                match sel {
                    Val::Int { v, .. } => {
                        let r = pick(*v as usize)?;
                        self.region(&r, env, state.to_vec(), out)
                    }
                    Val::Bool(BitExpr::Const(c)) => {
                        let r = pick(*c as usize)?;
                        self.region(&r, env, state.to_vec(), out)
                    }
                    Val::Bool(cond) => {
                        let (r1, r0) = (pick(1)?, pick(0)?);
                        let mut then_ = Block::new();
                        let mut else_ = Block::new();
                        let t = self.region(&r1, &mut env.clone(), state.to_vec(), &mut then_)?;
                        let e = self.region(&r0, &mut env.clone(), state.to_vec(), &mut else_)?;
                        if t != e {
                            return Err(unsupported(
                                "switch",
                                "the two arms return different values (only qubits and constants \
                                 equal in both arms are supported)",
                            ));
                        }
                        out.push(Op::If {
                            cond: cond.clone(),
                            then_,
                            else_,
                        });
                        Ok(t)
                    }
                    other => Err(unsupported("switch", format!("selector {other:?}"))),
                }
            }
            ControlFlowOp::For { region } => {
                let int = |i: usize| match ins.get(i) {
                    Some(Val::Int { v, bits }) => Ok((sext(*v, *bits), *bits)),
                    other => Err(unsupported(
                        "for",
                        format!("bound {other:?} is not a constant"),
                    )),
                };
                let ((start, bits), (stop, _), (step, _)) = (int(0)?, int(1)?, int(2)?);
                if step == 0 {
                    return Err(unsupported("for", "step is 0"));
                }
                let span = if step > 0 { stop - start } else { start - stop };
                let n = if span <= 0 {
                    0
                } else {
                    (span as u64).div_ceil(step.unsigned_abs()) as usize
                };
                self.unrolled += n;
                if self.unrolled > MAX_UNROLL {
                    return Err(unsupported("for", "too many unrolled iterations"));
                }
                let mut state = ins[3..].to_vec();
                for k in 0..n {
                    let iv = start + (k as i64) * step;
                    let mut src = vec![int_val(iv as u64, bits)];
                    src.extend(state);
                    state = self.region(region, env, src, out)?;
                }
                Ok(state)
            }
            ControlFlowOp::While { before, after } => {
                let mut state = ins;
                let mut first = Block::new();
                let head = self.region(before, env, state.clone(), &mut first)?;
                let (cond, carried) = head
                    .split_first()
                    .ok_or_else(|| unsupported("while", "before region has no condition"))?;
                let Val::Bool(cond) = cond.clone() else {
                    return Err(unsupported("while", "condition is not a 1-bit value"));
                };
                if let BitExpr::Const(c) = cond {
                    // A classical loop: run it to the end at import time.
                    out.extend(first);
                    let mut carried = carried.to_vec();
                    let mut go = c;
                    for _ in 0..MAX_UNROLL {
                        if !go {
                            return Ok(carried);
                        }
                        self.unrolled += 1;
                        if self.unrolled > MAX_UNROLL {
                            break;
                        }
                        state = self.region(after, env, carried, out)?;
                        let head = self.region(before, env, state, out)?;
                        let Some((Val::Bool(BitExpr::Const(c)), rest)) = head.split_first() else {
                            return Err(unsupported(
                                "while",
                                "condition turns dynamic after a classical iteration",
                            ));
                        };
                        go = *c;
                        carried = rest.to_vec();
                    }
                    return Err(unsupported("while", "too many classical iterations"));
                }
                let mut again = Block::new();
                let next = self.region(after, env, carried.to_vec(), &mut again)?;
                if next != state {
                    return Err(unsupported(
                        "while",
                        "loop-carried values change across iterations",
                    ));
                }
                first.push(Op::If {
                    cond: cond.clone(),
                    then_: again,
                    else_: Block::new(),
                });
                out.push(Op::Loop {
                    body: first,
                    until: cond.not(),
                    max_iters: self.opts.max_loop_iters,
                });
                Ok(carried.to_vec())
            }
        }
    }

    fn call(&mut self, idx: u32, ins: Vec<Val>, out: &mut Block) -> Result<Vec<Val>, ImportError> {
        if self.depth >= MAX_CALL_DEPTH {
            return Err(unsupported("call", "call depth limit reached"));
        }
        let f = self
            .module
            .try_function(idx)
            .ok_or_else(|| unsupported("call", format!("no function {idx}")))?;
        let Function::Definition(def) = f else {
            return Err(unsupported("call", "callee is a declaration"));
        };
        self.depth += 1;
        let mut env = Env::new();
        let r = self.region(&def.body(), &mut env, ins, out);
        self.depth -= 1;
        r
    }
}

/// Maps a jeff gate to qlin ops. `base` is `Err(name)` for a custom gate.
fn lower_gate(
    base: Result<WellKnownGate, String>,
    adjoint: bool,
    targets: &[u32],
    controls: &[u32],
    params: &[f64],
) -> Result<Vec<Op>, ImportError> {
    let qs = |t: &[u32]| -> Vec<Qubit> { controls.iter().chain(t).map(|&q| Qubit(q)).collect() };
    let gate = |g: Gate, p: Vec<f64>| Op::Gate {
        gate: g,
        qubits: qs(targets),
        params: p,
    };
    let w = match base {
        Err(name) => {
            if !controls.is_empty() || adjoint {
                return Err(unsupported(
                    "gate",
                    format!("controlled or adjoint custom gate `{name}`"),
                ));
            }
            let g = Gate::Custom {
                name,
                arity: targets.len(),
                n_params: params.len(),
            };
            return Ok(vec![gate(g, params.to_vec())]);
        }
        Ok(w) => w,
    };
    let sign = if adjoint { -1.0 } else { 1.0 };
    let theta = || params[0] * sign;
    use WellKnownGate as W;
    let one = match (w, controls.len()) {
        (W::I, _) => return Ok(vec![]),
        (W::GPhase, 0) => return Ok(vec![]),
        (W::GPhase, 1) => {
            return Ok(vec![Op::Gate {
                gate: Gate::P,
                qubits: vec![Qubit(controls[0])],
                params: vec![theta()],
            }])
        }
        (W::X, 0) => gate(Gate::X, vec![]),
        (W::Y, 0) => gate(Gate::Y, vec![]),
        (W::Z, 0) => gate(Gate::Z, vec![]),
        (W::H, 0) => gate(Gate::H, vec![]),
        (W::S, 0) => gate(if adjoint { Gate::Sdg } else { Gate::S }, vec![]),
        (W::T, 0) => gate(if adjoint { Gate::Tdg } else { Gate::T }, vec![]),
        (W::R1, 0) => gate(Gate::P, vec![theta()]),
        (W::Rx, 0) => gate(Gate::Rx, vec![theta()]),
        (W::Ry, 0) => gate(Gate::Ry, vec![theta()]),
        (W::Rz, 0) => gate(Gate::Rz, vec![theta()]),
        (W::U, 0) => {
            let (t, p, l) = (params[0], params[1], params[2]);
            let ps = if adjoint {
                vec![-t, -l, -p]
            } else {
                vec![t, p, l]
            };
            gate(Gate::U, ps)
        }
        (W::Swap, 0) => gate(Gate::Swap, vec![]),
        (W::X, 1) => gate(Gate::Cx, vec![]),
        (W::Y, 1) => gate(Gate::Cy, vec![]),
        (W::Z, 1) => gate(Gate::Cz, vec![]),
        (W::H, 1) => gate(Gate::Ch, vec![]),
        (W::R1, 1) => gate(Gate::Cp, vec![theta()]),
        (W::Rz, 1) => gate(Gate::Crz, vec![theta()]),
        (W::X, 2) => gate(Gate::Ccx, vec![]),
        (w, n) => return Err(unsupported("gate", format!("{w:?} with {n} controls"))),
    };
    Ok(vec![one])
}

fn out_bits(out_tys: &[Type]) -> Result<u8, ImportError> {
    match out_tys.first() {
        Some(Type::Int { bits }) => Ok(*bits),
        other => Err(unsupported("int op", format!("output type {other:?}"))),
    }
}

fn int_op(op: IntOp, ins: &[Val], out_tys: &[Type]) -> Result<Val, ImportError> {
    let name = format!("{op:?}");
    match op {
        IntOp::Const1(b) => return Ok(Val::Bool(BitExpr::Const(b))),
        IntOp::Const8(v) => return Ok(int_val(v as u64, 8)),
        IntOp::Const16(v) => return Ok(int_val(v as u64, 16)),
        IntOp::Const32(v) => return Ok(int_val(v as u64, 32)),
        IntOp::Const64(v) => return Ok(int_val(v, 64)),
        _ => {}
    }
    // 1-bit logic on measured bits builds a bit expression.
    let is_bool = ins.iter().all(|v| matches!(v, Val::Bool(_))) && !ins.is_empty();
    if is_bool
        && !ins
            .iter()
            .all(|v| matches!(v, Val::Bool(BitExpr::Const(_))))
    {
        let b = |i: usize| match &ins[i] {
            Val::Bool(e) => e.clone(),
            _ => unreachable!("checked above"),
        };
        return match op {
            IntOp::Not => Ok(Val::Bool(b(0).not())),
            IntOp::And => Ok(Val::Bool(b(0).and(b(1)))),
            IntOp::Or => Ok(Val::Bool(b(0).or(b(1)))),
            IntOp::Xor => Ok(Val::Bool(b(0).xor(b(1)))),
            IntOp::Eq => Ok(Val::Bool(b(0).xor(b(1)).not())),
            _ => Err(unsupported(name, "this op on a measured bit")),
        };
    }
    let arg = |i: usize| match ins.get(i) {
        Some(Val::Int { v, bits }) => Ok((*v, *bits)),
        Some(Val::Bool(BitExpr::Const(c))) => Ok((*c as u64, 1)),
        other => Err(unsupported(&name, format!("input {i} is {other:?}"))),
    };
    let (a, w) = arg(0)?;
    let sa = sext(a, w);
    let bin = |f: fn(u64, u64) -> u64| -> Result<Val, ImportError> {
        let (b, _) = arg(1)?;
        Ok(int_val(f(a, b), w))
    };
    let cmp = |f: fn(i64, i64) -> bool| -> Result<Val, ImportError> {
        let (b, wb) = arg(1)?;
        Ok(Val::Bool(BitExpr::Const(f(sa, sext(b, wb)))))
    };
    let ucmp = |f: fn(u64, u64) -> bool| -> Result<Val, ImportError> {
        let (b, _) = arg(1)?;
        Ok(Val::Bool(BitExpr::Const(f(a, b))))
    };
    let nonzero = |b: u64| {
        if b == 0 {
            Err(unsupported(&name, "division by zero"))
        } else {
            Ok(b)
        }
    };
    match op {
        IntOp::Add => bin(u64::wrapping_add),
        IntOp::Sub => bin(u64::wrapping_sub),
        IntOp::Mul => bin(u64::wrapping_mul),
        IntOp::And => bin(|a, b| a & b),
        IntOp::Or => bin(|a, b| a | b),
        IntOp::Xor => bin(|a, b| a ^ b),
        IntOp::Not => Ok(int_val(!a, w)),
        IntOp::DivU => {
            let b = nonzero(arg(1)?.0)?;
            Ok(int_val(a / b, w))
        }
        IntOp::RemU => {
            let b = nonzero(arg(1)?.0)?;
            Ok(int_val(a % b, w))
        }
        IntOp::DivS => {
            let (b, wb) = arg(1)?;
            let b = sext(nonzero(b)?, wb);
            Ok(int_val(sa.wrapping_div(b) as u64, w))
        }
        IntOp::RemS => {
            let (b, wb) = arg(1)?;
            let b = sext(nonzero(b)?, wb);
            Ok(int_val(sa.wrapping_rem(b) as u64, w))
        }
        IntOp::Pow => bin(|a, b| a.wrapping_pow(b.min(u32::MAX as u64) as u32)),
        IntOp::Shl => bin(|a, b| if b >= 64 { 0 } else { a << b }),
        IntOp::Shr => bin(|a, b| if b >= 64 { 0 } else { a >> b }),
        IntOp::MinU => bin(u64::min),
        IntOp::MaxU => bin(u64::max),
        IntOp::MinS => {
            let (b, wb) = arg(1)?;
            Ok(int_val(sa.min(sext(b, wb)) as u64, w))
        }
        IntOp::MaxS => {
            let (b, wb) = arg(1)?;
            Ok(int_val(sa.max(sext(b, wb)) as u64, w))
        }
        IntOp::Abs => Ok(int_val(sa.unsigned_abs(), w)),
        IntOp::Eq => ucmp(|a, b| a == b),
        IntOp::LtU => ucmp(|a, b| a < b),
        IntOp::LteU => ucmp(|a, b| a <= b),
        IntOp::LtS => cmp(|a, b| a < b),
        IntOp::LteS => cmp(|a, b| a <= b),
        IntOp::Select => {
            let pick = if a & 1 == 1 { 1 } else { 2 };
            ins.get(pick)
                .cloned()
                .ok_or_else(|| unsupported(&name, "missing select input"))
        }
        IntOp::ExtS => Ok(int_val(sa as u64, out_bits(out_tys)?)),
        IntOp::ExtU | IntOp::Trunc => Ok(int_val(a, out_bits(out_tys)?)),
        IntOp::ToFloatS => Ok(Val::Float(sa as f64)),
        IntOp::ToFloatU => Ok(Val::Float(a as f64)),
        other => Err(unsupported(format!("{other:?}"), "unknown int op")),
    }
}

fn float_op(op: FloatOp, ins: &[Val]) -> Result<Val, ImportError> {
    let name = format!("{op:?}");
    let f = |i: usize| match ins.get(i) {
        Some(Val::Float(x)) => Ok(*x),
        other => Err(unsupported(&name, format!("input {i} is {other:?}"))),
    };
    let un = |g: fn(f64) -> f64| -> Result<Val, ImportError> { Ok(Val::Float(g(f(0)?))) };
    let bin =
        |g: fn(f64, f64) -> f64| -> Result<Val, ImportError> { Ok(Val::Float(g(f(0)?, f(1)?))) };
    let test = |b: bool| Ok(Val::Bool(BitExpr::Const(b)));
    match op {
        FloatOp::Const32(x) => Ok(Val::Float(x as f64)),
        FloatOp::Const64(x) => Ok(Val::Float(x)),
        FloatOp::Add => bin(|a, b| a + b),
        FloatOp::Sub => bin(|a, b| a - b),
        FloatOp::Mul => bin(|a, b| a * b),
        FloatOp::Div => bin(|a, b| a / b),
        FloatOp::Pow => bin(f64::powf),
        FloatOp::Atan2 => bin(f64::atan2),
        FloatOp::Max => bin(f64::max),
        FloatOp::Min => bin(f64::min),
        FloatOp::Eq => test(f(0)? == f(1)?),
        FloatOp::Lt => test(f(0)? < f(1)?),
        FloatOp::Lte => test(f(0)? <= f(1)?),
        FloatOp::IsNan => test(f(0)?.is_nan()),
        FloatOp::IsInf => test(f(0)?.is_infinite()),
        FloatOp::Sqrt => un(f64::sqrt),
        FloatOp::Abs => un(f64::abs),
        FloatOp::Ceil => un(f64::ceil),
        FloatOp::Floor => un(f64::floor),
        FloatOp::Exp => un(f64::exp),
        FloatOp::Log => un(f64::ln),
        FloatOp::Sin => un(f64::sin),
        FloatOp::Cos => un(f64::cos),
        FloatOp::Tan => un(f64::tan),
        FloatOp::Asin => un(f64::asin),
        FloatOp::Acos => un(f64::acos),
        FloatOp::Atan => un(f64::atan),
        FloatOp::Sinh => un(f64::sinh),
        FloatOp::Cosh => un(f64::cosh),
        FloatOp::Tanh => un(f64::tanh),
        FloatOp::Asinh => un(f64::asinh),
        FloatOp::Acosh => un(f64::acosh),
        FloatOp::Atanh => un(f64::atanh),
        FloatOp::Ext | FloatOp::Trunc => un(|x| x),
        FloatOp::Select => match ins.first() {
            Some(Val::Bool(BitExpr::Const(c))) => {
                let pick = if *c { 1 } else { 2 };
                Ok(Val::Float(f(pick)?))
            }
            other => Err(unsupported(
                &name,
                format!("condition {other:?} is not a constant"),
            )),
        },
        other => Err(unsupported(format!("{other:?}"), "unknown float op")),
    }
}

fn index_of(v: Option<&Val>, what: &str) -> Result<usize, ImportError> {
    match v {
        Some(Val::Int { v, .. }) => Ok(*v as usize),
        other => Err(unsupported(
            what,
            format!("index {other:?} is not a constant"),
        )),
    }
}

fn int_array_op(
    op: IntArrayOp<'_>,
    ins: Vec<Val>,
    out_tys: &[Type],
) -> Result<Vec<Val>, ImportError> {
    let name = format!("{op:?}");
    let arr = |v: Option<&Val>| match v {
        Some(Val::IntArr { bits, items }) => Ok((*bits, items.clone())),
        other => Err(unsupported(&name, format!("{other:?} is not an int array"))),
    };
    let from = |bits: u8, vals: Vec<u64>| Val::IntArr {
        bits,
        items: vals.into_iter().map(|v| int_val(v, bits)).collect(),
    };
    Ok(vec![match op {
        IntArrayOp::ConstArray1(a) => Val::IntArr {
            bits: 1,
            items: a.values().map(|b| Val::Bool(BitExpr::Const(b))).collect(),
        },
        IntArrayOp::ConstArray8(a) => from(8, a.values().map(u64::from).collect()),
        IntArrayOp::ConstArray16(a) => from(16, a.values().map(u64::from).collect()),
        IntArrayOp::ConstArray32(a) => from(32, a.values().map(u64::from).collect()),
        IntArrayOp::ConstArray64(a) => from(64, a.values().collect()),
        IntArrayOp::Zero { bits } => {
            let n = index_of(ins.first(), &name)?;
            from(bits, vec![0; n])
        }
        IntArrayOp::GetIndex => {
            let (_, items) = arr(ins.first())?;
            let i = index_of(ins.get(1), &name)?;
            items
                .get(i)
                .cloned()
                .ok_or_else(|| unsupported(&name, format!("index {i} out of range")))?
        }
        IntArrayOp::SetIndex => {
            let (bits, mut items) = arr(ins.first())?;
            let i = index_of(ins.get(1), &name)?;
            let v = ins
                .get(2)
                .cloned()
                .ok_or_else(|| unsupported(&name, "missing value"))?;
            let slot = items
                .get_mut(i)
                .ok_or_else(|| unsupported(&name, format!("index {i} out of range")))?;
            *slot = v;
            Val::IntArr { bits, items }
        }
        IntArrayOp::Length => {
            let (_, items) = arr(ins.first())?;
            int_val(items.len() as u64, out_bits(out_tys)?)
        }
        IntArrayOp::Create => {
            let bits = match ins.first() {
                Some(Val::Int { bits, .. }) => *bits,
                _ => 1,
            };
            Val::IntArr { bits, items: ins }
        }
        other => return Err(unsupported(format!("{other:?}"), "unknown int array op")),
    }])
}

fn float_array_op(op: FloatArrayOp<'_>, ins: Vec<Val>) -> Result<Vec<Val>, ImportError> {
    let name = format!("{op:?}");
    let arr = |v: Option<&Val>| match v {
        Some(Val::FloatArr(items)) => Ok(items.clone()),
        other => Err(unsupported(
            &name,
            format!("{other:?} is not a float array"),
        )),
    };
    Ok(vec![match op {
        FloatArrayOp::Const32(a) => Val::FloatArr(a.values().map(f64::from).collect()),
        FloatArrayOp::Const64(a) => Val::FloatArr(a.values().collect()),
        FloatArrayOp::Zero { .. } => Val::FloatArr(vec![0.0; index_of(ins.first(), &name)?]),
        FloatArrayOp::GetIndex => {
            let items = arr(ins.first())?;
            let i = index_of(ins.get(1), &name)?;
            Val::Float(
                *items
                    .get(i)
                    .ok_or_else(|| unsupported(&name, format!("index {i} out of range")))?,
            )
        }
        FloatArrayOp::SetIndex => {
            let mut items = arr(ins.first())?;
            let i = index_of(ins.get(1), &name)?;
            let Some(Val::Float(x)) = ins.get(2) else {
                return Err(unsupported(&name, "value is not a constant float"));
            };
            *items
                .get_mut(i)
                .ok_or_else(|| unsupported(&name, format!("index {i} out of range")))? = *x;
            Val::FloatArr(items)
        }
        FloatArrayOp::Length => int_val(arr(ins.first())?.len() as u64, 32),
        FloatArrayOp::Create => Val::FloatArr(
            ins.iter()
                .map(|v| match v {
                    Val::Float(x) => Ok(*x),
                    other => Err(unsupported(&name, format!("{other:?} is not a float"))),
                })
                .collect::<Result<_, _>>()?,
        ),
        other => return Err(unsupported(format!("{other:?}"), "unknown float array op")),
    }])
}
