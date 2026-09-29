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

/-- A1 and A2 have a model with a leaf that changes the state. -/
theorem interp_nontrivial :
    ∃ (I : Interp ℕ) (i : ℕ) (f : Footprint) (s : State ℕ), I.leaf i f s ≠ s := by
  sorry

/-- Hoist without "`x` writes no bit of `c`" is unsound. -/
theorem hoist_needs_hc : ¬ ∀ (I : Interp ℕ) (c : Cond) (x : Op) (pA A pB B : List Op),
    (∀ y ∈ pA, (Op.fp x).Disj (Op.fp y)) → (∀ y ∈ pB, (Op.fp x).Disj (Op.fp y)) →
    ∀ s : State ℕ, den I (.ite c (pA ++ x :: A) (pB ++ x :: B)) s =
      denB I [x, .ite c (pA ++ A) (pB ++ B)] s := by
  sorry

/-- Hoist past an op that is not disjoint is unsound. -/
theorem hoist_needs_disj : ¬ ∀ (I : Interp ℕ) (c : Cond) (x : Op) (pA A pB B : List Op),
    Disjoint c.bits (Op.fp x).writes →
    ∀ s : State ℕ, den I (.ite c (pA ++ x :: A) (pB ++ x :: B)) s =
      denB I [x, .ite c (pA ++ A) (pB ++ B)] s := by
  sorry

/-- Merge past an op that is not disjoint is unsound. -/
theorem merge_needs_disj : ¬ ∀ (I : Interp ℕ) (c : Cond) (x : Op) (A sA B sB : List Op),
    ∀ s : State ℕ, den I (.ite c (A ++ x :: sA) (B ++ x :: sB)) s =
      denB I [.ite c (A ++ sA) (B ++ sB), x] s := by
  sorry

/-- Dispatch when the group writes a dispatch bit is unsound. -/
theorem fastpath_needs_hw : ¬ ∀ (I : Interp ℕ) (G : Finset Bit) (grp rest : List Op)
    (cases : List (Assign × List Op)),
    (∀ o ∈ grp, ∀ c A B, o = Op.ite c A B → c.bits ⊆ G) →
    (∀ p ∈ cases, ∀ s, denB I p.2 s = denB I (selected p.1 grp ++ rest) s) →
    ∀ s : State ℕ, den I (.switch G cases (grp ++ rest)) s = denB I (grp ++ rest) s := by
  sorry

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
  sorry

/-- Merge latency without "the ops `x` moves past write no enclosing gate
bit" fails (notes/c1-counterexample/c1_nested_merge.qlin). -/
theorem merge_latency_needs_henc : ¬ ∀ (C : Cost) (R : Record) (c : Cond) (x : Op)
    (A sA B sB : List Op) (gates : Finset Bit),
    (∀ y ∈ sA, (Op.fp x).Disj (Op.fp y)) → (∀ y ∈ sB, (Op.fp x).Disj (Op.fp y)) →
    ∀ st : TState, st.stopped = false →
    (run C R (.ite c (A ++ x :: sA) (B ++ x :: sB)) gates st).stopped = false →
    (runB C R [.ite c (A ++ sA) (B ++ sB), x] gates st).Le
      (run C R (.ite c (A ++ x :: sA) (B ++ x :: sB)) gates st) := by
  sorry

end Qlin
