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

theorem conj_h (x z : Bool) :
    ∃ φ, IsSign φ ∧ hM * pauli x z = φ • (pauli (tH x z).1 (tH x z).2 * hM) := by
  sorry

theorem conj_s (x z : Bool) :
    ∃ φ, IsSign φ ∧ sM * pauli x z = φ • (pauli (tS x z).1 (tS x z).2 * sM) := by
  sorry

theorem conj_sdg (x z : Bool) :
    ∃ φ, IsSign φ ∧ sdgM * pauli x z = φ • (pauli (tS x z).1 (tS x z).2 * sdgM) := by
  sorry

theorem conj_sx (x z : Bool) :
    ∃ φ, IsSign φ ∧ sxM * pauli x z = φ • (pauli (tSX x z).1 (tSX x z).2 * sxM) := by
  sorry

/-- x, y, and z leave every Pauli unchanged up to sign. -/
theorem conj_pauli (a b x z : Bool) :
    ∃ φ, IsSign φ ∧ pauli a b * pauli x z = φ • (pauli x z * pauli a b) := by
  sorry

theorem conj_cx (xc zc xt zt : Bool) :
    ∃ φ, IsSign φ ∧ cxM * pauli2 xc zc xt zt =
      φ • (pauli2 (tCX xc zc xt zt).1.1 (tCX xc zc xt zt).1.2
        (tCX xc zc xt zt).2.1 (tCX xc zc xt zt).2.2 * cxM) := by
  sorry

theorem conj_cz (xa za xb zb : Bool) :
    ∃ φ, IsSign φ ∧ czM * pauli2 xa za xb zb =
      φ • (pauli2 (tCZ xa za xb zb).1.1 (tCZ xa za xb zb).1.2
        (tCZ xa za xb zb).2.1 (tCZ xa za xb zb).2.2 * czM) := by
  sorry

theorem conj_cy (xc zc xt zt : Bool) :
    ∃ φ, IsSign φ ∧ cyM * pauli2 xc zc xt zt =
      φ • (pauli2 (tCY xc zc xt zt).1.1 (tCY xc zc xt zt).1.2
        (tCY xc zc xt zt).2.1 (tCY xc zc xt zt).2.2 * cyM) := by
  sorry

theorem conj_swap (xa za xb zb : Bool) :
    ∃ φ, IsSign φ ∧ swapM * pauli2 xa za xb zb = φ • (pauli2 xb zb xa za * swapM) := by
  sorry

end Qlin.Pauli
