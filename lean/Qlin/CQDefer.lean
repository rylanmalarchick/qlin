import Qlin.CQGates

/-!
# The defer rule in the cq model (direct form, one control bit)

`src/transform/defer.rs` replaces a classically controlled If by a
coherently controlled gate. In the direct form the control is the
measured qubit itself, and the measure moves after the controlled gate:

  `measure q -> b ; if b = v { U on T }`  =  `C_v-U (q; T) ; measure q -> b`

for `q ∉ T`. `defer_cq` proves this for any operator `U` on the qubits
`T`. Moving the measure further, past ops that touch neither `q` nor `b`,
is A2 (`den_comm`).

Not covered here (simulation-checked only): the copy form (a fresh
ancilla), conditions with several bits, and XOR conditions.
-/

namespace Qlin.CQ

open Matrix

noncomputable section

variable {n : ℕ}

instance (T : Finset Qubit) (x y : Basis n) : Decidable (AgreeOn T x y) := by
  unfold AgreeOn; infer_instance

/-- The identity on the qubits `T`, before the lift. -/
def idOn (T : Finset Qubit) : Mat n := fun x y => if AgreeOn T x y then 1 else 0

/-- `U` on `T` when qubit `q` is `v`, else the identity, before the lift
on `insert q T`. -/
def ctrl (q : Fin n) (v : Bool) (T : Finset Qubit) (U : Mat n) : Mat n :=
  fun x y => if x q = y q then (if x q = v then U x y else idOn T x y) else 0

theorem ctrl_local {q : Fin n} {v : Bool} {T : Finset Qubit} {U : Mat n} (hU : Local T U) :
    Local (insert (q : ℕ) T) (ctrl q v T U) := by
  intro x y x' y' hx hy
  have hxq : x q = x' q := hx q (Finset.mem_insert_self _ _)
  have hyq : y q = y' q := hy q (Finset.mem_insert_self _ _)
  have hxT : AgreeOn T x x' := fun i hi => hx i (Finset.mem_insert_of_mem hi)
  have hyT : AgreeOn T y y' := fun i hi => hy i (Finset.mem_insert_of_mem hi)
  have hid : AgreeOn T x y ↔ AgreeOn T x' y' :=
    ⟨fun h i hi => (hxT i hi).symm.trans ((h i hi).trans (hyT i hi)),
      fun h i hi => (hxT i hi).trans ((h i hi).trans (hyT i hi).symm)⟩
  simp only [ctrl, idOn, hxq, hyq, hU x y x' y' hxT hyT, hid]

/-- The projector `|w⟩⟨w|` on qubit `q`, lifted, entry by entry. -/
theorem lift_proj_apply (q : Fin n) (w : Bool) (x y : Basis n) :
    lift {(q : ℕ)} (proj (n := n) q w) x y = if x = y ∧ x q = w then 1 else 0 := by
  simp only [lift, proj, qbit_fin]
  by_cases hxy : x = y
  · subst hxy
    simp [show AgreeOff {(q : ℕ)} x x from fun _ _ => rfl]
  · have : ¬ (AgreeOff {(q : ℕ)} x y ∧ x q = w ∧ y q = w) := fun ⟨h, h1, h2⟩ =>
      hxy (funext fun i => by
        by_cases hi : i = q
        · subst hi; rw [h1, h2]
        · exact h i (by simpa using fin_ne hi))
    by_cases hoff : AgreeOff {(q : ℕ)} x y
    · rw [if_pos hoff, if_neg (fun h => this ⟨hoff, h⟩), if_neg (fun h => hxy h.1)]
    · rw [if_neg hoff, if_neg (fun h => hxy h.1)]

theorem lift_proj_mul (q : Fin n) (w : Bool) (M : Mat n) (x z : Basis n) :
    (lift {(q : ℕ)} (proj (n := n) q w) * M) x z = if x q = w then M x z else 0 := by
  rw [Matrix.mul_apply, Finset.sum_eq_single x]
  · simp [lift_proj_apply]
  · intro y _ hy
    rw [lift_proj_apply, if_neg (fun h => hy h.1.symm), zero_mul]
  · intro h
    exact absurd (Finset.mem_univ _) h

theorem mul_lift_proj (q : Fin n) (w : Bool) (M : Mat n) (x z : Basis n) :
    (M * lift {(q : ℕ)} (proj (n := n) q w)) x z = if z q = w then M x z else 0 := by
  rw [Matrix.mul_apply, Finset.sum_eq_single z]
  · simp [lift_proj_apply]
  · intro y _ hy
    rw [lift_proj_apply, if_neg (fun h => hy h.1), mul_zero]
  · intro h
    exact absurd (Finset.mem_univ _) h

/-- For `q ∉ T`: agreeing off `T` is agreeing off `insert q T` and on `q`. -/
theorem agreeOff_insert {q : Fin n} {T : Finset Qubit} (hq : (q : ℕ) ∉ T) (x z : Basis n) :
    AgreeOff T x z ↔ AgreeOff (insert (q : ℕ) T) x z ∧ x q = z q := by
  constructor
  · intro h
    exact ⟨fun i hi => h i fun hT => hi (Finset.mem_insert_of_mem hT), h q hq⟩
  · rintro ⟨h, hqq⟩ i hi
    by_cases hiq : i = q
    · subst hiq; exact hqq
    · exact h i (by simp [fin_ne hiq, hi])

/-- The projector on the control value `w` times the controlled gate. -/
theorem proj_ctrl {q : Fin n} {v w : Bool} {T : Finset Qubit} {U : Mat n} (hq : (q : ℕ) ∉ T) :
    lift {(q : ℕ)} (proj (n := n) q w) * lift (insert (q : ℕ) T) (ctrl q v T U) =
      if w = v then lift T U * lift {(q : ℕ)} (proj (n := n) q w)
      else lift {(q : ℕ)} (proj (n := n) q w) := by
  ext x z
  rw [lift_proj_mul]
  by_cases hwv : w = v
  · subst hwv
    rw [if_pos rfl, mul_lift_proj]
    simp only [lift, ctrl, agreeOff_insert hq x z]
    by_cases hx : x q = w <;> by_cases hz : z q = w <;>
      by_cases ho : AgreeOff (insert (q : ℕ) T) x z
    all_goals simp_all [eq_comm]
  · rw [if_neg hwv, lift_proj_apply]
    by_cases hx : x q = w
    · rw [if_pos hx]
      simp only [lift, ctrl, idOn]
      have hxv : ¬ x q = v := fun h => hwv (hx.symm.trans h)
      by_cases hxz : x = z
      · subst hxz
        simp [hx, AgreeOff, AgreeOn]
        exact fun h => absurd h hwv
      · have hne : ¬ (AgreeOff (insert (q : ℕ) T) x z ∧ x q = z q ∧ AgreeOn T x z) :=
          fun ⟨h1, h2, h3⟩ => hxz (funext fun i => by
            by_cases hiq : i = q
            · subst hiq; exact h2
            · by_cases hiT : (i : ℕ) ∈ T
              · exact h3 i hiT
              · exact h1 i (by simp [fin_ne hiq, hiT]))
        rw [if_neg (show ¬ (x = z ∧ x q = w) from fun h => hxz h.1)]
        by_cases h1 : AgreeOff (insert (q : ℕ) T) x z
        · rw [if_pos h1]
          by_cases h2 : x q = z q
          · rw [if_pos h2, if_neg hxv, if_neg (fun h3 => hne ⟨h1, h2, h3⟩)]
          · rw [if_neg h2]
        · rw [if_neg h1]
    · rw [if_neg hx, if_neg (fun h => hx h.2)]

/-- The defer step on matrices: measure-projector after the controlled
gate equals the gate `U` after the projector, on the control value `v`. -/
theorem chan_proj_ctrl {q : Fin n} {v w : Bool} {T : Finset Qubit} {U : Mat n}
    (hq : (q : ℕ) ∉ T) (ρ : Mat n) :
    chan {(q : ℕ)} [proj q w] (chan (insert (q : ℕ) T) [ctrl q v T U] ρ) =
      if w = v then chan T [U] (chan {(q : ℕ)} [proj q w] ρ)
      else chan {(q : ℕ)} [proj q w] ρ := by
  have key := proj_ctrl (U := U) (v := v) (w := w) hq
  rw [kraus_single, kraus_single]
  have e : lift {(q : ℕ)} (proj (n := n) q w) *
      (lift (insert (q : ℕ) T) (ctrl q v T U) * ρ *
        (lift (insert (q : ℕ) T) (ctrl q v T U))ᴴ) * (lift {(q : ℕ)} (proj (n := n) q w))ᴴ =
      (lift {(q : ℕ)} (proj (n := n) q w) * lift (insert (q : ℕ) T) (ctrl q v T U)) * ρ *
        (lift {(q : ℕ)} (proj (n := n) q w) * lift (insert (q : ℕ) T) (ctrl q v T U))ᴴ := by
    rw [conjTranspose_mul]; simp only [Matrix.mul_assoc]
  rw [e, key]
  split_ifs
  · rw [kraus_single, kraus_single, conjTranspose_mul]
    simp only [Matrix.mul_assoc]
  · rw [kraus_single]

/-- The condition `b = v`. -/
def bitIs (b : Bit) (v : Bool) : Cond :=
  ⟨fun β => β b == v, {b}, fun β β' h => by simp only [h b (Finset.mem_singleton_self b)]⟩

/-- The defer rule, direct form, on programs. Leaf `m` measures qubit
`q` into bit `b`, leaf `g` is `U` on `T`, leaf `cg` is `U` on `T`
controlled by qubit `q` on value `v`. -/
theorem defer_cq (spec : ℕ → Spec n) (m g cg : ℕ) (q : Fin n) (b : Bit) (v : Bool)
    {T : Finset Qubit} {U : Mat n} (hU : Local T U) (hq : (q : ℕ) ∉ T)
    (hm : spec m = .meas q b) (hg : spec g = Spec.gate T U hU)
    (hcg : spec cg = Spec.gate (insert (q : ℕ) T) (ctrl q v T U) (ctrl_local hU))
    (s : State (Mat n)) :
    denB (interp spec) [L spec m, .ite (bitIs b v) [L spec g] []] s =
      denB (interp spec) [L spec cg, L spec m] s := by
  simp only [denB, den, den_L, hm, hg, hcg]
  funext β
  change chan T [U] (restrict (bitIs b v) (measFn q b s) β) +
      restrict (bitIs b v).not (measFn q b s) β =
    measFn q b (fun γ => chan (insert (q : ℕ) T) [ctrl q v T U] (s γ)) β
  simp only [measFn, restrict, bitIs, Cond.not, ← chan_add, chan_proj_ctrl hq]
  by_cases hb : β b = v
  · simp [hb]
  · simp [hb, chan_zero]

end

end Qlin.CQ
