//! qlin: a compiler for dynamic quantum circuits.
//!
//! The crate has the IR ([`ir`]), a builder ([`builder`]), the `.qlin`
//! text format ([`text`]), the dynamic-core analysis ([`analysis`]), a
//! per-outcome trace enumerator ([`trace`]), and a state-vector simulator
//! used as a test oracle ([`sim`]).

pub mod analysis;
pub mod builder;
pub mod cost;
pub mod import;
pub mod ir;
pub mod sim;
pub mod stats;
pub mod text;
pub mod trace;
