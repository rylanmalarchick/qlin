//! IR for dynamic quantum programs.
//!
//! A program is a block of ops. Control flow is `If` on a bit expression
//! and `Loop` with a measured exit. There are no static loops: `repeat N`
//! unrolls in the parser. Gate angles are constants.

use std::collections::BTreeSet;
use std::fmt;

use serde::{Serialize, Serializer};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize)]
pub struct Qubit(pub u32);

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize)]
pub struct Bit(pub u32);

/// Gate kinds. `Custom` is an opaque symbol: the analysis compares it by
/// name, and the simulator refuses it.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Gate {
    H,
    X,
    Y,
    Z,
    S,
    Sdg,
    T,
    Tdg,
    Sx,
    Rx,
    Ry,
    Rz,
    P,
    U,
    Cx,
    Cy,
    Cz,
    Ch,
    Cp,
    Crz,
    Ccx,
    Swap,
    Custom {
        name: String,
        arity: usize,
        n_params: usize,
    },
}

/// Built-in gates as (name, gate, arity, parameter count).
const BUILTIN: &[(&str, Gate, usize, usize)] = &[
    ("h", Gate::H, 1, 0),
    ("x", Gate::X, 1, 0),
    ("y", Gate::Y, 1, 0),
    ("z", Gate::Z, 1, 0),
    ("s", Gate::S, 1, 0),
    ("sdg", Gate::Sdg, 1, 0),
    ("t", Gate::T, 1, 0),
    ("tdg", Gate::Tdg, 1, 0),
    ("sx", Gate::Sx, 1, 0),
    ("rx", Gate::Rx, 1, 1),
    ("ry", Gate::Ry, 1, 1),
    ("rz", Gate::Rz, 1, 1),
    ("p", Gate::P, 1, 1),
    ("u", Gate::U, 1, 3),
    ("cx", Gate::Cx, 2, 0),
    ("cy", Gate::Cy, 2, 0),
    ("cz", Gate::Cz, 2, 0),
    ("ch", Gate::Ch, 2, 0),
    ("cp", Gate::Cp, 2, 1),
    ("crz", Gate::Crz, 2, 1),
    ("ccx", Gate::Ccx, 3, 0),
    ("swap", Gate::Swap, 2, 0),
];

impl Gate {
    /// Looks up a built-in gate by its text name.
    pub fn builtin(name: &str) -> Option<Gate> {
        BUILTIN
            .iter()
            .find(|(n, ..)| *n == name)
            .map(|(_, g, ..)| g.clone())
    }

    fn entry(&self) -> Option<&'static (&'static str, Gate, usize, usize)> {
        BUILTIN.iter().find(|(_, g, ..)| g == self)
    }

    pub fn name(&self) -> &str {
        match self {
            Gate::Custom { name, .. } => name,
            g => g.entry().expect("every built-in gate is in BUILTIN").0,
        }
    }

    pub fn arity(&self) -> usize {
        match self {
            Gate::Custom { arity, .. } => *arity,
            g => g.entry().expect("every built-in gate is in BUILTIN").2,
        }
    }

    pub fn n_params(&self) -> usize {
        match self {
            Gate::Custom { n_params, .. } => *n_params,
            g => g.entry().expect("every built-in gate is in BUILTIN").3,
        }
    }
}

/// A boolean expression over classical bits.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize)]
pub enum BitExpr {
    Const(bool),
    Bit(Bit),
    Not(Box<BitExpr>),
    And(Box<BitExpr>, Box<BitExpr>),
    Or(Box<BitExpr>, Box<BitExpr>),
    Xor(Box<BitExpr>, Box<BitExpr>),
}

impl BitExpr {
    pub fn bit(i: u32) -> BitExpr {
        BitExpr::Bit(Bit(i))
    }

    #[allow(clippy::should_implement_trait)]
    pub fn not(self) -> BitExpr {
        BitExpr::Not(Box::new(self))
    }

    pub fn and(self, rhs: BitExpr) -> BitExpr {
        BitExpr::And(Box::new(self), Box::new(rhs))
    }

    pub fn or(self, rhs: BitExpr) -> BitExpr {
        BitExpr::Or(Box::new(self), Box::new(rhs))
    }

    pub fn xor(self, rhs: BitExpr) -> BitExpr {
        BitExpr::Xor(Box::new(self), Box::new(rhs))
    }

    /// Evaluates the expression with every bit value given.
    pub fn eval(&self, value: &impl Fn(Bit) -> bool) -> bool {
        match self {
            BitExpr::Const(c) => *c,
            BitExpr::Bit(b) => value(*b),
            BitExpr::Not(e) => !e.eval(value),
            BitExpr::And(a, b) => a.eval(value) && b.eval(value),
            BitExpr::Or(a, b) => a.eval(value) || b.eval(value),
            BitExpr::Xor(a, b) => a.eval(value) ^ b.eval(value),
        }
    }

    /// The set of bits the expression reads.
    pub fn bits(&self) -> BTreeSet<Bit> {
        let mut out = BTreeSet::new();
        self.collect_bits(&mut out);
        out
    }

    fn collect_bits(&self, out: &mut BTreeSet<Bit>) {
        match self {
            BitExpr::Const(_) => {}
            BitExpr::Bit(b) => {
                out.insert(*b);
            }
            BitExpr::Not(e) => e.collect_bits(out),
            BitExpr::And(a, b) | BitExpr::Or(a, b) | BitExpr::Xor(a, b) => {
                a.collect_bits(out);
                b.collect_bits(out);
            }
        }
    }
}

pub type Block = Vec<Op>;

#[derive(Clone, Debug, PartialEq, Serialize)]
pub enum Op {
    Gate {
        gate: Gate,
        qubits: Vec<Qubit>,
        params: Vec<f64>,
    },
    Measure {
        q: Qubit,
        b: Bit,
    },
    Reset {
        q: Qubit,
    },
    If {
        cond: BitExpr,
        then_: Block,
        else_: Block,
    },
    /// Runs `body`, then exits when `until` is true. `max_iters` bounds
    /// the iterations that the analysis and the simulator explore.
    Loop {
        body: Block,
        until: BitExpr,
        max_iters: u32,
    },
}

/// A gate serializes as its text name.
impl Serialize for Gate {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(self.name())
    }
}

/// Qubits and bits an op touches, used to decide if two ops commute.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Footprint {
    pub qubits: BTreeSet<Qubit>,
    pub reads: BTreeSet<Bit>,
    pub writes: BTreeSet<Bit>,
}

impl Footprint {
    /// True when the two ops share no qubit and no bit conflict (write/write
    /// or write/read). Such ops commute.
    pub fn disjoint(&self, other: &Footprint) -> bool {
        self.qubits.is_disjoint(&other.qubits)
            && self.writes.is_disjoint(&other.writes)
            && self.writes.is_disjoint(&other.reads)
            && self.reads.is_disjoint(&other.writes)
    }
}

impl Op {
    pub fn footprint(&self) -> Footprint {
        let mut fp = Footprint::default();
        self.add_footprint(&mut fp);
        fp
    }

    fn add_footprint(&self, fp: &mut Footprint) {
        match self {
            Op::Gate { qubits, .. } => fp.qubits.extend(qubits.iter().copied()),
            Op::Measure { q, b } => {
                fp.qubits.insert(*q);
                fp.writes.insert(*b);
            }
            Op::Reset { q } => {
                fp.qubits.insert(*q);
            }
            Op::If { cond, then_, else_ } => {
                fp.reads.extend(cond.bits());
                for op in then_.iter().chain(else_) {
                    op.add_footprint(fp);
                }
            }
            Op::Loop { body, until, .. } => {
                fp.reads.extend(until.bits());
                for op in body {
                    op.add_footprint(fp);
                }
            }
        }
    }

    /// True for gate, measure, and reset. These are the ops the analysis
    /// counts.
    pub fn is_leaf(&self) -> bool {
        matches!(
            self,
            Op::Gate { .. } | Op::Measure { .. } | Op::Reset { .. }
        )
    }
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Program {
    pub n_qubits: u32,
    pub n_bits: u32,
    pub body: Block,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ValidateError {
    QubitOutOfRange(Qubit),
    BitOutOfRange(Bit),
    Arity {
        gate: String,
        expected: usize,
        got: usize,
    },
    ParamCount {
        gate: String,
        expected: usize,
        got: usize,
    },
    RepeatedQubit {
        gate: String,
        q: Qubit,
    },
    ZeroMaxIters,
    NonFiniteParam {
        gate: String,
    },
}

impl fmt::Display for ValidateError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ValidateError::QubitOutOfRange(q) => write!(f, "qubit q{} out of range", q.0),
            ValidateError::BitOutOfRange(b) => write!(f, "bit c{} out of range", b.0),
            ValidateError::Arity {
                gate,
                expected,
                got,
            } => write!(f, "gate {gate} takes {expected} qubits, got {got}"),
            ValidateError::ParamCount {
                gate,
                expected,
                got,
            } => write!(f, "gate {gate} takes {expected} parameters, got {got}"),
            ValidateError::RepeatedQubit { gate, q } => {
                write!(f, "gate {gate} uses qubit q{} twice", q.0)
            }
            ValidateError::ZeroMaxIters => write!(f, "loop max must be at least 1"),
            ValidateError::NonFiniteParam { gate } => {
                write!(f, "gate {gate} has a parameter that is not finite")
            }
        }
    }
}

impl std::error::Error for ValidateError {}

impl Program {
    /// Checks index ranges, gate arities, and parameter counts.
    pub fn validate(&self) -> Result<(), ValidateError> {
        self.validate_block(&self.body)
    }

    fn validate_block(&self, block: &Block) -> Result<(), ValidateError> {
        for op in block {
            self.validate_op(op)?;
        }
        Ok(())
    }

    fn check_qubit(&self, q: Qubit) -> Result<(), ValidateError> {
        if q.0 < self.n_qubits {
            Ok(())
        } else {
            Err(ValidateError::QubitOutOfRange(q))
        }
    }

    fn check_bits(&self, e: &BitExpr) -> Result<(), ValidateError> {
        match e.bits().into_iter().find(|b| b.0 >= self.n_bits) {
            Some(b) => Err(ValidateError::BitOutOfRange(b)),
            None => Ok(()),
        }
    }

    fn validate_op(&self, op: &Op) -> Result<(), ValidateError> {
        match op {
            Op::Gate {
                gate,
                qubits,
                params,
            } => {
                if qubits.len() != gate.arity() {
                    return Err(ValidateError::Arity {
                        gate: gate.name().to_string(),
                        expected: gate.arity(),
                        got: qubits.len(),
                    });
                }
                if params.len() != gate.n_params() {
                    return Err(ValidateError::ParamCount {
                        gate: gate.name().to_string(),
                        expected: gate.n_params(),
                        got: params.len(),
                    });
                }
                if params.iter().any(|p| !p.is_finite()) {
                    return Err(ValidateError::NonFiniteParam {
                        gate: gate.name().to_string(),
                    });
                }
                let mut seen = BTreeSet::new();
                for q in qubits {
                    self.check_qubit(*q)?;
                    if !seen.insert(*q) {
                        return Err(ValidateError::RepeatedQubit {
                            gate: gate.name().to_string(),
                            q: *q,
                        });
                    }
                }
                Ok(())
            }
            Op::Measure { q, b } => {
                self.check_qubit(*q)?;
                if b.0 >= self.n_bits {
                    return Err(ValidateError::BitOutOfRange(*b));
                }
                Ok(())
            }
            Op::Reset { q } => self.check_qubit(*q),
            Op::If { cond, then_, else_ } => {
                self.check_bits(cond)?;
                self.validate_block(then_)?;
                self.validate_block(else_)
            }
            Op::Loop {
                body,
                until,
                max_iters,
            } => {
                if *max_iters == 0 {
                    return Err(ValidateError::ZeroMaxIters);
                }
                self.check_bits(until)?;
                self.validate_block(body)
            }
        }
    }
}

/// Position of an op in the program tree. The path alternates block index
/// and arm: `[i]` is op `i` of the body. `[i, 0, j]` is op `j` of the
/// `then` arm (or the loop body) of op `i`. `[i, 1, j]` is op `j` of its
/// `else` arm.
pub type OpPath = Vec<usize>;

impl Program {
    /// Returns the op at `path`, or `None` if the path is not valid.
    pub fn op_at(&self, path: &[usize]) -> Option<&Op> {
        let (&first, mut rest) = path.split_first()?;
        let mut op = self.body.get(first)?;
        while !rest.is_empty() {
            let [arm, idx, tail @ ..] = rest else {
                return None;
            };
            let block = match (op, arm) {
                (Op::If { then_, .. }, 0) => then_,
                (Op::If { else_, .. }, 1) => else_,
                (Op::Loop { body, .. }, 0) => body,
                _ => return None,
            };
            op = block.get(*idx)?;
            rest = tail;
        }
        Some(op)
    }
}
