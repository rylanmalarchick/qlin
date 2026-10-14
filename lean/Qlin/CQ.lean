import Qlin.Sem

/-!
# A concrete cq-channel model of A1 and A2

`n` qubits with computational basis `Fin n → Bool`. The quantum part of
a branch is a complex matrix over that basis (an unnormalized density
operator). A leaf is one of:
- `Spec.kraus Q ks`: the Kraus map `ρ ↦ Σ K ρ Kᴴ`. Each `K` acts on the
  qubits in `Q` and as the identity on the rest (`lift`). A gate has one
  Kraus operator (`Spec.gate`), reset has two (`Spec.reset`).
- `Spec.meas q b`: measure qubit `q` in the Z basis and write the
  outcome to bit `b`.

`interp` builds an `Interp` from a table of leaves. A1 and A2 are its
proof fields (`Spec.sem_restrict`, `Spec.sem_comm`), so every theorem
stated for an `Interp` holds for this model with no extra assumption.
-/

namespace Qlin.CQ

noncomputable section

open Matrix

variable {n : ℕ}

/-- A computational basis state of `n` qubits. -/
abbrev Basis (n : ℕ) := Fin n → Bool

/-- An operator on `n` qubits. -/
abbrev Mat (n : ℕ) := Matrix (Basis n) (Basis n) ℂ

/-- The value of qubit `q` in `x`. A qubit `q ≥ n` reads `false`. -/
def qbit (x : Basis n) (q : Qubit) : Bool := if h : q < n then x ⟨q, h⟩ else false

/-- `x` and `y` agree on every qubit in `Q`. -/
def AgreeOn (Q : Finset Qubit) (x y : Basis n) : Prop :=
  ∀ i : Fin n, (i : ℕ) ∈ Q → x i = y i

/-- `x` and `y` agree on every qubit outside `Q`. -/
def AgreeOff (Q : Finset Qubit) (x y : Basis n) : Prop :=
  ∀ i : Fin n, (i : ℕ) ∉ Q → x i = y i

instance (Q : Finset Qubit) (x y : Basis n) : Decidable (AgreeOff Q x y) := by
  unfold AgreeOff; infer_instance

/-- `k` reads only the qubits in `Q`. -/
def Local (Q : Finset Qubit) (k : Mat n) : Prop :=
  ∀ x y x' y', AgreeOn Q x x' → AgreeOn Q y y' → k x y = k x' y'

/-- `k` on the qubits in `Q`, the identity on the rest. -/
def lift (Q : Finset Qubit) (k : Mat n) : Mat n :=
  fun x y => if AgreeOff Q x y then k x y else 0

/-- `z` on the qubits in `Q`, `x` on the rest. -/
def mid (Q : Finset Qubit) (z x : Basis n) : Basis n :=
  fun i => if (i : ℕ) ∈ Q then z i else x i

/-- A product of lifts on disjoint qubit sets, entry by entry. -/
theorem lift_mul_apply {P Q : Finset Qubit} (hd : Disjoint P Q) {a b : Mat n}
    (ha : Local P a) (hb : Local Q b) (x z : Basis n) :
    (lift P a * lift Q b) x z = if AgreeOff (P ∪ Q) x z then a x z * b x z else 0 := by
  rw [Matrix.mul_apply, Finset.sum_eq_single (mid P z x)]
  · have h1 : AgreeOff P x (mid P z x) := fun i hi => by simp [mid, hi]
    have hay : a x (mid P z x) = a x z :=
      ha _ _ _ _ (fun _ _ => rfl) (fun i hi => by simp [mid, hi])
    have hby : b (mid P z x) z = b x z :=
      hb _ _ _ _ (fun i hi => by simp [mid, Finset.disjoint_right.1 hd hi]) (fun _ _ => rfl)
    simp only [lift]
    rw [if_pos h1, hay, hby]
    by_cases h : AgreeOff (P ∪ Q) x z
    · have h2 : AgreeOff Q (mid P z x) z := fun i hi => by
        by_cases hP : (i : ℕ) ∈ P
        · simp [mid, hP]
        · simp only [mid, hP, if_false]
          exact h i (by simp [hP, hi])
      rw [if_pos h2, if_pos h]
    · have h2 : ¬ AgreeOff Q (mid P z x) z := fun h2 => h fun i hi => by
        simp only [Finset.mem_union, not_or] at hi
        have := h2 i hi.2
        simpa [mid, hi.1] using this
      rw [if_neg h2, if_neg h, mul_zero]
  · intro y _ hy
    simp only [lift]
    by_cases h1 : AgreeOff P x y
    · by_cases h2 : AgreeOff Q y z
      · exfalso
        apply hy
        funext i
        by_cases hP : (i : ℕ) ∈ P
        · simp only [mid, hP, if_true]
          exact h2 i (Finset.disjoint_left.1 hd hP)
        · simp only [mid, hP, if_false]
          exact (h1 i hP).symm
      · simp [h2]
    · simp [h1]
  · intro h
    exact absurd (Finset.mem_univ _) h

/-- Lifts on disjoint qubit sets commute. -/
theorem lift_comm {P Q : Finset Qubit} (hd : Disjoint P Q) {a b : Mat n}
    (ha : Local P a) (hb : Local Q b) :
    lift P a * lift Q b = lift Q b * lift P a := by
  ext x z
  rw [lift_mul_apply hd ha hb, lift_mul_apply hd.symm hb ha, Finset.union_comm, mul_comm]

/-- The Kraus map `ρ ↦ Σ K ρ Kᴴ`, each Kraus operator lifted from `Q`. -/
def chan (Q : Finset Qubit) (ks : List (Mat n)) (ρ : Mat n) : Mat n :=
  (ks.map fun k => lift Q k * ρ * (lift Q k)ᴴ).sum

theorem chan_add (Q : Finset Qubit) (ks : List (Mat n)) (ρ σ : Mat n) :
    chan Q ks (ρ + σ) = chan Q ks ρ + chan Q ks σ := by
  simp only [chan, Matrix.mul_add, Matrix.add_mul, List.sum_map_add]

theorem chan_zero (Q : Finset Qubit) (ks : List (Mat n)) : chan Q ks 0 = 0 := by
  simp [chan]

private theorem list_sum_comm {α β M : Type*} [AddCommMonoid M] (l1 : List α) (l2 : List β)
    (f : α → β → M) :
    (l1.map fun a => (l2.map fun b => f a b).sum).sum =
      (l2.map fun b => (l1.map fun a => f a b).sum).sum := by
  induction l1 with
  | nil => simp
  | cons a l ih => simp [ih, List.sum_map_add]

private theorem conj_sum (A : Mat n) (ls : List (Mat n)) (g : Mat n → Mat n) :
    A * (ls.map g).sum * Aᴴ = (ls.map fun l => A * g l * Aᴴ).sum := by
  rw [← List.sum_map_mul_left, ← List.sum_map_mul_right]

/-- Kraus maps on disjoint qubit sets commute. -/
theorem chan_comm {P Q : Finset Qubit} (hd : Disjoint P Q) {ks ls : List (Mat n)}
    (hk : ∀ k ∈ ks, Local P k) (hl : ∀ l ∈ ls, Local Q l) (ρ : Mat n) :
    chan P ks (chan Q ls ρ) = chan Q ls (chan P ks ρ) := by
  have key : ∀ k ∈ ks, ∀ l ∈ ls, lift P k * (lift Q l * ρ * (lift Q l)ᴴ) * (lift P k)ᴴ =
      lift Q l * (lift P k * ρ * (lift P k)ᴴ) * (lift Q l)ᴴ := by
    intro k hk' l hl'
    have hc := lift_comm hd (hk k hk') (hl l hl')
    have hc' : (lift Q l)ᴴ * (lift P k)ᴴ = (lift P k)ᴴ * (lift Q l)ᴴ := by
      rw [← conjTranspose_mul, ← conjTranspose_mul, hc]
    calc _ = (lift P k * lift Q l) * ρ * ((lift Q l)ᴴ * (lift P k)ᴴ) := by
          simp only [Matrix.mul_assoc]
      _ = (lift Q l * lift P k) * ρ * ((lift P k)ᴴ * (lift Q l)ᴴ) := by rw [hc, hc']
      _ = _ := by simp only [Matrix.mul_assoc]
  simp only [chan, conj_sum]
  rw [list_sum_comm]
  refine congrArg List.sum (List.map_congr_left fun l hl' => ?_)
  exact congrArg List.sum (List.map_congr_left fun k hk' => key k hk' l hl')


/-! ## Leaves -/

theorem qbit_local {q : Qubit} {x x' : Basis n} (h : AgreeOn {q} x x') :
    qbit x q = qbit x' q := by
  unfold qbit
  split_ifs with hq
  · exact h ⟨q, hq⟩ (Finset.mem_singleton_self q)
  · rfl

/-- `|v⟩⟨v|` on qubit `q`, before the lift. -/
def proj (q : Qubit) (v : Bool) : Mat n :=
  fun x y => if qbit x q = v ∧ qbit y q = v then 1 else 0

/-- `|0⟩⟨1|` on qubit `q`, before the lift (the second Kraus operator of
reset). -/
def lower (q : Qubit) : Mat n :=
  fun x y => if qbit x q = false ∧ qbit y q = true then 1 else 0

theorem proj_local (q : Qubit) (v : Bool) : Local {q} (proj (n := n) q v) := by
  intro x y x' y' hx hy
  simp only [proj, qbit_local hx, qbit_local hy]

theorem lower_local (q : Qubit) : Local {q} (lower (n := n) q) := by
  intro x y x' y' hx hy
  simp only [lower, qbit_local hx, qbit_local hy]

/-- A leaf: a Kraus map on the qubits `Q`, or a Z measurement of qubit
`q` into bit `b`. -/
inductive Spec (n : ℕ) where
  | kraus (Q : Finset Qubit) (ks : List (Mat n)) (hk : ∀ k ∈ ks, Local Q k)
  | meas (q : Qubit) (b : Bit)

/-- A gate: the operator `U` on the qubits `Q`. -/
def Spec.gate (Q : Finset Qubit) (U : Mat n) (hU : Local Q U) : Spec n :=
  .kraus Q [U] (by simpa using hU)

/-- Reset of qubit `q` to `|0⟩`: Kraus operators `|0⟩⟨0|` and `|0⟩⟨1|`. -/
def Spec.reset (q : Qubit) : Spec n :=
  .kraus {q} [proj q false, lower q] (by
    intro k hk
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hk
    rcases hk with rfl | rfl
    · exact proj_local q false
    · exact lower_local q)

/-- The footprint of a leaf, as `Op::footprint` in `src/ir.rs`. -/
def Spec.fp : Spec n → Footprint
  | .kraus Q _ _ => ⟨Q, ∅, ∅⟩
  | .meas q b => ⟨{q}, ∅, {b}⟩

/-- Measure qubit `q` into bit `b`: the branch `β` collects both old
values of `b` and keeps the part where qubit `q` equals `β b`. -/
def measFn (q : Qubit) (b : Bit) (s : State (Mat n)) : State (Mat n) := fun β =>
  chan {q} [proj q (β b)] (s (Function.update β b false) + s (Function.update β b true))

/-- The semantics of a leaf. -/
def Spec.sem : Spec n → State (Mat n) →+ State (Mat n)
  | .kraus Q ks _ =>
    { toFun := fun s β => chan Q ks (s β)
      map_zero' := by funext β; exact chan_zero Q ks
      map_add' := fun s t => by funext β; exact chan_add Q ks (s β) (t β) }
  | .meas q b =>
    { toFun := measFn q b
      map_zero' := by funext β; simp [measFn, chan_zero]
      map_add' := fun s t => by
        funext β
        simp only [measFn, Pi.add_apply, ← chan_add]
        congr 1
        abel }

/-- A1 for a leaf. -/
theorem Spec.sem_restrict (sp : Spec n) (c : Cond) (hc : Disjoint c.bits sp.fp.writes)
    (s : State (Mat n)) : sp.sem (restrict c s) = restrict c (sp.sem s) := by
  funext β
  cases sp with
  | kraus Q ks hk =>
    simp only [Spec.sem, AddMonoidHom.coe_mk, ZeroHom.coe_mk, restrict]
    split_ifs <;> simp [chan_zero]
  | meas q b =>
    have hb : b ∉ c.bits := fun h => Finset.disjoint_left.1 hc h (by simp [Spec.fp])
    have hu : ∀ v, c.eval (Function.update β b v) = c.eval β := fun v =>
      c.dep _ _ fun b' hb' => by
        rw [Function.update_of_ne (by rintro rfl; exact hb hb')]
    simp only [Spec.sem, AddMonoidHom.coe_mk, ZeroHom.coe_mk, measFn, restrict, hu]
    split_ifs <;> simp [chan_zero]

private theorem proj_single (q : Qubit) (v : Bool) :
    ∀ k ∈ [proj (n := n) q v], Local {q} k := fun k hk => by
  rw [List.mem_singleton.1 hk]
  exact proj_local q v

/-- A measurement commutes with a Kraus map on other qubits. -/
private theorem meas_chan_comm {q : Qubit} {b : Bit} {Q : Finset Qubit} {ks : List (Mat n)}
    (hk : ∀ k ∈ ks, Local Q k) (hq : q ∉ Q) (s : State (Mat n)) (β : Assign) :
    measFn q b (fun γ => chan Q ks (s γ)) β = chan Q ks (measFn q b s β) := by
  have hd : Disjoint ({q} : Finset Qubit) Q := Finset.disjoint_singleton_left.2 hq
  simp only [measFn, ← chan_add]
  exact chan_comm hd (proj_single q (β b)) hk _

/-- A2 for leaves. -/
theorem Spec.sem_comm (sp sq : Spec n) (hq : Disjoint sp.fp.qubits sq.fp.qubits)
    (hw : Disjoint sp.fp.writes sq.fp.writes) (s : State (Mat n)) :
    sp.sem (sq.sem s) = sq.sem (sp.sem s) := by
  funext β
  cases sp with
  | kraus P ks hk =>
    cases sq with
    | kraus Q ls hl =>
      exact chan_comm hq hk hl (s β)
    | meas q b =>
      exact (meas_chan_comm hk (Finset.disjoint_singleton_right.1 hq) s β).symm
  | meas p a =>
    cases sq with
    | kraus Q ls hl =>
      exact meas_chan_comm hl (Finset.disjoint_singleton_left.1 hq) s β
    | meas q b =>
      have hpq : p ≠ q := Finset.disjoint_singleton.1 hq
      have hab : a ≠ b := Finset.disjoint_singleton.1 hw
      have hd : Disjoint ({p} : Finset Qubit) {q} := Finset.disjoint_singleton.2 hpq
      simp only [Spec.sem, AddMonoidHom.coe_mk, ZeroHom.coe_mk, measFn,
        Function.update_of_ne hab.symm, Function.update_of_ne hab, ← chan_add]
      rw [chan_comm hd (proj_single p (β a)) (proj_single q (β b))]
      congr 2
      simp only [Function.update_comm hab]
      abel

open Classical in
/-- The cq model: leaf `i` with footprint `f` is `spec i` when `f`
covers its footprint, else the identity. The footprint of a Rust leaf
always covers its own op (`interp_leaf`). -/
def interp (spec : ℕ → Spec n) : Interp (Mat n) where
  leaf i f := if (spec i).fp.qubits ⊆ f.qubits ∧ (spec i).fp.writes ⊆ f.writes
    then (spec i).sem else AddMonoidHom.id _
  local_ i f c hc s := by
    split_ifs with h
    · exact (spec i).sem_restrict c (Finset.disjoint_of_subset_right h.2 hc) s
    · rfl
  comm i f j g hd s := by
    split_ifs with h1 h2 h2
    · exact (spec i).sem_comm (spec j) (Finset.disjoint_of_subset_left h1.1
        (Finset.disjoint_of_subset_right h2.1 hd.1))
        (Finset.disjoint_of_subset_left h1.2 (Finset.disjoint_of_subset_right h2.2 hd.2.1)) s
    all_goals rfl

/-- A leaf whose footprint is its own denotes its spec. -/
theorem interp_leaf (spec : ℕ → Spec n) (i : ℕ) :
    (interp spec).leaf i (spec i).fp = (spec i).sem := by
  simp [interp]

end

end Qlin.CQ
