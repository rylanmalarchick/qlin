//! Builder API for writing programs in code.
//!
//! ```
//! use qlin::builder::ProgramBuilder;
//! use qlin::ir::BitExpr;
//!
//! let mut b = ProgramBuilder::new(2, 1);
//! b.h(0).cx(0, 1).measure(0, 0);
//! b.if_(BitExpr::bit(0), |t| {
//!     t.x(1);
//! });
//! let prog = b.build().unwrap();
//! assert_eq!(prog.body.len(), 4);
//! ```

use crate::ir::{Bit, BitExpr, Block, Gate, Op, Program, Qubit, ValidateError};

/// Builds one block of ops.
#[derive(Default)]
pub struct BlockBuilder {
    ops: Block,
}

impl BlockBuilder {
    pub fn gate(&mut self, gate: Gate, qubits: &[u32], params: &[f64]) -> &mut Self {
        self.ops.push(Op::Gate {
            gate,
            qubits: qubits.iter().map(|&q| Qubit(q)).collect(),
            params: params.to_vec(),
        });
        self
    }

    pub fn h(&mut self, q: u32) -> &mut Self {
        self.gate(Gate::H, &[q], &[])
    }

    pub fn x(&mut self, q: u32) -> &mut Self {
        self.gate(Gate::X, &[q], &[])
    }

    pub fn z(&mut self, q: u32) -> &mut Self {
        self.gate(Gate::Z, &[q], &[])
    }

    pub fn ry(&mut self, theta: f64, q: u32) -> &mut Self {
        self.gate(Gate::Ry, &[q], &[theta])
    }

    pub fn rz(&mut self, theta: f64, q: u32) -> &mut Self {
        self.gate(Gate::Rz, &[q], &[theta])
    }

    pub fn cx(&mut self, c: u32, t: u32) -> &mut Self {
        self.gate(Gate::Cx, &[c, t], &[])
    }

    pub fn measure(&mut self, q: u32, b: u32) -> &mut Self {
        self.ops.push(Op::Measure {
            q: Qubit(q),
            b: Bit(b),
        });
        self
    }

    pub fn reset(&mut self, q: u32) -> &mut Self {
        self.ops.push(Op::Reset { q: Qubit(q) });
        self
    }

    /// `if cond { then }` with an empty else arm.
    pub fn if_(&mut self, cond: BitExpr, then_: impl FnOnce(&mut BlockBuilder)) -> &mut Self {
        self.if_else(cond, then_, |_| {})
    }

    pub fn if_else(
        &mut self,
        cond: BitExpr,
        then_: impl FnOnce(&mut BlockBuilder),
        else_: impl FnOnce(&mut BlockBuilder),
    ) -> &mut Self {
        let mut t = BlockBuilder::default();
        then_(&mut t);
        let mut e = BlockBuilder::default();
        else_(&mut e);
        self.ops.push(Op::If {
            cond,
            then_: t.ops,
            else_: e.ops,
        });
        self
    }

    pub fn loop_until(
        &mut self,
        max_iters: u32,
        until: BitExpr,
        body: impl FnOnce(&mut BlockBuilder),
    ) -> &mut Self {
        let mut b = BlockBuilder::default();
        body(&mut b);
        self.ops.push(Op::Loop {
            body: b.ops,
            until,
            max_iters,
        });
        self
    }
}

/// Builds a whole program. Derefs to the top-level [`BlockBuilder`].
pub struct ProgramBuilder {
    n_qubits: u32,
    n_bits: u32,
    top: BlockBuilder,
}

impl ProgramBuilder {
    pub fn new(n_qubits: u32, n_bits: u32) -> Self {
        ProgramBuilder {
            n_qubits,
            n_bits,
            top: BlockBuilder::default(),
        }
    }

    /// Validates and returns the program.
    pub fn build(self) -> Result<Program, ValidateError> {
        let prog = Program {
            n_qubits: self.n_qubits,
            n_bits: self.n_bits,
            body: self.top.ops,
        };
        prog.validate()?;
        Ok(prog)
    }
}

impl std::ops::Deref for ProgramBuilder {
    type Target = BlockBuilder;
    fn deref(&self) -> &BlockBuilder {
        &self.top
    }
}

impl std::ops::DerefMut for ProgramBuilder {
    fn deref_mut(&mut self) -> &mut BlockBuilder {
        &mut self.top
    }
}
