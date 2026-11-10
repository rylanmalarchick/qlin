import Qlin.Latency

/-!
# The block timing model, and where C1 stops

The `Block` model of `src/latency.rs` (`Sync::Block`): the ideal replay of
`Latency.lean`, plus a serial controller. Each executed branch (an `if`,
the exit test of a loop iteration, a `switch`) is one step of the
controller (`Replay::stall`):
- the step starts when the condition bits and the enclosing gate bits are
  known (`gateTime`) and the controller is free;
- it takes `decisions × t_branch`;
- every qubit of the branch waits for its end, taken or not.

No noise qubits and no relaxed Ifs, as in `Latency.lean`.

`hoist_block_can_delay`: C1 does not carry over to this model. A hoist
that meets every side condition of `hoist_latency` can delay a qubit when
the hoisted op is itself a branch: the controller then decides the
hoisted branch first, and the outer branch waits for it
(notes/block-counterexample).
-/

namespace Qlin

open scoped NNReal

/-- The block cost model: the ideal durations, the time per branch
decision, and the number of decisions of a switch (bits, cases, taken
arm), as `SwitchCost::decisions`. -/
structure BCost where
  base : Cost
  tb : ℝ≥0
  dec : ℕ → ℕ → ℕ → ℕ

/-- The replay state with the controller: `free` is when the controller
can decide the next branch (`controller_free`). -/
structure BState where
  st : TState
  free : ℝ≥0

/-- One controller step (`Replay::stall`) for a branch with footprint `f`,
condition bits `bits`, enclosing gate bits `gates`, and `n` decisions. -/
def stall (C : BCost) (f : Footprint) (bits gates : Finset Bit) (n : ℕ) (s : BState) : BState :=
  let t := max (max (gateTime C.base s.st bits) (gateTime C.base s.st gates)) s.free + C.tb * n
  { st := { s.st with
      ready := fun q => if q ∈ f.qubits then max (s.st.ready q) t else s.st.ready q }
    free := t }

/-- A loop in the block model: after each iteration that does not stop,
the controller decides the exit test. -/
def loopK (body : Finset Bit → BState → BState) (stl : BState → BState) (c : Cond)
    (gates : Finset Bit) : ℕ → Bool → BState → BState
  | 0, _, s => { s with st := { s.st with stopped := true } }
  | k + 1, first, s =>
      let s1 := body (if first then gates else gates ∪ c.bits) s
      let s2 := if s1.st.stopped then s1 else stl s1
      if s2.st.stopped || c.eval s2.st.vals then s2 else loopK body stl c gates k false s2

/-- The index of the taken arm of a switch: the first case that agrees,
or the number of cases for the default. -/
def armIdx (G : Finset Bit) (vals : Assign) : List (Assign × List Op) → ℕ
  | [] => 0
  | (v, _) :: cs => if agrees G vals v then 0 else armIdx G vals cs + 1

mutual
/-- Replay one op in the block model. -/
def runK (C : BCost) (R : Record) : Op → Finset Bit → BState → BState
  | .leaf i f, gates, s => { s with st := leafT C.base R i f gates s.st }
  | .ite c A B, gates, s =>
      if s.st.stopped then s
      else if c.eval s.st.vals then
        runKB C R A (gates ∪ c.bits) (stall C (Op.fp (.ite c A B)) c.bits gates 1 s)
      else runKB C R B (gates ∪ c.bits) (stall C (Op.fp (.ite c A B)) c.bits gates 1 s)
  | .loop K body c, gates, s =>
      if s.st.stopped then s
      else loopK (fun g t => runKB C R body g t)
        (stall C (Op.fp (.loop K body c)) c.bits gates 1) c gates K true s
  | .switch G cases dflt, gates, s =>
      if s.st.stopped then s
      else runKCases C R G cases dflt (gates ∪ G)
        (stall C (Op.fp (.switch G cases dflt)) G gates
          (C.dec G.card cases.length (armIdx G s.st.vals cases)) s)
  termination_by o => sizeOf o

/-- Replay a block in the block model. -/
def runKB (C : BCost) (R : Record) : List Op → Finset Bit → BState → BState
  | [], _, s => s
  | o :: os, gates, s => runKB C R os gates (runK C R o gates s)
  termination_by l => sizeOf l

/-- The first case whose value agrees on `G`, else `dflt`. -/
def runKCases (C : BCost) (R : Record) (G : Finset Bit) :
    List (Assign × List Op) → List Op → Finset Bit → BState → BState
  | [], dflt, gates, s => runKB C R dflt gates s
  | (v, blk) :: cs, dflt, gates, s =>
      if agrees G s.st.vals v then runKB C R blk gates s
      else runKCases C R G cs dflt gates s
  termination_by cs dflt => sizeOf cs + sizeOf dflt
end

/-! ### C1 fails for a hoisted branch -/

private theorem fq (f g : Footprint) : (f ∪ g).qubits = f.qubits ∪ g.qubits := rfl
private theorem fr (f g : Footprint) : (f ∪ g).reads = f.reads ∪ g.reads := rfl
private theorem fw (f g : Footprint) : (f ∪ g).writes = f.writes ∪ g.writes := rfl

private def cb (b : Bit) : Cond := ⟨fun β => β b, {b}, fun _ _ h => h b (Finset.mem_singleton_self b)⟩

/-- Leaf 0 (on qubit 4) takes 100, every other leaf takes 1. No
feedforward latency, 10 per decision. -/
private def costB : BCost := ⟨⟨fun i _ => if i = 0 then 100 else 1, 0⟩, 10, fun _ _ _ => 1⟩

/-- Bit 0 was measured at time 0, bit 2 at time 1000. Both are 1. -/
private def sB : BState :=
  ⟨⟨fun _ => 0, fun b => if b = 2 then some 1000 else if b = 0 then some 0 else none,
    fun _ => true, fun _ => 0, false⟩, 0⟩

/-- In the block model, a hoist that meets the side conditions of
`hoist_latency` can delay a qubit. Source: `if c0 { g q4; if c2 { y q3 } }
else { if c2 { y q3 } }`. Target: `if c2 { y q3 }; if c0 { g q4 }`. Bit 2
is known late, so in the target the controller is busy until then, and
`g` on qubit 4 ends at 1120 instead of 110. -/
theorem hoist_block_can_delay : ¬ ∀ (C : BCost) (R : Record) (c : Cond) (x : Op)
    (pA A pB B : List Op) (gates : Finset Bit),
    (∀ y ∈ pA, (Op.fp x).Disj (Op.fp y)) → (∀ y ∈ pB, (Op.fp x).Disj (Op.fp y)) →
    Disjoint c.bits (Op.fp x).writes → Disjoint gates (Op.fp x).writes →
    ∀ s : BState, s.st.stopped = false →
    (runK C R (.ite c (pA ++ x :: A) (pB ++ x :: B)) gates s).st.stopped = false →
    ∀ q, (runKB C R [x, .ite c (pA ++ A) (pB ++ B)] gates s).st.ready q ≤
      (runK C R (.ite c (pA ++ x :: A) (pB ++ x :: B)) gates s).st.ready q := by
  intro H
  have h := H costB (fun _ _ => false) (cb 0) (.ite (cb 2) [.leaf 1 ⟨{3}, ∅, ∅⟩] [])
    [.leaf 0 ⟨{4}, ∅, ∅⟩] [] [] [] ∅
    (by simp [Op.fp, Op.fps, Footprint.Disj, Footprint.empty, cb, fq, fr, fw])
    (by simp)
    (by simp [Op.fp, Op.fps, Footprint.empty, cb, fw])
    (by simp)
    sB rfl
    (by simp [runK, runKB, stall, leafT, sB, cb])
    4
  simp [runK, runKB, stall, leafT, gateTime, Op.fp, Op.fps, Footprint.empty, fq,
    sB, cb, costB] at h

end Qlin
