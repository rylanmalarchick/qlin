//! Device cost model: op durations and feedforward latency, in ns.

use std::fmt;

use serde::Serialize;

use crate::ir::Op;

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
pub struct CostModel {
    pub t_1q: f64,
    pub t_2q: f64,
    /// Three-qubit gates (ccx).
    pub t_3q: f64,
    pub t_meas: f64,
    pub t_reset: f64,
    /// Time from the end of a measurement to the start of an op that is
    /// classically conditioned on it.
    pub t_ff: f64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct CostError(pub String);

impl fmt::Display for CostError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "invalid cost model: {}", self.0)
    }
}

impl std::error::Error for CostError {}

impl CostModel {
    /// Starting values only, not measured. 1q and 2q times are assumed for
    /// an IBM Heron-class device. t_meas (mid-circuit) and t_ff come from
    /// notes/prior-work.txt section 8. t_3q is 6 x t_2q (ccx in cx).
    pub const HERON_LIKE: CostModel = CostModel {
        t_1q: 32.0,
        t_2q: 68.0,
        t_3q: 408.0,
        t_meas: 800.0,
        t_reset: 1000.0,
        t_ff: 600.0,
    };

    /// Checks that every time is finite and non-negative and that
    /// `t_1q <= t_2q <= t_3q`. The relaxation bound needs the ordering: a
    /// controlled gate is never faster than its base gate.
    pub fn validate(&self) -> Result<(), CostError> {
        let all = [
            self.t_1q,
            self.t_2q,
            self.t_3q,
            self.t_meas,
            self.t_reset,
            self.t_ff,
        ];
        if all.iter().any(|t| !t.is_finite() || *t < 0.0) {
            return Err(CostError("times must be finite and >= 0".into()));
        }
        if !(self.t_1q <= self.t_2q && self.t_2q <= self.t_3q) {
            return Err(CostError("need t_1q <= t_2q <= t_3q".into()));
        }
        Ok(())
    }

    /// Duration of a leaf op. Control flow has no duration of its own.
    pub fn duration(&self, op: &Op) -> f64 {
        match op {
            Op::Gate { qubits, .. } => match qubits.len() {
                0 | 1 => self.t_1q,
                2 => self.t_2q,
                _ => self.t_3q,
            },
            Op::Measure { .. } => self.t_meas,
            Op::Reset { .. } => self.t_reset,
            Op::If { .. } | Op::Loop { .. } => 0.0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preset_is_valid_and_bad_orders_are_rejected() {
        assert!(CostModel::HERON_LIKE.validate().is_ok());
        let bad = CostModel {
            t_2q: 10.0,
            ..CostModel::HERON_LIKE
        };
        assert!(bad.validate().is_err());
        let neg = CostModel {
            t_ff: -1.0,
            ..CostModel::HERON_LIKE
        };
        assert!(neg.validate().is_err());
    }
}
