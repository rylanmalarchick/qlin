import Qlin.Structure

/-!
# R3b: the Pauli sink is sound

`src/transform/sink.rs` moves a Pauli If forward past an op that either
is disjoint from it (`sink_past_disjoint`) or is a Clifford gate on its
qubits (`sink_past_clifford`). In the second case each arm is replaced
by its conjugate. The conjugation facts come from `PauliTable.lean`:
there `C * P = φ • P' * C` with `φ = ±1`, so as channels the arm `P`
then `C` equals `C` then `P'`. That last step (Kraus operators equal up
to a global phase give the same channel) is hand-checked.
-/

namespace Qlin

variable {D : Type*} [AddCommMonoid D]

/-- Sink past a disjoint op. -/
theorem sink_past_disjoint (I : Interp D) (o y : Op) (h : (Op.fp o).Disj (Op.fp y))
    (s : State D) : denB I [o, y] s = denB I [y, o] s := by
  simp only [denB]
  exact (den_comm I o y h s).symm

/-- Sink past a Clifford op `C`: each arm followed by `C` equals `C`
followed by the conjugated arm. `C` writes no bit of the condition. -/
theorem sink_past_clifford (I : Interp D) (c : Cond) (PA PB PA' PB' : List Op) (C : Op)
    (hc : Disjoint c.bits (Op.fp C).writes)
    (hA : ∀ s, denB I (PA ++ [C]) s = denB I (C :: PA') s)
    (hB : ∀ s, denB I (PB ++ [C]) s = denB I (C :: PB') s) (s : State D) :
    denB I [.ite c PA PB, C] s = denB I [C, .ite c PA' PB'] s := by
  have hA' := hA (restrict c s)
  have hB' := hB (restrict c.not s)
  simp only [denB_append, denB] at hA' hB'
  simp only [denB, den, den_add, hA', hB']
  rw [den_restrict I C c hc, den_restrict I C c.not hc]

end Qlin
