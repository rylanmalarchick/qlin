import Qlin.Structure

/-!
# R4: the M0 moves never increase replay latency (claim C1)

A timing semantics copied from `Replay` in `src/latency.rs`, Ideal
model, no noise qubits, no relaxed Ifs:
- A leaf starts when its qubits are free and each enclosing condition
  bit's latest measurement has ended plus `t_ff` (`gate_time`). A leaf
  that writes a bit is a measurement. It records the end time and the
  next outcome of that bit from the record.
- An If runs its taken arm, gated also on its condition bits.
- A loop runs at most `K` iterations. Iterations after the first are
  gated on the exit bits. A loop that never exits stops the run (the
  `stopped` flag): every later op is skipped.
- A Switch runs its first matching case, gated on its bits.

Theorems:
- `run_mono`: the schedule is monotone in the start state and in the
  gate bits.
- `hoist_latency` and `merge_latency`: one hoist or merge step gives a
  state that is no later, pointwise, than the original. The side
  conditions are those of `match_arms` in `src/analysis/core.rs`,
  including the enclosing condition bits (`gates`): see
  notes/c1-counterexample. The run must not stop (no truncated loop on
  this record).
-/

namespace Qlin

open scoped NNReal

/-- Durations and feedforward latency (ns). -/
structure Cost where
  dur : ℕ → Footprint → ℝ≥0
  tff : ℝ≥0

/-- The replay state. -/
structure TState where
  ready : Qubit → ℝ≥0
  measEnd : Bit → Option ℝ≥0
  vals : Assign
  cursor : Bit → ℕ
  stopped : Bool

/-- The outcome of the `k`-th measurement of each bit. -/
abbrev Record := Bit → ℕ → Bool

/-- The earliest start allowed by the gate bits (`gate_time`). -/
def gateTime (C : Cost) (st : TState) (gates : Finset Bit) : ℝ≥0 :=
  gates.sup fun b => match st.measEnd b with
    | some t => t + C.tff
    | none => 0

/-- One leaf (`run_leaf`, and `next_outcome` for a measurement). -/
def leafT (C : Cost) (R : Record) (i : ℕ) (f : Footprint) (gates : Finset Bit)
    (st : TState) : TState :=
  if st.stopped then st else
    let fin := max (gateTime C st gates) (f.qubits.sup st.ready) + C.dur i f
    { ready := fun q => if q ∈ f.qubits then fin else st.ready q
      measEnd := fun b => if b ∈ f.writes then some fin else st.measEnd b
      vals := fun b => if b ∈ f.writes then R b (st.cursor b) else st.vals b
      cursor := fun b => if b ∈ f.writes then st.cursor b + 1 else st.cursor b
      stopped := false }

/-- A loop: at most `k` more iterations of `body`. `first` marks the first
iteration, which is not gated on the exit bits. -/
def loopT (body : Finset Bit → TState → TState) (c : Cond) (gates : Finset Bit) :
    ℕ → Bool → TState → TState
  | 0, _, st => { st with stopped := true }
  | k + 1, first, st =>
      let st' := body (if first then gates else gates ∪ c.bits) st
      if st'.stopped || c.eval st'.vals then st' else loopT body c gates k false st'

/-- `β` agrees with `v` on `G`. -/
def agrees (G : Finset Bit) (β v : Assign) : Prop := ∀ b ∈ G, β b = v b

instance (G : Finset Bit) (β v : Assign) : Decidable (agrees G β v) := by
  unfold agrees; infer_instance

mutual
/-- Replay one op with the enclosing gate bits `gates`. -/
def run (C : Cost) (R : Record) : Op → Finset Bit → TState → TState
  | .leaf i f, gates, st => leafT C R i f gates st
  | .ite c A B, gates, st =>
      if st.stopped then st
      else if c.eval st.vals then runB C R A (gates ∪ c.bits) st
      else runB C R B (gates ∪ c.bits) st
  | .loop K body c, gates, st =>
      if st.stopped then st
      else loopT (fun g t => runB C R body g t) c gates K true st
  | .switch G cases dflt, gates, st =>
      if st.stopped then st else runCases C R G cases dflt (gates ∪ G) st
  termination_by o => sizeOf o

/-- Replay a block. -/
def runB (C : Cost) (R : Record) : List Op → Finset Bit → TState → TState
  | [], _, st => st
  | o :: os, gates, st => runB C R os gates (run C R o gates st)
  termination_by l => sizeOf l

/-- The first case whose value agrees on `G`, else `dflt`. -/
def runCases (C : Cost) (R : Record) (G : Finset Bit) :
    List (Assign × List Op) → List Op → Finset Bit → TState → TState
  | [], dflt, gates, st => runB C R dflt gates st
  | (v, blk) :: cs, dflt, gates, st =>
      if agrees G st.vals v then runB C R blk gates st
      else runCases C R G cs dflt gates st
  termination_by cs dflt => sizeOf cs + sizeOf dflt
end

/-- `none ≤ none` and `some a ≤ some b` when `a ≤ b`. -/
def OptLe : Option ℝ≥0 → Option ℝ≥0 → Prop
  | none, none => True
  | some a, some b => a ≤ b
  | _, _ => False

/-- `a` is no later than `b`, with the same classical state. -/
def TState.Le (a b : TState) : Prop :=
  a.vals = b.vals ∧ a.cursor = b.cursor ∧ a.stopped = b.stopped ∧
    (∀ q, a.ready q ≤ b.ready q) ∧ (∀ x, OptLe (a.measEnd x) (b.measEnd x))

/-- The makespan over the qubits `Q` (`replay` returns it). -/
def makespan (Q : Finset Qubit) (st : TState) : ℝ≥0 := Q.sup st.ready

/-- The schedule is monotone in the start state and the gate bits. -/
theorem run_mono (C : Cost) (R : Record) (o : Op) (g1 g2 : Finset Bit) (h : g1 ⊆ g2)
    (a b : TState) (hab : a.Le b) : (run C R o g1 a).Le (run C R o g2 b) := by
  sorry

theorem runB_mono (C : Cost) (R : Record) (l : List Op) (g1 g2 : Finset Bit)
    (h : g1 ⊆ g2) (a b : TState) (hab : a.Le b) :
    (runB C R l g1 a).Le (runB C R l g2 b) := by
  sorry

/-- A hoist step does not increase latency: side conditions of
`hoist_sound`, plus `x` writes no enclosing gate bit. -/
theorem hoist_latency (C : Cost) (R : Record) (c : Cond) (x : Op) (pA A pB B : List Op)
    (gates : Finset Bit)
    (hA : ∀ y ∈ pA, (Op.fp x).Disj (Op.fp y))
    (hB : ∀ y ∈ pB, (Op.fp x).Disj (Op.fp y))
    (hc : Disjoint c.bits (Op.fp x).writes)
    (henc : Disjoint gates (Op.fp x).writes)
    (st : TState) (hst : st.stopped = false)
    (hrun : (run C R (.ite c (pA ++ x :: A) (pB ++ x :: B)) gates st).stopped = false) :
    (runB C R [x, .ite c (pA ++ A) (pB ++ B)] gates st).Le
      (run C R (.ite c (pA ++ x :: A) (pB ++ x :: B)) gates st) := by
  sorry

/-- A merge step does not increase latency: side conditions of
`merge_sound`, plus the ops `x` moves past write no enclosing gate bit. -/
theorem merge_latency (C : Cost) (R : Record) (c : Cond) (x : Op) (A sA B sB : List Op)
    (gates : Finset Bit)
    (hA : ∀ y ∈ sA, (Op.fp x).Disj (Op.fp y))
    (hB : ∀ y ∈ sB, (Op.fp x).Disj (Op.fp y))
    (hencA : ∀ y ∈ sA, Disjoint gates (Op.fp y).writes)
    (hencB : ∀ y ∈ sB, Disjoint gates (Op.fp y).writes)
    (st : TState) (hst : st.stopped = false)
    (hrun : (run C R (.ite c (A ++ x :: sA) (B ++ x :: sB)) gates st).stopped = false) :
    (runB C R [.ite c (A ++ sA) (B ++ sB), x] gates st).Le
      (run C R (.ite c (A ++ x :: sA) (B ++ x :: sB)) gates st) := by
  sorry

/-- No later, pointwise, gives no larger makespan. -/
theorem makespan_le (Q : Finset Qubit) (a b : TState) (h : a.Le b) :
    makespan Q a ≤ makespan Q b := by
  exact Finset.sup_mono_fun fun q _ => h.2.2.2.1 q

end Qlin
