import Qlin.Sem

/-!
# R1: structure of the denotation

- The denotation is additive (`den_add`, `den_zero`).
- A1 lifts from leaves to every op (`den_restrict`).
- A2 lifts from leaves to every op (`den_comm`).
- Bits an op does not write keep their value on the support
  (`supp_den`): this is A3 of the plan, derived from A1.
-/

namespace Qlin

variable {D : Type*} [AddCommMonoid D]

/-- The branches of `s` with nonzero weight have every bit of `W` false.
Before any op writes a bit, the bit holds 0 (`Known` in
`src/analysis/core.rs`). -/
def Supp (W : Finset Bit) (s : State D) : Prop :=
  ∀ β, s β ≠ 0 → ∀ b ∈ W, β b = false

theorem restrict_add (c : Cond) (s t : State D) :
    restrict c (s + t) = restrict c s + restrict c t := by
  ext β; unfold restrict; by_cases h : c.eval β <;> simp [h]

theorem restrict_zero (c : Cond) : restrict c (0 : State D) = 0 := by
  ext β; unfold restrict; by_cases h : c.eval β <;> simp [h]

theorem restrict_comm (c c' : Cond) (s : State D) :
    restrict c (restrict c' s) = restrict c' (restrict c s) := by
  ext β; unfold restrict; by_cases h : c.eval β <;> by_cases h' : c'.eval β <;> simp [h, h']

/-- A state splits into the branches where `c` holds and the rest. -/
theorem restrict_split (c : Cond) (s : State D) :
    restrict c s + restrict c.not s = s := by
  ext β; unfold restrict Cond.not; by_cases h : c.eval β <;> simp [h]

theorem Footprint.Disj.symm {f g : Footprint} (h : f.Disj g) : g.Disj f := by
  obtain ⟨h1, h2, h3, h4⟩ := h
  exact ⟨h1.symm, h2.symm, h4.symm, h3.symm⟩

theorem denB_append (I : Interp D) (A B : List Op) (s : State D) :
    denB I (A ++ B) s = denB I B (denB I A s) := by
  induction A generalizing s with
  | nil => simp [denB]
  | cons o os ih => simp [denB, ih]

theorem den_add (I : Interp D) (o : Op) (s t : State D) :
    den I o (s + t) = den I o s + den I o t := by
  sorry

theorem den_zero (I : Interp D) (o : Op) : den I o 0 = 0 := by
  sorry

theorem denB_add (I : Interp D) (l : List Op) (s t : State D) :
    denB I l (s + t) = denB I l s + denB I l t := by
  sorry

theorem denB_zero (I : Interp D) (l : List Op) : denB I l 0 = 0 := by
  sorry

/-- A1 for every op: an op commutes with a condition on bits it does not
write. -/
theorem den_restrict (I : Interp D) (o : Op) (c : Cond)
    (h : Disjoint c.bits (Op.fp o).writes) (s : State D) :
    den I o (restrict c s) = restrict c (den I o s) := by
  sorry

theorem denB_restrict (I : Interp D) (l : List Op) (c : Cond)
    (h : Disjoint c.bits (Op.fps l).writes) (s : State D) :
    denB I l (restrict c s) = restrict c (denB I l s) := by
  sorry

/-- A2 for every op: ops with disjoint footprints commute. -/
theorem den_comm (I : Interp D) (o o' : Op) (h : (Op.fp o).Disj (Op.fp o'))
    (s : State D) : den I o (den I o' s) = den I o' (den I o s) := by
  sorry

/-- An op that writes no bit of `W` keeps those bits false on the
support. -/
theorem supp_den (I : Interp D) (o : Op) (W : Finset Bit)
    (h : Disjoint W (Op.fp o).writes) (s : State D) (hs : Supp W s) :
    Supp W (den I o s) := by
  sorry

theorem supp_denB (I : Interp D) (l : List Op) (W : Finset Bit)
    (h : Disjoint W (Op.fps l).writes) (s : State D) (hs : Supp W s) :
    Supp W (denB I l s) := by
  sorry

end Qlin
