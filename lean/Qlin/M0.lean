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

private theorem denB_comm_of_forall (I : Interp D) (g : State D → State D) (l : List Op)
    (h : ∀ y ∈ l, ∀ s, g (den I y s) = den I y (g s)) (s : State D) :
    g (denB I l s) = denB I l (g s) := by
  induction l generalizing s with
  | nil => simp only [denB]
  | cons o os ih =>
    simp only [denB]
    rw [ih (fun y hy => h y (List.mem_cons_of_mem _ hy)), h o List.mem_cons_self]

/-- Fold to the then arm: `c` is true whenever the known bits `W` are
false, and `W` is false on the support. -/
theorem fold_true (I : Interp D) (c : Cond) (A B : List Op) (W : Finset Bit)
    (hc : ∀ β : Assign, (∀ b ∈ W, β b = false) → c.eval β = true)
    (s : State D) (hs : Supp W s) :
    den I (.ite c A B) s = denB I A s := by
  have key : ∀ β, s β ≠ 0 → c.eval β = true := fun β hβ => hc β (hs β hβ)
  have h1 : restrict c s = s := by
    funext β
    unfold restrict
    by_cases hβ : s β = 0
    · split_ifs <;> simp [hβ]
    · have := key β hβ
      simp [this]
  have h2 : restrict c.not s = 0 := by
    funext β
    unfold restrict Cond.not
    by_cases hβ : s β = 0
    · split_ifs <;> simp [hβ]
    · have := key β hβ
      simp [this]
  simp only [den, h1, h2, denB_zero, add_zero]

/-- Fold to the else arm. -/
theorem fold_false (I : Interp D) (c : Cond) (A B : List Op) (W : Finset Bit)
    (hc : ∀ β : Assign, (∀ b ∈ W, β b = false) → c.eval β = false)
    (s : State D) (hs : Supp W s) :
    den I (.ite c A B) s = denB I B s := by
  have key : ∀ β, s β ≠ 0 → c.eval β = false := fun β hβ => hc β (hs β hβ)
  have h1 : restrict c s = 0 := by
    funext β
    unfold restrict
    by_cases hβ : s β = 0
    · split_ifs <;> simp [hβ]
    · have := key β hβ
      simp [this]
  have h2 : restrict c.not s = s := by
    funext β
    unfold restrict Cond.not
    by_cases hβ : s β = 0
    · split_ifs <;> simp [hβ]
    · have := key β hβ
      simp [this]
  simp only [den, h1, h2, denB_zero, zero_add]

/-- Hoist: `x` commutes with the ops before it in each arm and writes no
bit of `c`. -/
theorem hoist_sound (I : Interp D) (c : Cond) (x : Op) (pA A pB B : List Op)
    (hA : ∀ y ∈ pA, (Op.fp x).Disj (Op.fp y))
    (hB : ∀ y ∈ pB, (Op.fp x).Disj (Op.fp y))
    (hc : Disjoint c.bits (Op.fp x).writes) (s : State D) :
    den I (.ite c (pA ++ x :: A) (pB ++ x :: B)) s =
      denB I [x, .ite c (pA ++ A) (pB ++ B)] s := by
  have cA : ∀ t, den I x (denB I pA t) = denB I pA (den I x t) :=
    denB_comm_of_forall I (den I x) pA (fun y hy t => den_comm I x y (hA y hy) t)
  have cB : ∀ t, den I x (denB I pB t) = denB I pB (den I x t) :=
    denB_comm_of_forall I (den I x) pB (fun y hy t => den_comm I x y (hB y hy) t)
  simp only [den, denB_append, denB, cA, cB]
  rw [den_restrict I x c hc, den_restrict I x c.not hc]

/-- Merge: `x` commutes with the ops after it in each arm. -/
theorem merge_sound (I : Interp D) (c : Cond) (x : Op) (A sA B sB : List Op)
    (hA : ∀ y ∈ sA, (Op.fp x).Disj (Op.fp y))
    (hB : ∀ y ∈ sB, (Op.fp x).Disj (Op.fp y)) (s : State D) :
    den I (.ite c (A ++ x :: sA) (B ++ x :: sB)) s =
      denB I [.ite c (A ++ sA) (B ++ sB), x] s := by
  have cA : ∀ t, den I x (denB I sA t) = denB I sA (den I x t) :=
    denB_comm_of_forall I (den I x) sA (fun y hy t => den_comm I x y (hA y hy) t)
  have cB : ∀ t, den I x (denB I sB t) = denB I sB (den I x t) :=
    denB_comm_of_forall I (den I x) sB (fun y hy t => den_comm I x y (hB y hy) t)
  simp only [den, denB_append, denB, ← cA, ← cB, den_add]

/-- Unroll: peel the first iteration of a loop. -/
theorem unroll_sound (I : Interp D) (K : ℕ) (body : List Op) (c : Cond)
    (s : State D) :
    den I (.loop (K + 1) body c) s =
      denB I (body ++ [.ite c [] [.loop K body c]]) s := by
  simp only [den, denB_append, denB, loopIter]

/-- Congruence: equal blocks give equal Ifs. -/
theorem ite_congr (I : Interp D) (c : Cond) (A A' B B' : List Op)
    (hA : ∀ s, denB I A s = denB I A' s) (hB : ∀ s, denB I B s = denB I B' s)
    (s : State D) : den I (.ite c A B) s = den I (.ite c A' B') s := by
  simp only [den, hA, hB]

/-- Congruence: an equal middle block gives an equal block. -/
theorem denB_congr (I : Interp D) (P Q Q' R : List Op)
    (hQ : ∀ s, denB I Q s = denB I Q' s) (s : State D) :
    denB I (P ++ Q ++ R) s = denB I (P ++ Q' ++ R) s := by
  simp only [denB_append, hQ]

end Qlin
