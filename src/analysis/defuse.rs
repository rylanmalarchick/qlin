//! Def-use over classical bits.

use std::collections::BTreeMap;

use crate::ir::{Bit, Block, Op, OpPath, Program};

/// For each bit: the measure ops that write it, and the `If` and `Loop`
/// ops whose condition reads it. Paths follow [`OpPath`].
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct DefUse {
    pub defs: BTreeMap<Bit, Vec<OpPath>>,
    pub uses: BTreeMap<Bit, Vec<OpPath>>,
}

pub fn defuse(prog: &Program) -> DefUse {
    let mut du = DefUse::default();
    walk(&prog.body, &mut Vec::new(), &mut du);
    du
}

fn walk(block: &Block, prefix: &mut OpPath, du: &mut DefUse) {
    for (i, op) in block.iter().enumerate() {
        prefix.push(i);
        match op {
            Op::Measure { b, .. } => du.defs.entry(*b).or_default().push(prefix.clone()),
            Op::If { cond, then_, else_ } => {
                for b in cond.bits() {
                    du.uses.entry(b).or_default().push(prefix.clone());
                }
                for (arm, blk) in [then_, else_].into_iter().enumerate() {
                    prefix.push(arm);
                    walk(blk, prefix, du);
                    prefix.pop();
                }
            }
            Op::Loop { body, until, .. } => {
                for b in until.bits() {
                    du.uses.entry(b).or_default().push(prefix.clone());
                }
                prefix.push(0);
                walk(body, prefix, du);
                prefix.pop();
            }
            Op::Gate { .. } | Op::Reset { .. } => {}
        }
        prefix.pop();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::text::parse;

    #[test]
    fn defs_and_uses() {
        let p = parse(
            "qubits 2\nbits 2\nmeasure q0 -> c0\nif c0 { measure q1 -> c1 }\n\
             loop max 3 { measure q1 -> c1 } until c1 & c0\n",
        )
        .unwrap();
        let du = defuse(&p);
        assert_eq!(du.defs[&Bit(0)], vec![vec![0]]);
        assert_eq!(du.defs[&Bit(1)], vec![vec![1, 0, 0], vec![2, 0, 0]]);
        assert_eq!(du.uses[&Bit(0)], vec![vec![1], vec![2]]);
        assert_eq!(du.uses[&Bit(1)], vec![vec![2]]);
    }
}
