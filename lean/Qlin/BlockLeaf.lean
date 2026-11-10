import Qlin.Block

/-!
# The block model: monotonicity

`hoist_block_can_delay` (Block.lean) shows that a hoisted branch can add
latency in the block model. This file builds the tools for the positive
side: the block replay is monotone in its start state, in the controller
time, and in its gate bits (`runK_mono`, `runKB_mono`).
-/

namespace Qlin

open scoped NNReal

/-- `a` is no later than `b` in the block model: the replay state is no
later, and the controller is free no later. -/
def BState.Le (a b : BState) : Prop := a.st.Le b.st ∧ a.free ≤ b.free

theorem BState.Le.refl (a : BState) : a.Le a := ⟨TState.Le.refl _, le_rfl⟩

theorem BState.Le.trans {a b c : BState} (h1 : a.Le b) (h2 : b.Le c) : a.Le c :=
  ⟨h1.1.trans h2.1, h1.2.trans h2.2⟩

/-- The gate time is monotone in the state and in the gate bits. -/
theorem gateTime_mono (C : Cost) {a b : TState} (h : a.Le b) {g1 g2 : Finset Bit}
    (hg : g1 ⊆ g2) : gateTime C a g1 ≤ gateTime C b g2 := by
  unfold gateTime
  refine Finset.sup_le fun z hz => ?_
  refine le_trans ?_ (Finset.le_sup (f := fun z => match b.measEnd z with
    | some t => t + C.tff
    | none => 0) (hg hz))
  have hz' := h.2.2.2.2 z
  cases ha : a.measEnd z with
  | none => simp
  | some t =>
    cases hb : b.measEnd z with
    | none => rw [ha, hb] at hz'; exact absurd hz' (by simp [OptLe])
    | some t' =>
      rw [ha, hb] at hz'
      simp only [OptLe] at hz'
      simpa using hz'

theorem stall_mono (C : BCost) (f : Footprint) (bits : Finset Bit) {g1 g2 : Finset Bit}
    (hg : g1 ⊆ g2) (n : ℕ) {a b : BState} (h : a.Le b) :
    (stall C f bits g1 n a).Le (stall C f bits g2 n b) := by
  have ht : max (max (gateTime C.base a.st bits) (gateTime C.base a.st g1)) a.free + C.tb * n ≤
      max (max (gateTime C.base b.st bits) (gateTime C.base b.st g2)) b.free + C.tb * n := by
    gcongr
    · exact gateTime_mono C.base h.1 (Finset.Subset.refl _)
    · exact gateTime_mono C.base h.1 hg
    · exact h.2
  refine ⟨⟨h.1.1, h.1.2.1, h.1.2.2.1, fun q => ?_, h.1.2.2.2.2⟩, ht⟩
  simp only [stall]
  split_ifs
  · exact max_le_max (h.1.2.2.2.1 q) ht
  · exact h.1.2.2.2.1 q

theorem loopK_mono (body1 body2 : Finset Bit → BState → BState) (stl1 stl2 : BState → BState)
    (c : Cond) (g1 g2 : Finset Bit) (hg : g1 ⊆ g2)
    (hbody : ∀ g g' a b, g ⊆ g' → BState.Le a b → (body1 g a).Le (body2 g' b))
    (hstl : ∀ a b, BState.Le a b → (stl1 a).Le (stl2 b)) :
    ∀ (k : ℕ) (first : Bool) (a b : BState), a.Le b →
      (loopK body1 stl1 c g1 k first a).Le (loopK body2 stl2 c g2 k first b)
  | 0, _, a, b, hab => by
    simp only [loopK]
    exact ⟨⟨hab.1.1, hab.1.2.1, rfl, hab.1.2.2.2.1, hab.1.2.2.2.2⟩, hab.2⟩
  | k + 1, first, a, b, hab => by
    have hg' : (if first = true then g1 else g1 ∪ c.bits) ⊆
        (if first = true then g2 else g2 ∪ c.bits) := by
      cases first
      · exact Finset.union_subset_union hg (Finset.Subset.refl _)
      · exact hg
    have h1 := hbody _ _ a b hg' hab
    simp only [loopK]
    generalize body1 (if first = true then g1 else g1 ∪ c.bits) a = x at h1 ⊢
    generalize body2 (if first = true then g2 else g2 ∪ c.bits) b = y at h1 ⊢
    have h2 : (if x.st.stopped = true then x else stl1 x).Le
        (if y.st.stopped = true then y else stl2 y) := by
      rw [h1.1.2.2.1]
      split_ifs
      · exact h1
      · exact hstl x y h1
    generalize (if x.st.stopped = true then x else stl1 x) = x' at h2 ⊢
    generalize (if y.st.stopped = true then y else stl2 y) = y' at h2 ⊢
    rw [h2.1.2.2.1, h2.1.1]
    split_ifs
    · exact h2
    · exact loopK_mono body1 body2 stl1 stl2 c g1 g2 hg hbody hstl k false x' y' h2

mutual
/-- The block replay is monotone in the start state and the gate bits. -/
theorem runK_mono (C : BCost) (R : Record) : ∀ (o : Op) (g1 g2 : Finset Bit), g1 ⊆ g2 →
    ∀ a b : BState, a.Le b → (runK C R o g1 a).Le (runK C R o g2 b)
  | .leaf i f, g1, g2, hg, a, b, hab => by
    simp only [runK]
    have h := run_mono C.base R (.leaf i f) g1 g2 hg a.st b.st hab.1
    simp only [run] at h
    exact ⟨h, hab.2⟩
  | .ite c A B, g1, g2, hg, a, b, hab => by
    have hst := stall_mono C (Op.fp (.ite c A B)) c.bits hg 1 hab
    have hg' : g1 ∪ c.bits ⊆ g2 ∪ c.bits := Finset.union_subset_union hg (Finset.Subset.refl _)
    simp only [runK]
    rw [hab.1.2.2.1, hab.1.1]
    split_ifs
    · exact hab
    · exact runKB_mono C R A _ _ hg' _ _ hst
    · exact runKB_mono C R B _ _ hg' _ _ hst
  | .loop K body c, g1, g2, hg, a, b, hab => by
    simp only [runK]
    rw [hab.1.2.2.1]
    split_ifs
    · exact hab
    · exact loopK_mono _ _ _ _ c g1 g2 hg
        (fun g g' a' b' h1 h2 => runKB_mono C R body g g' h1 a' b' h2)
        (fun a' b' h => stall_mono C _ c.bits hg 1 h) K true a b hab
  | .switch G cs dflt, g1, g2, hg, a, b, hab => by
    have hg' : g1 ∪ G ⊆ g2 ∪ G := Finset.union_subset_union hg (Finset.Subset.refl _)
    simp only [runK]
    rw [hab.1.2.2.1, hab.1.1]
    split_ifs
    · exact hab
    · exact runKCases_mono C R G cs dflt _ _ hg'
        (fun a' b' h => runKB_mono C R dflt _ _ hg' a' b' h) _ _ (stall_mono C _ G hg _ hab)

theorem runKB_mono (C : BCost) (R : Record) : ∀ (l : List Op) (g1 g2 : Finset Bit), g1 ⊆ g2 →
    ∀ a b : BState, a.Le b → (runKB C R l g1 a).Le (runKB C R l g2 b)
  | [], _, _, _, a, b, hab => by simp only [runKB]; exact hab
  | o :: os, g1, g2, hg, a, b, hab => by
    simp only [runKB]
    exact runKB_mono C R os g1 g2 hg _ _ (runK_mono C R o g1 g2 hg a b hab)

theorem runKCases_mono (C : BCost) (R : Record) (G : Finset Bit) :
    ∀ (cs : List (Assign × List Op)) (dflt : List Op) (g1 g2 : Finset Bit), g1 ⊆ g2 →
    (∀ a b : BState, a.Le b → (runKB C R dflt g1 a).Le (runKB C R dflt g2 b)) →
    ∀ a b : BState, a.Le b →
      (runKCases C R G cs dflt g1 a).Le (runKCases C R G cs dflt g2 b)
  | [], dflt, g1, g2, _, hd, a, b, hab => by
    simp only [runKCases]
    exact hd a b hab
  | (v, blk) :: cs, dflt, g1, g2, hg, hd, a, b, hab => by
    simp only [runKCases]
    rw [hab.1.1]
    split_ifs
    · exact runKB_mono C R blk g1 g2 hg a b hab
    · exact runKCases_mono C R G cs dflt g1 g2 hg hd a b hab
end

end Qlin
