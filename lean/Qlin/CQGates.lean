import Qlin.CQ
import Qlin.PauliTable
import Qlin.Sink
import Qlin.M0
import Qlin.FastPath

/-!
# Gates on charts: the Pauli sink step and Kraus completeness

`Sink.lean` takes the arm conjugation `P ; C = C ; P'` as a hypothesis.
`PauliTable.lean` proves `C * P = φ • (P' * C)` with `φ = ±1` for 2 × 2
and 4 × 4 matrices. This file connects the two in the cq model of
`CQ.lean`: a matrix on one or two qubits is placed on `n` qubits by a
`Chart`, and the sign `φ` drops out of the Kraus map. So the sink step
needs no hand-checked part.

A `Chart n Q ι` reads the qubits in `Q` as an index of type `ι`.
`chart1 q` reads qubit `q` as `Fin 2`. `chart2 a b` reads qubits `a` and
`b` as `Fin 2 × Fin 2`, the index order of `PauliTable.lean`.

`meas_complete` and `reset_complete` show that the Kraus operators of
measurement and reset in `CQ.lean` sum to the identity (`Σ Kᴴ K = 1`),
so both are trace preserving.

`hoist_sound_cq`, `merge_sound_cq`, and `fastpath_step_cq` restate the
M0 and fast-path theorems for `interp spec`, with no assumption on the
leaves.
-/

namespace Qlin.CQ

open Matrix Qlin.Pauli

noncomputable section

variable {n : ℕ}

theorem AgreeOff.symm {Q : Finset Qubit} {x y : Basis n} (h : AgreeOff Q x y) :
    AgreeOff Q y x := fun i hi => (h i hi).symm

theorem AgreeOff.trans {Q : Finset Qubit} {x y z : Basis n} (h1 : AgreeOff Q x y)
    (h2 : AgreeOff Q y z) : AgreeOff Q x z := fun i hi => (h1 i hi).trans (h2 i hi)

/-- The qubits in `Q` read as an index of type `ι`. `put x i` is the
basis state equal to `x` off `Q` with index `i`. -/
structure Chart (n : ℕ) (Q : Finset Qubit) (ι : Type*) where
  r : Basis n → ι
  put : Basis n → ι → Basis n
  r_local : ∀ x y, AgreeOn Q x y → r x = r y
  r_put : ∀ x i, r (put x i) = i
  off_put : ∀ x i, AgreeOff Q x (put x i)
  put_r : ∀ x y, AgreeOff Q x y → put x (r y) = y

variable {Q : Finset Qubit} {ι : Type*} [Fintype ι] [DecidableEq ι]

/-- The matrix `M` on the qubits of the chart, before the lift. -/
def Chart.emb (ch : Chart n Q ι) (M : Matrix ι ι ℂ) : Mat n :=
  fun x y => M (ch.r x) (ch.r y)

omit [Fintype ι] [DecidableEq ι] in
theorem Chart.emb_local (ch : Chart n Q ι) (M : Matrix ι ι ℂ) : Local Q (ch.emb M) := by
  intro x y x' y' hx hy
  simp only [Chart.emb, ch.r_local x x' hx, ch.r_local y y' hy]

omit [DecidableEq ι] in
/-- A sum over the basis states equal to `x` off `Q` is a sum over the
index. -/
theorem Chart.sum_off (ch : Chart n Q ι) (x : Basis n) (g : ι → ℂ) :
    ∑ y : Basis n, (if AgreeOff Q x y then g (ch.r y) else 0) = ∑ i : ι, g i := by
  rw [← Finset.sum_filter]
  refine Finset.sum_nbij' ch.r (ch.put x) (by simp) (by simp [ch.off_put]) ?_ ?_ ?_
  · intro y hy
    exact ch.put_r x y (by simpa using hy)
  · intro i _
    exact ch.r_put x i
  · intro y _
    rfl

omit [DecidableEq ι] in
/-- Lifts of chart matrices multiply as the matrices. -/
theorem Chart.lift_emb_mul (ch : Chart n Q ι) (A B : Matrix ι ι ℂ) :
    lift Q (ch.emb A) * lift Q (ch.emb B) = lift Q (ch.emb (A * B)) := by
  ext x z
  simp only [Matrix.mul_apply, lift, Chart.emb]
  by_cases hxz : AgreeOff Q x z
  · rw [if_pos hxz]
    have h : ∀ y, (if AgreeOff Q x y then A (ch.r x) (ch.r y) else 0) *
        (if AgreeOff Q y z then B (ch.r y) (ch.r z) else 0) =
        if AgreeOff Q x y then A (ch.r x) (ch.r y) * B (ch.r y) (ch.r z) else 0 := by
      intro y
      by_cases hxy : AgreeOff Q x y
      · rw [if_pos hxy, if_pos (hxy.symm.trans hxz), if_pos hxy]
      · rw [if_neg hxy, if_neg hxy, zero_mul]
    simp only [h]
    exact ch.sum_off x (fun i => A (ch.r x) i * B i (ch.r z))
  · rw [if_neg hxz]
    refine Finset.sum_eq_zero fun y _ => ?_
    by_cases hxy : AgreeOff Q x y
    · rw [if_neg fun hyz => hxz (hxy.trans hyz), mul_zero]
    · rw [if_neg hxy, zero_mul]

omit [Fintype ι] in
theorem Chart.lift_emb_one (ch : Chart n Q ι) : lift Q (ch.emb 1) = 1 := by
  ext x z
  simp only [lift, Chart.emb, Matrix.one_apply]
  by_cases hxz : AgreeOff Q x z
  · rw [if_pos hxz]
    by_cases h : x = z
    · simp [h]
    · have hr : ch.r x ≠ ch.r z := fun hr => h (by
        rw [← ch.put_r x x (fun _ _ => rfl), ← ch.put_r x z hxz, hr])
      simp [h, hr]
  · rw [if_neg hxz, if_neg fun h : x = z => hxz (h ▸ fun _ _ => rfl)]

omit [Fintype ι] [DecidableEq ι] in
theorem Chart.lift_emb_conjTranspose (ch : Chart n Q ι) (M : Matrix ι ι ℂ) :
    (lift Q (ch.emb M))ᴴ = lift Q (ch.emb Mᴴ) := by
  ext x z
  simp only [conjTranspose_apply, lift, Chart.emb]
  by_cases h : AgreeOff Q x z
  · rw [if_pos h.symm, if_pos h]
  · rw [if_neg fun h' => h h'.symm, if_neg h, star_zero]

theorem lift_smul (Q : Finset Qubit) (c : ℂ) (k : Mat n) : lift Q (c • k) = c • lift Q k := by
  ext x z
  simp only [lift, Matrix.smul_apply, smul_eq_mul]
  split_ifs <;> simp

theorem kraus_single (Q : Finset Qubit) (K ρ : Mat n) :
    chan Q [K] ρ = lift Q K * ρ * (lift Q K)ᴴ := by
  simp [chan]

/-- A Kraus operator times a sign gives the same Kraus map. -/
theorem chan_sign (Q : Finset Qubit) {φ : ℂ} (hφ : IsSign φ) (K ρ : Mat n) :
    chan Q [φ • K] ρ = chan Q [K] ρ := by
  have hφφ : φ * star φ = 1 := by rcases hφ with rfl | rfl <;> simp
  rw [kraus_single, kraus_single, lift_smul, conjTranspose_smul, Matrix.smul_mul,
    Matrix.smul_mul, Matrix.mul_smul, smul_smul, hφφ, one_smul]

omit [DecidableEq ι] in
/-- The conjugation step: if `C * P = φ • (P' * C)` with `φ = ±1`, then
`P` then `C` equals `C` then `P'` as Kraus maps. -/
theorem Chart.chan_conj (ch : Chart n Q ι) {C P P' : Matrix ι ι ℂ} {φ : ℂ} (hφ : IsSign φ)
    (h : C * P = φ • (P' * C)) (ρ : Mat n) :
    chan Q [ch.emb C] (chan Q [ch.emb P] ρ) = chan Q [ch.emb P'] (chan Q [ch.emb C] ρ) := by
  have hmul : lift Q (ch.emb C) * lift Q (ch.emb P) =
      φ • (lift Q (ch.emb P') * lift Q (ch.emb C)) := by
    rw [ch.lift_emb_mul, ch.lift_emb_mul, h, ← lift_smul]
    congr 1
  have hφφ : φ * star φ = 1 := by rcases hφ with rfl | rfl <;> simp
  set LC := lift Q (ch.emb C)
  set LP := lift Q (ch.emb P)
  set LP' := lift Q (ch.emb P')
  rw [kraus_single, kraus_single, kraus_single, kraus_single]
  calc LC * (LP * ρ * LPᴴ) * LCᴴ = (LC * LP) * ρ * (LC * LP)ᴴ := by
        rw [conjTranspose_mul]; simp only [Matrix.mul_assoc]
    _ = (φ • (LP' * LC)) * ρ * (φ • (LP' * LC))ᴴ := by rw [hmul]
    _ = (LP' * LC) * ρ * (LP' * LC)ᴴ := by
        rw [conjTranspose_smul, Matrix.smul_mul, Matrix.smul_mul, Matrix.mul_smul, smul_smul,
          hφφ, one_smul]
    _ = LP' * (LC * ρ * LCᴴ) * LP'ᴴ := by
        rw [conjTranspose_mul]; simp only [Matrix.mul_assoc]


/-! ## One- and two-qubit charts -/

/-- A bit as an index of `Fin 2`. -/
def b2f (v : Bool) : Fin 2 := if v then 1 else 0

/-- An index of `Fin 2` as a bit. -/
def f2b (i : Fin 2) : Bool := decide (i = 1)

theorem f2b_b2f (v : Bool) : f2b (b2f v) = v := by cases v <;> decide

theorem b2f_f2b (i : Fin 2) : b2f (f2b i) = i := by fin_cases i <;> decide

theorem fin_ne {a b : Fin n} (h : a ≠ b) : (a : ℕ) ≠ b := fun h' => h (Fin.ext h')

/-- Qubit `q` as `Fin 2`. -/
def chart1 (q : Fin n) : Chart n {(q : ℕ)} (Fin 2) where
  r x := b2f (x q)
  put x i := Function.update x q (f2b i)
  r_local x y h := by rw [h q (Finset.mem_singleton_self _)]
  r_put x i := by simp [b2f_f2b]
  off_put x i j hj := by
    have : j ≠ q := fun h => hj (by simp [h])
    rw [Function.update_of_ne this]
  put_r x y h := by
    funext j
    by_cases hj : j = q
    · subst hj; simp [f2b_b2f]
    · rw [Function.update_of_ne hj]
      exact h j (by simpa using fin_ne hj)

/-- Qubits `a` and `b` as `Fin 2 × Fin 2`, `a` first. -/
def chart2 (a b : Fin n) (hab : a ≠ b) : Chart n {(a : ℕ), (b : ℕ)} (Fin 2 × Fin 2) where
  r x := (b2f (x a), b2f (x b))
  put x i := Function.update (Function.update x a (f2b i.1)) b (f2b i.2)
  r_local x y h := by
    rw [h a (by simp), h b (by simp)]
  r_put x i := by
    simp [Function.update_of_ne hab, b2f_f2b]
  off_put x i j hj := by
    have ha : j ≠ a := fun h => hj (by simp [h])
    have hb : j ≠ b := fun h => hj (by simp [h])
    rw [Function.update_of_ne hb, Function.update_of_ne ha]
  put_r x y h := by
    funext j
    by_cases hb : j = b
    · subst hb; simp [f2b_b2f]
    · rw [Function.update_of_ne hb]
      by_cases ha : j = a
      · subst ha; simp [f2b_b2f]
      · rw [Function.update_of_ne ha]
        exact h j (by simp [fin_ne ha, fin_ne hb])

@[simp] theorem chart1_r (q : Fin n) (x : Basis n) : (chart1 q).r x = b2f (x q) := rfl

@[simp] theorem chart2_r (a b : Fin n) (hab : a ≠ b) (x : Basis n) :
    (chart2 a b hab).r x = (b2f (x a), b2f (x b)) := rfl

theorem single_local {Q : Finset Qubit} {k : Mat n} (h : Local Q k) :
    ∀ k' ∈ [k], Local Q k' := fun k' hk' => by
  rw [List.mem_singleton.1 hk']
  exact h

/-- Two one-qubit Kraus operators on qubits `a` and `b` give their
Kronecker product on `a` and `b`. -/
theorem chan_kron {a b : Fin n} (hab : a ≠ b) (A B : M1) (ρ : Mat n) :
    chan {(a : ℕ)} [(chart1 a).emb A] (chan {(b : ℕ)} [(chart1 b).emb B] ρ) =
      chan {(a : ℕ), (b : ℕ)} [(chart2 a b hab).emb (kroneckerMap (· * ·) A B)] ρ := by
  have hd : Disjoint ({(a : ℕ)} : Finset Qubit) {(b : ℕ)} :=
    Finset.disjoint_singleton.2 (fin_ne hab)
  have hmul : lift {(a : ℕ)} ((chart1 a).emb A) * lift {(b : ℕ)} ((chart1 b).emb B) =
      lift {(a : ℕ), (b : ℕ)} ((chart2 a b hab).emb (kroneckerMap (· * ·) A B)) := by
    ext x z
    rw [lift_mul_apply hd ((chart1 a).emb_local A) ((chart1 b).emb_local B),
      ← Finset.insert_eq]
    simp only [lift, Chart.emb, chart1_r, chart2_r, kroneckerMap_apply]
  rw [kraus_single, kraus_single, kraus_single, ← hmul, conjTranspose_mul]
  simp only [Matrix.mul_assoc]

/-! ## Gates on charts, and the sink step on programs -/

/-- The gate `M` on qubit `q`. -/
def gate1 (q : Fin n) (M : M1) : Spec n :=
  Spec.gate {(q : ℕ)} ((chart1 q).emb M) ((chart1 q).emb_local M)

/-- The gate `M` on qubits `a` and `b`, `a` first. -/
def gate2 (a b : Fin n) (hab : a ≠ b) (M : M2) : Spec n :=
  Spec.gate {(a : ℕ), (b : ℕ)} ((chart2 a b hab).emb M) ((chart2 a b hab).emb_local M)

/-- Leaf `i` of the table, with its own footprint. -/
abbrev L (spec : ℕ → Spec n) (i : ℕ) : Op := .leaf i (spec i).fp

theorem den_L (spec : ℕ → Spec n) (i : ℕ) (s : State (Mat n)) :
    den (interp spec) (L spec i) s = (spec i).sem s := by
  simp only [L, den, interp_leaf]

/-- The identity gate does nothing. -/
theorem gate1_one (q : Fin n) (s : State (Mat n)) : (gate1 q 1).sem s = s := by
  funext β
  change chan _ [_] (s β) = s β
  rw [kraus_single, (chart1 q).lift_emb_one, conjTranspose_one, Matrix.one_mul,
    Matrix.mul_one]

/-- A conjugation fact for `C` holds for every multiple `μ • C` (the
table uses `√2 · H` and `2 · SX`). -/
theorem conj_smul {ι : Type*} [Fintype ι] {C P P' : Matrix ι ι ℂ} (μ : ℂ)
    (h : ∃ φ, IsSign φ ∧ C * P = φ • (P' * C)) :
    ∃ φ, IsSign φ ∧ (μ • C) * P = φ • (P' * (μ • C)) := by
  obtain ⟨φ, hφ, h⟩ := h
  refine ⟨φ, hφ, ?_⟩
  rw [Matrix.smul_mul, h, Matrix.mul_smul, smul_comm]

/-- The sink step past a one-qubit gate, on programs: if
`C * P = φ • (P' * C)` with `φ = ±1`, then `P ; C` equals `C ; P'`. -/
theorem sink1_cq (spec : ℕ → Spec n) (i j k : ℕ) (q : Fin n) {C P P' : M1}
    (h : ∃ φ, IsSign φ ∧ C * P = φ • (P' * C))
    (hi : spec i = gate1 q P) (hj : spec j = gate1 q C) (hk : spec k = gate1 q P')
    (s : State (Mat n)) :
    denB (interp spec) [L spec i, L spec j] s = denB (interp spec) [L spec j, L spec k] s := by
  obtain ⟨φ, hφ, h⟩ := h
  simp only [denB, den_L, hi, hj, hk]
  funext β
  exact (chart1 q).chan_conj hφ h (s β)

/-- The sink step past a two-qubit gate on qubits `a` and `b`. The arm
is one Pauli leaf on each qubit (`gate1_one` covers an identity). -/
theorem sink2_cq (spec : ℕ → Spec n) (i i' j k k' : ℕ) {a b : Fin n} (hab : a ≠ b)
    {C : M2} {A₁ A₂ B₁ B₂ : M1}
    (h : ∃ φ, IsSign φ ∧
      C * kroneckerMap (· * ·) A₁ A₂ = φ • (kroneckerMap (· * ·) B₁ B₂ * C))
    (hi : spec i = gate1 a A₁) (hi' : spec i' = gate1 b A₂) (hj : spec j = gate2 a b hab C)
    (hk : spec k = gate1 a B₁) (hk' : spec k' = gate1 b B₂) (s : State (Mat n)) :
    denB (interp spec) [L spec i, L spec i', L spec j] s =
      denB (interp spec) [L spec j, L spec k, L spec k'] s := by
  obtain ⟨φ, hφ, h⟩ := h
  have hd : Disjoint ({(a : ℕ)} : Finset Qubit) {(b : ℕ)} :=
    Finset.disjoint_singleton.2 (fin_ne hab)
  simp only [denB, den_L, hi, hi', hj, hk, hk']
  funext β
  change chan _ [_] (chan _ [_] (chan _ [_] (s β))) =
    chan _ [_] (chan _ [_] (chan _ [_] (s β)))
  have e1 := chan_comm hd (single_local ((chart1 a).emb_local A₁))
    (single_local ((chart1 b).emb_local A₂)) (s β)
  have e2 := chan_comm hd (single_local ((chart1 a).emb_local B₁))
    (single_local ((chart1 b).emb_local B₂))
    (chan {(a : ℕ), (b : ℕ)} [(chart2 a b hab).emb C] (s β))
  rw [← e1, ← e2, chan_kron hab, chan_kron hab]
  exact (chart2 a b hab).chan_conj hφ h (s β)


/-- Example: the Pauli `(x, z)` on qubit `q` sinks past the Hadamard
`(√2)⁻¹ • hM` and becomes `tH x z`. -/
theorem sink_h_cq (spec : ℕ → Spec n) (i j k : ℕ) (q : Fin n) (x z : Bool)
    (hi : spec i = gate1 q (pauli x z)) (hj : spec j = gate1 q ((Real.sqrt 2 : ℂ)⁻¹ • hM))
    (hk : spec k = gate1 q (pauli (tH x z).1 (tH x z).2)) (s : State (Mat n)) :
    denB (interp spec) [L spec i, L spec j] s = denB (interp spec) [L spec j, L spec k] s :=
  sink1_cq spec i j k q (conj_smul _ (conj_h x z)) hi hj hk s

/-- Example: a Pauli on control `a` and target `b` sinks past cx and
becomes `tCX`. -/
theorem sink_cx_cq (spec : ℕ → Spec n) (i i' j k k' : ℕ) {a b : Fin n} (hab : a ≠ b)
    (xc zc xt zt : Bool)
    (hi : spec i = gate1 a (pauli xc zc)) (hi' : spec i' = gate1 b (pauli xt zt))
    (hj : spec j = gate2 a b hab cxM)
    (hk : spec k = gate1 a (pauli (tCX xc zc xt zt).1.1 (tCX xc zc xt zt).1.2))
    (hk' : spec k' = gate1 b (pauli (tCX xc zc xt zt).2.1 (tCX xc zc xt zt).2.2))
    (s : State (Mat n)) :
    denB (interp spec) [L spec i, L spec i', L spec j] s =
      denB (interp spec) [L spec j, L spec k, L spec k'] s :=
  sink2_cq spec i i' j k k' hab (conj_cx xc zc xt zt) hi hi' hj hk hk' s


/-! ## Kraus completeness of measurement and reset -/

theorem lift_add (Q : Finset Qubit) (a b : Mat n) : lift Q (a + b) = lift Q a + lift Q b := by
  ext x z
  simp only [lift, Matrix.add_apply]
  split_ifs <;> simp

theorem qbit_fin (x : Basis n) (q : Fin n) : qbit x q = x q := by
  simp [qbit]

/-- `|v⟩⟨v|` as a 2 × 2 matrix. -/
def pm (v : Bool) : M1 := fun i j => if f2b i = v ∧ f2b j = v then 1 else 0

/-- `|0⟩⟨1|` as a 2 × 2 matrix. -/
def lm : M1 := fun i j => if f2b i = false ∧ f2b j = true then 1 else 0

theorem proj_emb (q : Fin n) (v : Bool) : proj (n := n) q v = (chart1 q).emb (pm v) := by
  ext x y
  simp [proj, Chart.emb, pm, qbit_fin, f2b_b2f]

theorem lower_emb (q : Fin n) : lower (n := n) q = (chart1 q).emb lm := by
  ext x y
  simp [lower, Chart.emb, lm, qbit_fin, f2b_b2f]

/-- The sum `Σ Kᴴ K` of two chart Kraus operators. -/
private theorem kraus_pair (q : Fin n) (A B : M1) (h : Aᴴ * A + Bᴴ * B = 1) :
    (lift {(q : ℕ)} ((chart1 q).emb A))ᴴ * lift {(q : ℕ)} ((chart1 q).emb A) +
      (lift {(q : ℕ)} ((chart1 q).emb B))ᴴ * lift {(q : ℕ)} ((chart1 q).emb B) = 1 := by
  rw [Chart.lift_emb_conjTranspose, Chart.lift_emb_conjTranspose, Chart.lift_emb_mul,
    Chart.lift_emb_mul, ← lift_add]
  have he : (chart1 q).emb (Aᴴ * A) + (chart1 q).emb (Bᴴ * B) = (chart1 q).emb 1 := by
    rw [← h]
    rfl
  rw [he, Chart.lift_emb_one]

/-- The two Kraus operators of a Z measurement sum to the identity. -/
theorem meas_complete (q : Fin n) :
    (lift {(q : ℕ)} (proj q false))ᴴ * lift {(q : ℕ)} (proj q false) +
      (lift {(q : ℕ)} (proj q true))ᴴ * lift {(q : ℕ)} (proj q true) = (1 : Mat n) := by
  rw [proj_emb, proj_emb]
  refine kraus_pair q _ _ ?_
  ext i j
  fin_cases i <;> fin_cases j <;> simp [pm, f2b, Matrix.mul_apply, Fin.sum_univ_two]

/-- The two Kraus operators of reset sum to the identity. -/
theorem reset_complete (q : Fin n) :
    (lift {(q : ℕ)} (proj q false))ᴴ * lift {(q : ℕ)} (proj q false) +
      (lift {(q : ℕ)} (lower q))ᴴ * lift {(q : ℕ)} (lower q) = (1 : Mat n) := by
  rw [proj_emb, lower_emb]
  refine kraus_pair q _ _ ?_
  ext i j
  fin_cases i <;> fin_cases j <;> simp [pm, lm, f2b, Matrix.mul_apply, Fin.sum_univ_two]


/-! ## The rewrite theorems in the cq model -/

theorem hoist_sound_cq (spec : ℕ → Spec n) (c : Cond) (x : Op) (pA A pB B : List Op)
    (hA : ∀ y ∈ pA, (Op.fp x).Disj (Op.fp y))
    (hB : ∀ y ∈ pB, (Op.fp x).Disj (Op.fp y))
    (hc : Disjoint c.bits (Op.fp x).writes) (s : State (Mat n)) :
    den (interp spec) (.ite c (pA ++ x :: A) (pB ++ x :: B)) s =
      denB (interp spec) [x, .ite c (pA ++ A) (pB ++ B)] s :=
  hoist_sound (interp spec) c x pA A pB B hA hB hc s

theorem merge_sound_cq (spec : ℕ → Spec n) (c : Cond) (x : Op) (A sA B sB : List Op)
    (hA : ∀ y ∈ sA, (Op.fp x).Disj (Op.fp y))
    (hB : ∀ y ∈ sB, (Op.fp x).Disj (Op.fp y)) (s : State (Mat n)) :
    den (interp spec) (.ite c (A ++ x :: sA) (B ++ x :: sB)) s =
      denB (interp spec) [.ite c (A ++ sA) (B ++ sB), x] s :=
  merge_sound (interp spec) c x A sA B sB hA hB s

theorem fastpath_step_cq (spec : ℕ → Spec n) (G : Finset Bit) (grp rest : List Op)
    (cases : List (Assign × List Op))
    (hbits : ∀ o ∈ grp, ∀ c A B, o = Op.ite c A B → c.bits ⊆ G)
    (hw : Disjoint G (Op.fps grp).writes)
    (hcase : ∀ p ∈ cases, ∀ s,
      denB (interp spec) p.2 s = denB (interp spec) (selected p.1 grp ++ rest) s)
    (s : State (Mat n)) :
    den (interp spec) (.switch G cases (grp ++ rest)) s =
      denB (interp spec) (grp ++ rest) s :=
  fastpath_step (interp spec) G grp rest cases hbits hw hcase s

end

end Qlin.CQ
