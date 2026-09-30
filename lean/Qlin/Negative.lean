import Qlin.M0
import Qlin.FastPath
import Qlin.Latency

/-!
# Negative tests: each side condition is needed

Each theorem refutes a rule with one side condition dropped, by a
concrete counterexample. `interp_nontrivial` shows the axioms A1 and A2
have a model in which a leaf changes the state, so the soundness
theorems are not vacuous.
-/

namespace Qlin

/-- Set bit 0 to true, moving the weight of `β[0 := false]` onto `β[0 := true]`. -/
private def set0Fn (s : State ℕ) : State ℕ :=
  fun β => if β 0 = true then s (Function.update β 0 false) + s β else 0

/-- Leaf `i` with footprint `f`: set bit 0 if `f` writes it, then double if `i = 1`. -/
private def leafFn (i : ℕ) (f : Footprint) (s : State ℕ) : State ℕ :=
  fun β => (if i = 1 then 2 else 1) * (if 0 ∈ f.writes then set0Fn s β else s β)

private def leafHom (i : ℕ) (f : Footprint) : State ℕ →+ State ℕ where
  toFun := leafFn i f
  map_zero' := by funext β; simp [leafFn, set0Fn]
  map_add' s t := by
    funext β
    simp only [leafFn, set0Fn, Pi.add_apply]
    split_ifs <;> ring

private def interpN : Interp ℕ where
  leaf := leafHom
  local_ i f c hc s := by
    funext β
    simp only [leafHom, AddMonoidHom.coe_mk, ZeroHom.coe_mk, leafFn, set0Fn, restrict]
    by_cases h0 : 0 ∈ f.writes
    · have h0c : (0 : Bit) ∉ c.bits := fun h => Finset.disjoint_left.1 hc h h0
      have hdep : c.eval (Function.update β 0 false) = c.eval β :=
        c.dep _ _ fun b hb => by
          rw [Function.update_of_ne (by rintro rfl; exact h0c hb)]
      simp only [h0, if_true, hdep]
      split_ifs <;> simp
    · simp only [h0, if_false]
      split_ifs <;> simp
  comm i f j g hd s := by
    funext β
    have hfg : ¬ (0 ∈ f.writes ∧ 0 ∈ g.writes) := fun ⟨h1, h2⟩ =>
      Finset.disjoint_left.1 hd.2.1 h1 h2
    simp only [leafHom, AddMonoidHom.coe_mk, ZeroHom.coe_mk, leafFn, set0Fn]
    by_cases hf : 0 ∈ f.writes <;> by_cases hg : 0 ∈ g.writes
    · exact absurd ⟨hf, hg⟩ hfg
    all_goals simp only [hf, hg, if_true, if_false]
    all_goals split_ifs <;> ring

private def c0 : Cond := ⟨fun β => β 0, {0}, fun _ _ h => h 0 (Finset.mem_singleton_self 0)⟩
private def cT : Cond := ⟨fun _ => true, ∅, fun _ _ _ => rfl⟩
private def xSet : Op := .leaf 0 ⟨∅, ∅, {0}⟩
private def xDbl : Op := .leaf 1 ⟨∅, ∅, ∅⟩
private def yIte : Op := .ite c0 [xDbl] []
private def allT : Assign := fun _ => true
private def one : State ℕ := fun _ => 1

private def costN : Cost := ⟨fun _ _ => 1, 1⟩
private def recN : Record := fun _ _ => false
private def st0 : TState := ⟨fun _ => 0, fun _ => none, fun _ => false, fun _ => 0, false⟩

/-- A1 and A2 have a model with a leaf that changes the state. -/
theorem interp_nontrivial :
    ∃ (I : Interp ℕ) (i : ℕ) (f : Footprint) (s : State ℕ), I.leaf i f s ≠ s := by
  refine ⟨interpN, 1, ⟨∅, ∅, ∅⟩, one, fun h => ?_⟩
  have := congrFun h allT
  simp [interpN, leafHom, leafFn, one] at this

/-- Hoist without "`x` writes no bit of `c`" is unsound. -/
theorem hoist_needs_hc : ¬ ∀ (I : Interp ℕ) (c : Cond) (x : Op) (pA A pB B : List Op),
    (∀ y ∈ pA, (Op.fp x).Disj (Op.fp y)) → (∀ y ∈ pB, (Op.fp x).Disj (Op.fp y)) →
    ∀ s : State ℕ, den I (.ite c (pA ++ x :: A) (pB ++ x :: B)) s =
      denB I [x, .ite c (pA ++ A) (pB ++ B)] s := by
  intro H
  have h := congrFun (H interpN c0 xSet [] [] [] [xDbl] (by simp) (by simp) one) allT
  simp [den, denB, interpN, leafHom, leafFn, set0Fn, restrict, c0, Cond.not, xSet, xDbl,
    one, allT] at h

/-- Hoist past an op that is not disjoint is unsound. -/
theorem hoist_needs_disj : ¬ ∀ (I : Interp ℕ) (c : Cond) (x : Op) (pA A pB B : List Op),
    Disjoint c.bits (Op.fp x).writes →
    ∀ s : State ℕ, den I (.ite c (pA ++ x :: A) (pB ++ x :: B)) s =
      denB I [x, .ite c (pA ++ A) (pB ++ B)] s := by
  intro H
  have h := congrFun (H interpN cT xSet [yIte] [] [] [] (by simp [cT]) one) allT
  simp [den, denB, interpN, leafHom, leafFn, set0Fn, restrict, c0, cT, Cond.not, xSet, xDbl,
    yIte, one, allT] at h

/-- Merge past an op that is not disjoint is unsound. -/
theorem merge_needs_disj : ¬ ∀ (I : Interp ℕ) (c : Cond) (x : Op) (A sA B sB : List Op),
    ∀ s : State ℕ, den I (.ite c (A ++ x :: sA) (B ++ x :: sB)) s =
      denB I [.ite c (A ++ sA) (B ++ sB), x] s := by
  intro H
  have h := congrFun (H interpN cT xSet [] [yIte] [] [] one) allT
  simp [den, denB, interpN, leafHom, leafFn, set0Fn, restrict, c0, cT, Cond.not, xSet, xDbl,
    yIte, one, allT] at h

/-- Dispatch when the group writes a dispatch bit is unsound. -/
theorem fastpath_needs_hw : ¬ ∀ (I : Interp ℕ) (G : Finset Bit) (grp rest : List Op)
    (cases : List (Assign × List Op)),
    (∀ o ∈ grp, ∀ c A B, o = Op.ite c A B → c.bits ⊆ G) →
    (∀ p ∈ cases, ∀ s, denB I p.2 s = denB I (selected p.1 grp ++ rest) s) →
    ∀ s : State ℕ, den I (.switch G cases (grp ++ rest)) s = denB I (grp ++ rest) s := by
  intro H
  have hbits : ∀ o ∈ [xSet, yIte], ∀ c A B, o = Op.ite c A B → c.bits ⊆ {0} := by
    intro o ho c A B hoc
    simp only [List.mem_cons, List.not_mem_nil, or_false] at ho
    rcases ho with rfl | rfl
    · simp [xSet] at hoc
    · simp only [yIte, Op.ite.injEq] at hoc
      rw [← hoc.1]; simp [c0]
  have hcase : ∀ p ∈ [((fun _ => false : Assign), [xSet])], ∀ s,
      denB interpN p.2 s = denB interpN (selected p.1 [xSet, yIte] ++ []) s := by
    intro p hp s
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hp
    subst hp
    simp [selected, sel, xSet, yIte, c0]
  have h := congrFun (H interpN {0} [xSet, yIte] [] _ hbits hcase one) allT
  simp [den, denB, denCases, interpN, leafHom, leafFn, set0Fn, restrict, c0, Cond.not,
    Cond.matches, xSet, xDbl, yIte, one, allT] at h

/-- Hoist latency without "`x` writes no enclosing gate bit" fails
(notes/c1-counterexample/c1_nested_hoist.qlin). -/
theorem hoist_latency_needs_henc : ¬ ∀ (C : Cost) (R : Record) (c : Cond) (x : Op)
    (pA A pB B : List Op) (gates : Finset Bit),
    (∀ y ∈ pA, (Op.fp x).Disj (Op.fp y)) → (∀ y ∈ pB, (Op.fp x).Disj (Op.fp y)) →
    Disjoint c.bits (Op.fp x).writes →
    ∀ st : TState, st.stopped = false →
    (run C R (.ite c (pA ++ x :: A) (pB ++ x :: B)) gates st).stopped = false →
    (runB C R [x, .ite c (pA ++ A) (pB ++ B)] gates st).Le
      (run C R (.ite c (pA ++ x :: A) (pB ++ x :: B)) gates st) := by
  intro H
  have h := H costN recN cT (.leaf 0 ⟨{0}, ∅, {0}⟩) [.leaf 1 ⟨{1}, ∅, ∅⟩] [] [] [] {0}
    (by simp [Op.fp, Footprint.Disj]) (by simp) (by simp [cT]) st0 rfl
    (by simp [run, runB, leafT, st0, cT])
  have h4 := h.2.2.2.1 1
  simp [run, runB, leafT, gateTime, st0, cT, costN] at h4

/-- Merge latency without "the ops `x` moves past write no enclosing gate
bit" fails (notes/c1-counterexample/c1_nested_merge.qlin). -/
theorem merge_latency_needs_henc : ¬ ∀ (C : Cost) (R : Record) (c : Cond) (x : Op)
    (A sA B sB : List Op) (gates : Finset Bit),
    (∀ y ∈ sA, (Op.fp x).Disj (Op.fp y)) → (∀ y ∈ sB, (Op.fp x).Disj (Op.fp y)) →
    ∀ st : TState, st.stopped = false →
    (run C R (.ite c (A ++ x :: sA) (B ++ x :: sB)) gates st).stopped = false →
    (runB C R [.ite c (A ++ sA) (B ++ sB), x] gates st).Le
      (run C R (.ite c (A ++ x :: sA) (B ++ x :: sB)) gates st) := by
  intro H
  have h := H costN recN cT (.leaf 0 ⟨{0}, ∅, ∅⟩) [] [.leaf 1 ⟨{1}, ∅, {0}⟩] [] [] {0}
    (by simp [Op.fp, Footprint.Disj]) (by simp) st0 rfl
    (by simp [run, runB, leafT, st0, cT])
  have h4 := h.2.2.2.1 0
  simp [run, runB, leafT, gateTime, st0, cT, costN] at h4

end Qlin
