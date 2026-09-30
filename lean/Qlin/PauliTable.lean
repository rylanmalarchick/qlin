import Mathlib

/-!
# R3c: the Pauli conjugation table of `src/pauli.rs`

A Pauli on one qubit is a pair `(x, z)`: `(0,0) = I`, `(1,0) = X`,
`(1,1) = Y`, `(0,1) = Z`. `conjugate` in `src/pauli.rs` maps the Pauli
`P` before a Clifford gate `C` to the Pauli `P'` after it:
`C * P = φ • (P' * C)` with `φ = ±1`.

The equation is homogeneous in `C`, so a nonzero multiple of a gate
gives the same fact. `hM` is `√2 · H` and `sxM` is `2 · SX`, which
keeps the square roots out.

Two-qubit matrices use the index `(a, b)`, where `a` is the first qubit
(the control for cx and cy).
-/

namespace Qlin.Pauli

open Complex Matrix

abbrev M1 := Matrix (Fin 2) (Fin 2) ℂ
abbrev M2 := Matrix (Fin 2 × Fin 2) (Fin 2 × Fin 2) ℂ

def pX : M1 := !![0, 1; 1, 0]
def pY : M1 := !![0, -I; I, 0]
def pZ : M1 := !![1, 0; 0, -1]

/-- The Pauli `(x, z)`. -/
def pauli : Bool → Bool → M1
  | false, false => 1
  | true, false => pX
  | true, true => pY
  | false, true => pZ

/-- The two-qubit Pauli `(x1, z1) ⊗ (x2, z2)`. -/
def pauli2 (x1 z1 x2 z2 : Bool) : M2 :=
  kroneckerMap (· * ·) (pauli x1 z1) (pauli x2 z2)

def hM : M1 := !![1, 1; 1, -1]
def sM : M1 := !![1, 0; 0, I]
def sdgM : M1 := !![1, 0; 0, -I]
def sxM : M1 := !![1 + I, 1 - I; 1 - I, 1 + I]

def cxM : M2 := Matrix.of fun i j => if i.1 = j.1 ∧ i.2 = j.2 + j.1 then 1 else 0
def czM : M2 := Matrix.of fun i j => if i = j then (if i = (1, 1) then -1 else 1) else 0
def cyM : M2 := Matrix.of fun i j =>
  if i.1 = j.1 then (if j.1 = 0 then (if i.2 = j.2 then 1 else 0) else pY i.2 j.2) else 0
def swapM : M2 := Matrix.of fun i j => if i = (j.2, j.1) then 1 else 0

/-- Single-qubit tables, as in `conjugate`. -/
def tH (x z : Bool) : Bool × Bool := (z, x)
def tS (x z : Bool) : Bool × Bool := (x, xor z x)
def tSX (x z : Bool) : Bool × Bool := (xor x z, z)

/-- Two-qubit tables: `((x1, z1), (x2, z2))`. -/
def tCX (xc zc xt zt : Bool) : (Bool × Bool) × (Bool × Bool) :=
  ((xc, xor zc zt), (xor xt xc, zt))
def tCZ (xa za xb zb : Bool) : (Bool × Bool) × (Bool × Bool) :=
  ((xa, xor za xb), (xb, xor zb xa))
/-- cy is Sdg on the target, then cx, then S on the target (time order). -/
def tCY (xc zc xt zt : Bool) : (Bool × Bool) × (Bool × Bool) :=
  let t1 := tS xt zt
  let r := tCX xc zc t1.1 t1.2
  (r.1, tS r.2.1 r.2.2)

/-- The sign condition. -/
def IsSign (φ : ℂ) : Prop := φ = 1 ∨ φ = -1

/-- Entrywise check of a single-qubit conjugation identity. -/
local macro "pauli_ent" : tactic => `(tactic| (
  simp only [pauli, tH, tS, tSX, pX, pY, pZ, hM, sM, sdgM, sxM, Bool.xor_true, Bool.xor_false,
    Bool.not_true, Bool.not_false, Matrix.one_fin_two, Matrix.mul_fin_two, Matrix.smul_of,
    Matrix.smul_cons, Matrix.smul_empty, smul_eq_mul]
  ext i j; fin_cases i <;> fin_cases j <;> (try simp) <;> (try ring_nf) <;> (try simp) <;>
    (try ring_nf) <;> done))

/-- Try both signs for a single-qubit conjugation identity. -/
local macro "pauli_sign" : tactic => `(tactic| first
  | (refine ⟨1, Or.inl rfl, ?_⟩; pauli_ent)
  | (refine ⟨-1, Or.inr rfl, ?_⟩; pauli_ent))

/-- Entrywise check of a two-qubit conjugation identity. -/
local macro "pauli_ent2" : tactic => `(tactic| (
  simp only [pauli2, pauli, Matrix.one_fin_two, pX, pY, pZ, tCX, tCZ, tCY, tS, Bool.xor_true,
    Bool.xor_false, Bool.not_true, Bool.not_false, Bool.false_xor, Bool.true_xor]
  ext ⟨a, b⟩ ⟨c, d⟩
  simp only [Matrix.mul_apply, Fintype.sum_prod_type, Fin.sum_univ_two, Matrix.smul_apply,
    kroneckerMap_apply, smul_eq_mul]
  fin_cases a <;> fin_cases b <;> fin_cases c <;> fin_cases d <;>
    (try simp [cxM, czM, cyM, swapM, pY]) <;> (try ring_nf) <;> (try simp) <;> (try ring_nf) <;>
    done))

/-- Try both signs for a two-qubit conjugation identity. -/
local macro "pauli_sign2" : tactic => `(tactic| first
  | (refine ⟨1, Or.inl rfl, ?_⟩; pauli_ent2)
  | (refine ⟨-1, Or.inr rfl, ?_⟩; pauli_ent2))

theorem conj_h (x z : Bool) :
    ∃ φ, IsSign φ ∧ hM * pauli x z = φ • (pauli (tH x z).1 (tH x z).2 * hM) := by
  cases x <;> cases z <;> pauli_sign

theorem conj_s (x z : Bool) :
    ∃ φ, IsSign φ ∧ sM * pauli x z = φ • (pauli (tS x z).1 (tS x z).2 * sM) := by
  cases x <;> cases z <;> pauli_sign

theorem conj_sdg (x z : Bool) :
    ∃ φ, IsSign φ ∧ sdgM * pauli x z = φ • (pauli (tS x z).1 (tS x z).2 * sdgM) := by
  cases x <;> cases z <;> pauli_sign

theorem conj_sx (x z : Bool) :
    ∃ φ, IsSign φ ∧ sxM * pauli x z = φ • (pauli (tSX x z).1 (tSX x z).2 * sxM) := by
  cases x <;> cases z <;> pauli_sign

/-- x, y, and z leave every Pauli unchanged up to sign. -/
theorem conj_pauli (a b x z : Bool) :
    ∃ φ, IsSign φ ∧ pauli a b * pauli x z = φ • (pauli x z * pauli a b) := by
  cases a <;> cases b <;> cases x <;> cases z <;> pauli_sign

private theorem conj_cx_ffff :
    ∃ φ, IsSign φ ∧ cxM * pauli2 false false false false =
      φ • (pauli2 (tCX false false false false).1.1 (tCX false false false false).1.2
      (tCX false false false false).2.1 (tCX false false false false).2.2 * cxM) := by
  pauli_sign2

private theorem conj_cx_ffft :
    ∃ φ, IsSign φ ∧ cxM * pauli2 false false false true =
      φ • (pauli2 (tCX false false false true).1.1 (tCX false false false true).1.2
      (tCX false false false true).2.1 (tCX false false false true).2.2 * cxM) := by
  pauli_sign2

private theorem conj_cx_fftf :
    ∃ φ, IsSign φ ∧ cxM * pauli2 false false true false =
      φ • (pauli2 (tCX false false true false).1.1 (tCX false false true false).1.2
      (tCX false false true false).2.1 (tCX false false true false).2.2 * cxM) := by
  pauli_sign2

private theorem conj_cx_fftt :
    ∃ φ, IsSign φ ∧ cxM * pauli2 false false true true =
      φ • (pauli2 (tCX false false true true).1.1 (tCX false false true true).1.2
      (tCX false false true true).2.1 (tCX false false true true).2.2 * cxM) := by
  pauli_sign2

private theorem conj_cx_ftff :
    ∃ φ, IsSign φ ∧ cxM * pauli2 false true false false =
      φ • (pauli2 (tCX false true false false).1.1 (tCX false true false false).1.2
      (tCX false true false false).2.1 (tCX false true false false).2.2 * cxM) := by
  pauli_sign2

private theorem conj_cx_ftft :
    ∃ φ, IsSign φ ∧ cxM * pauli2 false true false true =
      φ • (pauli2 (tCX false true false true).1.1 (tCX false true false true).1.2
      (tCX false true false true).2.1 (tCX false true false true).2.2 * cxM) := by
  pauli_sign2

private theorem conj_cx_fttf :
    ∃ φ, IsSign φ ∧ cxM * pauli2 false true true false =
      φ • (pauli2 (tCX false true true false).1.1 (tCX false true true false).1.2
      (tCX false true true false).2.1 (tCX false true true false).2.2 * cxM) := by
  pauli_sign2

private theorem conj_cx_fttt :
    ∃ φ, IsSign φ ∧ cxM * pauli2 false true true true =
      φ • (pauli2 (tCX false true true true).1.1 (tCX false true true true).1.2
      (tCX false true true true).2.1 (tCX false true true true).2.2 * cxM) := by
  pauli_sign2

private theorem conj_cx_tfff :
    ∃ φ, IsSign φ ∧ cxM * pauli2 true false false false =
      φ • (pauli2 (tCX true false false false).1.1 (tCX true false false false).1.2
      (tCX true false false false).2.1 (tCX true false false false).2.2 * cxM) := by
  pauli_sign2

private theorem conj_cx_tfft :
    ∃ φ, IsSign φ ∧ cxM * pauli2 true false false true =
      φ • (pauli2 (tCX true false false true).1.1 (tCX true false false true).1.2
      (tCX true false false true).2.1 (tCX true false false true).2.2 * cxM) := by
  pauli_sign2

private theorem conj_cx_tftf :
    ∃ φ, IsSign φ ∧ cxM * pauli2 true false true false =
      φ • (pauli2 (tCX true false true false).1.1 (tCX true false true false).1.2
      (tCX true false true false).2.1 (tCX true false true false).2.2 * cxM) := by
  pauli_sign2

private theorem conj_cx_tftt :
    ∃ φ, IsSign φ ∧ cxM * pauli2 true false true true =
      φ • (pauli2 (tCX true false true true).1.1 (tCX true false true true).1.2
      (tCX true false true true).2.1 (tCX true false true true).2.2 * cxM) := by
  pauli_sign2

private theorem conj_cx_ttff :
    ∃ φ, IsSign φ ∧ cxM * pauli2 true true false false =
      φ • (pauli2 (tCX true true false false).1.1 (tCX true true false false).1.2
      (tCX true true false false).2.1 (tCX true true false false).2.2 * cxM) := by
  pauli_sign2

private theorem conj_cx_ttft :
    ∃ φ, IsSign φ ∧ cxM * pauli2 true true false true =
      φ • (pauli2 (tCX true true false true).1.1 (tCX true true false true).1.2
      (tCX true true false true).2.1 (tCX true true false true).2.2 * cxM) := by
  pauli_sign2

private theorem conj_cx_tttf :
    ∃ φ, IsSign φ ∧ cxM * pauli2 true true true false =
      φ • (pauli2 (tCX true true true false).1.1 (tCX true true true false).1.2
      (tCX true true true false).2.1 (tCX true true true false).2.2 * cxM) := by
  pauli_sign2

private theorem conj_cx_tttt :
    ∃ φ, IsSign φ ∧ cxM * pauli2 true true true true =
      φ • (pauli2 (tCX true true true true).1.1 (tCX true true true true).1.2
      (tCX true true true true).2.1 (tCX true true true true).2.2 * cxM) := by
  pauli_sign2

private theorem conj_cz_ffff :
    ∃ φ, IsSign φ ∧ czM * pauli2 false false false false =
      φ • (pauli2 (tCZ false false false false).1.1 (tCZ false false false false).1.2
      (tCZ false false false false).2.1 (tCZ false false false false).2.2 * czM) := by
  pauli_sign2

private theorem conj_cz_ffft :
    ∃ φ, IsSign φ ∧ czM * pauli2 false false false true =
      φ • (pauli2 (tCZ false false false true).1.1 (tCZ false false false true).1.2
      (tCZ false false false true).2.1 (tCZ false false false true).2.2 * czM) := by
  pauli_sign2

private theorem conj_cz_fftf :
    ∃ φ, IsSign φ ∧ czM * pauli2 false false true false =
      φ • (pauli2 (tCZ false false true false).1.1 (tCZ false false true false).1.2
      (tCZ false false true false).2.1 (tCZ false false true false).2.2 * czM) := by
  pauli_sign2

private theorem conj_cz_fftt :
    ∃ φ, IsSign φ ∧ czM * pauli2 false false true true =
      φ • (pauli2 (tCZ false false true true).1.1 (tCZ false false true true).1.2
      (tCZ false false true true).2.1 (tCZ false false true true).2.2 * czM) := by
  pauli_sign2

private theorem conj_cz_ftff :
    ∃ φ, IsSign φ ∧ czM * pauli2 false true false false =
      φ • (pauli2 (tCZ false true false false).1.1 (tCZ false true false false).1.2
      (tCZ false true false false).2.1 (tCZ false true false false).2.2 * czM) := by
  pauli_sign2

private theorem conj_cz_ftft :
    ∃ φ, IsSign φ ∧ czM * pauli2 false true false true =
      φ • (pauli2 (tCZ false true false true).1.1 (tCZ false true false true).1.2
      (tCZ false true false true).2.1 (tCZ false true false true).2.2 * czM) := by
  pauli_sign2

private theorem conj_cz_fttf :
    ∃ φ, IsSign φ ∧ czM * pauli2 false true true false =
      φ • (pauli2 (tCZ false true true false).1.1 (tCZ false true true false).1.2
      (tCZ false true true false).2.1 (tCZ false true true false).2.2 * czM) := by
  pauli_sign2

private theorem conj_cz_fttt :
    ∃ φ, IsSign φ ∧ czM * pauli2 false true true true =
      φ • (pauli2 (tCZ false true true true).1.1 (tCZ false true true true).1.2
      (tCZ false true true true).2.1 (tCZ false true true true).2.2 * czM) := by
  pauli_sign2

private theorem conj_cz_tfff :
    ∃ φ, IsSign φ ∧ czM * pauli2 true false false false =
      φ • (pauli2 (tCZ true false false false).1.1 (tCZ true false false false).1.2
      (tCZ true false false false).2.1 (tCZ true false false false).2.2 * czM) := by
  pauli_sign2

private theorem conj_cz_tfft :
    ∃ φ, IsSign φ ∧ czM * pauli2 true false false true =
      φ • (pauli2 (tCZ true false false true).1.1 (tCZ true false false true).1.2
      (tCZ true false false true).2.1 (tCZ true false false true).2.2 * czM) := by
  pauli_sign2

private theorem conj_cz_tftf :
    ∃ φ, IsSign φ ∧ czM * pauli2 true false true false =
      φ • (pauli2 (tCZ true false true false).1.1 (tCZ true false true false).1.2
      (tCZ true false true false).2.1 (tCZ true false true false).2.2 * czM) := by
  pauli_sign2

private theorem conj_cz_tftt :
    ∃ φ, IsSign φ ∧ czM * pauli2 true false true true =
      φ • (pauli2 (tCZ true false true true).1.1 (tCZ true false true true).1.2
      (tCZ true false true true).2.1 (tCZ true false true true).2.2 * czM) := by
  pauli_sign2

private theorem conj_cz_ttff :
    ∃ φ, IsSign φ ∧ czM * pauli2 true true false false =
      φ • (pauli2 (tCZ true true false false).1.1 (tCZ true true false false).1.2
      (tCZ true true false false).2.1 (tCZ true true false false).2.2 * czM) := by
  pauli_sign2

private theorem conj_cz_ttft :
    ∃ φ, IsSign φ ∧ czM * pauli2 true true false true =
      φ • (pauli2 (tCZ true true false true).1.1 (tCZ true true false true).1.2
      (tCZ true true false true).2.1 (tCZ true true false true).2.2 * czM) := by
  pauli_sign2

private theorem conj_cz_tttf :
    ∃ φ, IsSign φ ∧ czM * pauli2 true true true false =
      φ • (pauli2 (tCZ true true true false).1.1 (tCZ true true true false).1.2
      (tCZ true true true false).2.1 (tCZ true true true false).2.2 * czM) := by
  pauli_sign2

private theorem conj_cz_tttt :
    ∃ φ, IsSign φ ∧ czM * pauli2 true true true true =
      φ • (pauli2 (tCZ true true true true).1.1 (tCZ true true true true).1.2
      (tCZ true true true true).2.1 (tCZ true true true true).2.2 * czM) := by
  pauli_sign2

private theorem conj_cy_ffff :
    ∃ φ, IsSign φ ∧ cyM * pauli2 false false false false =
      φ • (pauli2 (tCY false false false false).1.1 (tCY false false false false).1.2
      (tCY false false false false).2.1 (tCY false false false false).2.2 * cyM) := by
  pauli_sign2

private theorem conj_cy_ffft :
    ∃ φ, IsSign φ ∧ cyM * pauli2 false false false true =
      φ • (pauli2 (tCY false false false true).1.1 (tCY false false false true).1.2
      (tCY false false false true).2.1 (tCY false false false true).2.2 * cyM) := by
  pauli_sign2

private theorem conj_cy_fftf :
    ∃ φ, IsSign φ ∧ cyM * pauli2 false false true false =
      φ • (pauli2 (tCY false false true false).1.1 (tCY false false true false).1.2
      (tCY false false true false).2.1 (tCY false false true false).2.2 * cyM) := by
  pauli_sign2

private theorem conj_cy_fftt :
    ∃ φ, IsSign φ ∧ cyM * pauli2 false false true true =
      φ • (pauli2 (tCY false false true true).1.1 (tCY false false true true).1.2
      (tCY false false true true).2.1 (tCY false false true true).2.2 * cyM) := by
  pauli_sign2

private theorem conj_cy_ftff :
    ∃ φ, IsSign φ ∧ cyM * pauli2 false true false false =
      φ • (pauli2 (tCY false true false false).1.1 (tCY false true false false).1.2
      (tCY false true false false).2.1 (tCY false true false false).2.2 * cyM) := by
  pauli_sign2

private theorem conj_cy_ftft :
    ∃ φ, IsSign φ ∧ cyM * pauli2 false true false true =
      φ • (pauli2 (tCY false true false true).1.1 (tCY false true false true).1.2
      (tCY false true false true).2.1 (tCY false true false true).2.2 * cyM) := by
  pauli_sign2

private theorem conj_cy_fttf :
    ∃ φ, IsSign φ ∧ cyM * pauli2 false true true false =
      φ • (pauli2 (tCY false true true false).1.1 (tCY false true true false).1.2
      (tCY false true true false).2.1 (tCY false true true false).2.2 * cyM) := by
  pauli_sign2

private theorem conj_cy_fttt :
    ∃ φ, IsSign φ ∧ cyM * pauli2 false true true true =
      φ • (pauli2 (tCY false true true true).1.1 (tCY false true true true).1.2
      (tCY false true true true).2.1 (tCY false true true true).2.2 * cyM) := by
  pauli_sign2

private theorem conj_cy_tfff :
    ∃ φ, IsSign φ ∧ cyM * pauli2 true false false false =
      φ • (pauli2 (tCY true false false false).1.1 (tCY true false false false).1.2
      (tCY true false false false).2.1 (tCY true false false false).2.2 * cyM) := by
  pauli_sign2

private theorem conj_cy_tfft :
    ∃ φ, IsSign φ ∧ cyM * pauli2 true false false true =
      φ • (pauli2 (tCY true false false true).1.1 (tCY true false false true).1.2
      (tCY true false false true).2.1 (tCY true false false true).2.2 * cyM) := by
  pauli_sign2

private theorem conj_cy_tftf :
    ∃ φ, IsSign φ ∧ cyM * pauli2 true false true false =
      φ • (pauli2 (tCY true false true false).1.1 (tCY true false true false).1.2
      (tCY true false true false).2.1 (tCY true false true false).2.2 * cyM) := by
  pauli_sign2

private theorem conj_cy_tftt :
    ∃ φ, IsSign φ ∧ cyM * pauli2 true false true true =
      φ • (pauli2 (tCY true false true true).1.1 (tCY true false true true).1.2
      (tCY true false true true).2.1 (tCY true false true true).2.2 * cyM) := by
  pauli_sign2

private theorem conj_cy_ttff :
    ∃ φ, IsSign φ ∧ cyM * pauli2 true true false false =
      φ • (pauli2 (tCY true true false false).1.1 (tCY true true false false).1.2
      (tCY true true false false).2.1 (tCY true true false false).2.2 * cyM) := by
  pauli_sign2

private theorem conj_cy_ttft :
    ∃ φ, IsSign φ ∧ cyM * pauli2 true true false true =
      φ • (pauli2 (tCY true true false true).1.1 (tCY true true false true).1.2
      (tCY true true false true).2.1 (tCY true true false true).2.2 * cyM) := by
  pauli_sign2

private theorem conj_cy_tttf :
    ∃ φ, IsSign φ ∧ cyM * pauli2 true true true false =
      φ • (pauli2 (tCY true true true false).1.1 (tCY true true true false).1.2
      (tCY true true true false).2.1 (tCY true true true false).2.2 * cyM) := by
  pauli_sign2

private theorem conj_cy_tttt :
    ∃ φ, IsSign φ ∧ cyM * pauli2 true true true true =
      φ • (pauli2 (tCY true true true true).1.1 (tCY true true true true).1.2
      (tCY true true true true).2.1 (tCY true true true true).2.2 * cyM) := by
  pauli_sign2

private theorem conj_swap_ffff :
    ∃ φ, IsSign φ ∧ swapM * pauli2 false false false false =
      φ • (pauli2 false false false false * swapM) := by
  pauli_sign2

private theorem conj_swap_ffft :
    ∃ φ, IsSign φ ∧ swapM * pauli2 false false false true =
      φ • (pauli2 false true false false * swapM) := by
  pauli_sign2

private theorem conj_swap_fftf :
    ∃ φ, IsSign φ ∧ swapM * pauli2 false false true false =
      φ • (pauli2 true false false false * swapM) := by
  pauli_sign2

private theorem conj_swap_fftt :
    ∃ φ, IsSign φ ∧ swapM * pauli2 false false true true =
      φ • (pauli2 true true false false * swapM) := by
  pauli_sign2

private theorem conj_swap_ftff :
    ∃ φ, IsSign φ ∧ swapM * pauli2 false true false false =
      φ • (pauli2 false false false true * swapM) := by
  pauli_sign2

private theorem conj_swap_ftft :
    ∃ φ, IsSign φ ∧ swapM * pauli2 false true false true =
      φ • (pauli2 false true false true * swapM) := by
  pauli_sign2

private theorem conj_swap_fttf :
    ∃ φ, IsSign φ ∧ swapM * pauli2 false true true false =
      φ • (pauli2 true false false true * swapM) := by
  pauli_sign2

private theorem conj_swap_fttt :
    ∃ φ, IsSign φ ∧ swapM * pauli2 false true true true =
      φ • (pauli2 true true false true * swapM) := by
  pauli_sign2

private theorem conj_swap_tfff :
    ∃ φ, IsSign φ ∧ swapM * pauli2 true false false false =
      φ • (pauli2 false false true false * swapM) := by
  pauli_sign2

private theorem conj_swap_tfft :
    ∃ φ, IsSign φ ∧ swapM * pauli2 true false false true =
      φ • (pauli2 false true true false * swapM) := by
  pauli_sign2

private theorem conj_swap_tftf :
    ∃ φ, IsSign φ ∧ swapM * pauli2 true false true false =
      φ • (pauli2 true false true false * swapM) := by
  pauli_sign2

private theorem conj_swap_tftt :
    ∃ φ, IsSign φ ∧ swapM * pauli2 true false true true =
      φ • (pauli2 true true true false * swapM) := by
  pauli_sign2

private theorem conj_swap_ttff :
    ∃ φ, IsSign φ ∧ swapM * pauli2 true true false false =
      φ • (pauli2 false false true true * swapM) := by
  pauli_sign2

private theorem conj_swap_ttft :
    ∃ φ, IsSign φ ∧ swapM * pauli2 true true false true =
      φ • (pauli2 false true true true * swapM) := by
  pauli_sign2

private theorem conj_swap_tttf :
    ∃ φ, IsSign φ ∧ swapM * pauli2 true true true false =
      φ • (pauli2 true false true true * swapM) := by
  pauli_sign2

private theorem conj_swap_tttt :
    ∃ φ, IsSign φ ∧ swapM * pauli2 true true true true =
      φ • (pauli2 true true true true * swapM) := by
  pauli_sign2

theorem conj_cx (xc zc xt zt : Bool) :
    ∃ φ, IsSign φ ∧ cxM * pauli2 xc zc xt zt =
      φ • (pauli2 (tCX xc zc xt zt).1.1 (tCX xc zc xt zt).1.2
        (tCX xc zc xt zt).2.1 (tCX xc zc xt zt).2.2 * cxM) := by
  cases xc <;> cases zc <;> cases xt <;> cases zt
  exacts [conj_cx_ffff, conj_cx_ffft, conj_cx_fftf, conj_cx_fftt,
    conj_cx_ftff, conj_cx_ftft, conj_cx_fttf, conj_cx_fttt,
    conj_cx_tfff, conj_cx_tfft, conj_cx_tftf, conj_cx_tftt,
    conj_cx_ttff, conj_cx_ttft, conj_cx_tttf, conj_cx_tttt]

theorem conj_cz (xa za xb zb : Bool) :
    ∃ φ, IsSign φ ∧ czM * pauli2 xa za xb zb =
      φ • (pauli2 (tCZ xa za xb zb).1.1 (tCZ xa za xb zb).1.2
        (tCZ xa za xb zb).2.1 (tCZ xa za xb zb).2.2 * czM) := by
  cases xa <;> cases za <;> cases xb <;> cases zb
  exacts [conj_cz_ffff, conj_cz_ffft, conj_cz_fftf, conj_cz_fftt,
    conj_cz_ftff, conj_cz_ftft, conj_cz_fttf, conj_cz_fttt,
    conj_cz_tfff, conj_cz_tfft, conj_cz_tftf, conj_cz_tftt,
    conj_cz_ttff, conj_cz_ttft, conj_cz_tttf, conj_cz_tttt]

theorem conj_cy (xc zc xt zt : Bool) :
    ∃ φ, IsSign φ ∧ cyM * pauli2 xc zc xt zt =
      φ • (pauli2 (tCY xc zc xt zt).1.1 (tCY xc zc xt zt).1.2
        (tCY xc zc xt zt).2.1 (tCY xc zc xt zt).2.2 * cyM) := by
  cases xc <;> cases zc <;> cases xt <;> cases zt
  exacts [conj_cy_ffff, conj_cy_ffft, conj_cy_fftf, conj_cy_fftt,
    conj_cy_ftff, conj_cy_ftft, conj_cy_fttf, conj_cy_fttt,
    conj_cy_tfff, conj_cy_tfft, conj_cy_tftf, conj_cy_tftt,
    conj_cy_ttff, conj_cy_ttft, conj_cy_tttf, conj_cy_tttt]

theorem conj_swap (xa za xb zb : Bool) :
    ∃ φ, IsSign φ ∧ swapM * pauli2 xa za xb zb = φ • (pauli2 xb zb xa za * swapM) := by
  cases xa <;> cases za <;> cases xb <;> cases zb
  exacts [conj_swap_ffff, conj_swap_ffft, conj_swap_fftf, conj_swap_fftt,
    conj_swap_ftff, conj_swap_ftft, conj_swap_fttf, conj_swap_fttt,
    conj_swap_tfff, conj_swap_tfft, conj_swap_tftf, conj_swap_tftt,
    conj_swap_ttff, conj_swap_ttft, conj_swap_tttf, conj_swap_tttt]

end Qlin.Pauli
