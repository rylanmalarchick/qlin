import Qlin.Structure

/-!
# R2: the M0 rules are sound

Each rule is one step of `src/transform/m0.rs`, with the side conditions
of `match_arms` in `src/analysis/core.rs`:
- fold: a condition that is constant on the known bits selects its arm.
- hoist: an op that commutes to the front of both arms, and writes no
  bit of the condition, moves before the If.
- merge: an op that commutes to the back of both arms moves after the If.
- unroll: a loop runs its first iteration unconditionally.
Congruence lemmas let a rule apply inside any arm or block.
-/

namespace Qlin

variable {D : Type*} [AddCommMonoid D]

/-- Fold to the then arm: `c` is true whenever the known bits `W` are
false, and `W` is false on the support. -/
theorem fold_true (I : Interp D) (c : Cond) (A B : List Op) (W : Finset Bit)
    (hc : ∀ β : Assign, (∀ b ∈ W, β b = false) → c.eval β = true)
    (s : State D) (hs : Supp W s) :
    den I (.ite c A B) s = denB I A s := by
  sorry

/-- Fold to the else arm. -/
theorem fold_false (I : Interp D) (c : Cond) (A B : List Op) (W : Finset Bit)
    (hc : ∀ β : Assign, (∀ b ∈ W, β b = false) → c.eval β = false)
    (s : State D) (hs : Supp W s) :
    den I (.ite c A B) s = denB I B s := by
  sorry

/-- Hoist: `x` commutes with the ops before it in each arm and writes no
bit of `c`. -/
theorem hoist_sound (I : Interp D) (c : Cond) (x : Op) (pA A pB B : List Op)
    (hA : ∀ y ∈ pA, (Op.fp x).Disj (Op.fp y))
    (hB : ∀ y ∈ pB, (Op.fp x).Disj (Op.fp y))
    (hc : Disjoint c.bits (Op.fp x).writes) (s : State D) :
    den I (.ite c (pA ++ x :: A) (pB ++ x :: B)) s =
      denB I [x, .ite c (pA ++ A) (pB ++ B)] s := by
  sorry

/-- Merge: `x` commutes with the ops after it in each arm. -/
theorem merge_sound (I : Interp D) (c : Cond) (x : Op) (A sA B sB : List Op)
    (hA : ∀ y ∈ sA, (Op.fp x).Disj (Op.fp y))
    (hB : ∀ y ∈ sB, (Op.fp x).Disj (Op.fp y)) (s : State D) :
    den I (.ite c (A ++ x :: sA) (B ++ x :: sB)) s =
      denB I [.ite c (A ++ sA) (B ++ sB), x] s := by
  sorry

/-- Unroll: peel the first iteration of a loop. -/
theorem unroll_sound (I : Interp D) (K : ℕ) (body : List Op) (c : Cond)
    (s : State D) :
    den I (.loop (K + 1) body c) s =
      denB I (body ++ [.ite c [] [.loop K body c]]) s := by
  sorry

/-- Congruence: equal blocks give equal Ifs. -/
theorem ite_congr (I : Interp D) (c : Cond) (A A' B B' : List Op)
    (hA : ∀ s, denB I A s = denB I A' s) (hB : ∀ s, denB I B s = denB I B' s)
    (s : State D) : den I (.ite c A B) s = den I (.ite c A' B') s := by
  sorry

/-- Congruence: an equal middle block gives an equal block. -/
theorem denB_congr (I : Interp D) (P Q Q' R : List Op)
    (hQ : ∀ s, denB I Q s = denB I Q' s) (s : State D) :
    denB I (P ++ Q ++ R) s = denB I (P ++ Q' ++ R) s := by
  sorry

end Qlin
