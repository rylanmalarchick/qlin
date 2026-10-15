import Qlin.M0
import Qlin.FastPath

/-!
# Translation validation: a checker for compiled programs

The rule theorems of `M0.lean` and `FastPath.lean` say that each rewrite
preserves the denotation. This file closes the gap to the Rust code for
one compiled program at a time. `checkM0` decides whether a target block
follows from a source block by M0 steps (fold, hoist, merge, and
congruence into arms). `checkFP` decides whether a target is a fast path of
its input (dispatch steps). Both work on a syntactic copy of the IR whose
conditions are bit expressions, so every side condition is decidable.
`checkM0_sound` and `checkFP_sound` prove that a `true` answer implies
equal denotations for every interpretation.
-/

namespace Qlin.TV

open Qlin

/-- A Boolean expression over bits (`BitExpr` in `src/ir.rs`). -/
inductive SExpr where
  | const (v : Bool)
  | var (b : Bit)
  | not (e : SExpr)
  | and (a b : SExpr)
  | or (a b : SExpr)
  | xor (a b : SExpr)
  deriving DecidableEq, Repr

def SExpr.eval : SExpr → Assign → Bool
  | .const v, _ => v
  | .var b, β => β b
  | .not e, β => !e.eval β
  | .and a b, β => a.eval β && b.eval β
  | .or a b, β => a.eval β || b.eval β
  | .xor a b, β => Bool.xor (a.eval β) (b.eval β)

def SExpr.bits : SExpr → Finset Bit
  | .const _ => ∅
  | .var b => {b}
  | .not e => e.bits
  | .and a b => a.bits ∪ b.bits
  | .or a b => a.bits ∪ b.bits
  | .xor a b => a.bits ∪ b.bits

theorem SExpr.dep (e : SExpr) (β β' : Assign) (h : ∀ b ∈ e.bits, β b = β' b) :
    e.eval β = e.eval β' := by
  induction e with
  | const v => rfl
  | var b => exact h b (by simp [SExpr.bits])
  | not e ih => simp [SExpr.eval, ih h]
  | and a b iha ihb =>
    simp only [SExpr.eval, iha fun x hx => h x (by simp [SExpr.bits, hx]),
      ihb fun x hx => h x (by simp [SExpr.bits, hx])]
  | or a b iha ihb =>
    simp only [SExpr.eval, iha fun x hx => h x (by simp [SExpr.bits, hx]),
      ihb fun x hx => h x (by simp [SExpr.bits, hx])]
  | xor a b iha ihb =>
    simp only [SExpr.eval, iha fun x hx => h x (by simp [SExpr.bits, hx]),
      ihb fun x hx => h x (by simp [SExpr.bits, hx])]

/-- The condition of an expression. -/
def SExpr.toCond (e : SExpr) : Cond := ⟨e.eval, e.bits, e.dep⟩

/-- A leaf: an operation code (gate, measure, or reset), its qubits, the
bits it writes, and its parameters (as the bit patterns of the floats).
Two leaves denote the same operation iff they are equal. -/
structure SLeaf where
  kind : ℕ
  qubits : List ℕ
  writes : List ℕ
  params : List ℕ
  deriving DecidableEq, Repr

/-- An injective code for leaves: the leaf id of `Op.leaf`. -/
def SLeaf.code (l : SLeaf) : ℕ := Encodable.encode (l.kind, l.qubits, l.writes, l.params)

theorem SLeaf.code_injective : Function.Injective SLeaf.code := by
  intro a b h
  have := Encodable.encode_injective h
  cases a; cases b
  simp only [Prod.mk.injEq] at this
  obtain ⟨h1, h2, h3, h4⟩ := this
  subst h1 h2 h3 h4
  rfl

/-- The footprint a leaf declares. -/
def SLeaf.fp (l : SLeaf) : Footprint := ⟨l.qubits.toFinset, ∅, l.writes.toFinset⟩

/-- Syntactic ops. A switch case value lists one Boolean per bit of `G`. -/
inductive SOp where
  | leaf (l : SLeaf)
  | ite (c : SExpr) (A B : List SOp)
  | loop (K : ℕ) (body : List SOp) (c : SExpr)
  | switch (G : List Bit) (cases : List (List Bool × List SOp)) (dflt : List SOp)
  deriving Repr

mutual
def SOp.decEq : (a b : SOp) → Decidable (a = b)
  | .leaf l, .leaf l' =>
    if h : l = l' then isTrue (h ▸ rfl) else isFalse (by intro e; cases e; exact h rfl)
  | .ite c A B, .ite c' A' B' =>
    if hc : c = c' then
      match SOp.decEqL A A', SOp.decEqL B B' with
      | isTrue hA, isTrue hB => isTrue (by subst hc hA hB; rfl)
      | isFalse hA, _ => isFalse (by intro e; cases e; exact hA rfl)
      | _, isFalse hB => isFalse (by intro e; cases e; exact hB rfl)
    else isFalse (by intro e; cases e; exact hc rfl)
  | .loop K body c, .loop K' body' c' =>
    if hK : K = K' then
      if hc : c = c' then
        match SOp.decEqL body body' with
        | isTrue hb => isTrue (by subst hK hc hb; rfl)
        | isFalse hb => isFalse (by intro e; cases e; exact hb rfl)
      else isFalse (by intro e; cases e; exact hc rfl)
    else isFalse (by intro e; cases e; exact hK rfl)
  | .switch G cs d, .switch G' cs' d' =>
    if hG : G = G' then
      match SOp.decEqC cs cs', SOp.decEqL d d' with
      | isTrue hc, isTrue hd => isTrue (by subst hG hc hd; rfl)
      | isFalse hc, _ => isFalse (by intro e; cases e; exact hc rfl)
      | _, isFalse hd => isFalse (by intro e; cases e; exact hd rfl)
    else isFalse (by intro e; cases e; exact hG rfl)
  | .leaf _, .ite _ _ _ | .leaf _, .loop _ _ _ | .leaf _, .switch _ _ _
  | .ite _ _ _, .leaf _ | .ite _ _ _, .loop _ _ _ | .ite _ _ _, .switch _ _ _
  | .loop _ _ _, .leaf _ | .loop _ _ _, .ite _ _ _ | .loop _ _ _, .switch _ _ _
  | .switch _ _ _, .leaf _ | .switch _ _ _, .ite _ _ _ | .switch _ _ _, .loop _ _ _ =>
    isFalse (by intro e; cases e)

def SOp.decEqL : (a b : List SOp) → Decidable (a = b)
  | [], [] => isTrue rfl
  | [], _ :: _ => isFalse (by intro e; cases e)
  | _ :: _, [] => isFalse (by intro e; cases e)
  | x :: xs, y :: ys =>
    match SOp.decEq x y, SOp.decEqL xs ys with
    | isTrue h1, isTrue h2 => isTrue (by subst h1 h2; rfl)
    | isFalse h1, _ => isFalse (by intro e; cases e; exact h1 rfl)
    | _, isFalse h2 => isFalse (by intro e; cases e; exact h2 rfl)

def SOp.decEqC : (a b : List (List Bool × List SOp)) → Decidable (a = b)
  | [], [] => isTrue rfl
  | [], _ :: _ => isFalse (by intro e; cases e)
  | _ :: _, [] => isFalse (by intro e; cases e)
  | (v, x) :: xs, (w, y) :: ys =>
    if hv : v = w then
      match SOp.decEqL x y, SOp.decEqC xs ys with
      | isTrue h1, isTrue h2 => isTrue (by subst hv h1 h2; rfl)
      | isFalse h1, _ => isFalse (by intro e; cases e; exact h1 rfl)
      | _, isFalse h2 => isFalse (by intro e; cases e; exact h2 rfl)
    else isFalse (by intro e; cases e; exact hv rfl)
end

instance : DecidableEq SOp := SOp.decEq

/-- The assignment a case value names: bit `G[i]` is `v[i]`, others 0. -/
def assignOf (G : List Bit) (v : List Bool) : Assign := fun b =>
  match (G.zip v).find? (fun p => p.1 == b) with
  | some p => p.2
  | none => false

mutual
def SOp.toOp : SOp → Op
  | .leaf l => .leaf l.code l.fp
  | .ite c A B => .ite c.toCond (SOp.toOps A) (SOp.toOps B)
  | .loop K body c => .loop K (SOp.toOps body) c.toCond
  | .switch G cases dflt => .switch G.toFinset (SOp.toCases G cases) (SOp.toOps dflt)

def SOp.toOps : List SOp → List Op
  | [] => []
  | o :: os => SOp.toOp o :: SOp.toOps os

def SOp.toCases (G : List Bit) : List (List Bool × List SOp) → List (Assign × List Op)
  | [] => []
  | (v, blk) :: cs => (assignOf G v, SOp.toOps blk) :: SOp.toCases G cs
end

theorem SOp.toOps_eq_map (A : List SOp) : SOp.toOps A = A.map SOp.toOp := by
  induction A with
  | nil => simp [SOp.toOps]
  | cons o os ih => simp [SOp.toOps, ih]

theorem SOp.toOps_append (A B : List SOp) : SOp.toOps (A ++ B) = SOp.toOps A ++ SOp.toOps B := by
  induction A with
  | nil => simp [SOp.toOps]
  | cons o os ih => simp [SOp.toOps, ih]


/-! ## Footprints and support -/

instance (f g : Footprint) : Decidable (f.Disj g) := by unfold Footprint.Disj; infer_instance

/-- The bits an op writes. -/
def writesO (o : SOp) : Finset Bit := (Op.fp (SOp.toOp o)).writes

/-- The bits a block writes. -/
def writesL (l : List SOp) : Finset Bit := (Op.fps (SOp.toOps l)).writes

/-- `P` and `Q` have equal denotations, for every interpretation, on every
state whose support has the bits of `W` at 0. -/
def EqvOn (W : Finset Bit) (P Q : List Op) : Prop :=
  ∀ (D : Type) [AddCommMonoid D] (I : Interp D) (s : State D), Supp W s →
    denB I P s = denB I Q s

theorem supp_mono {D : Type} [AddCommMonoid D] {W W' : Finset Bit} (h : W' ⊆ W)
    {s : State D} (hs : Supp W s) : Supp W' s :=
  fun β hβ b hb => hs β hβ b (h hb)

theorem supp_restrict {D : Type} [AddCommMonoid D] {W : Finset Bit} (c : Cond)
    {s : State D} (hs : Supp W s) : Supp W (restrict c s) := by
  intro β hβ b hb
  unfold restrict at hβ
  split_ifs at hβ
  · exact hs β hβ b hb
  · exact absurd rfl hβ

theorem supp_after {D : Type} [AddCommMonoid D] (I : Interp D) (o : Op) {W : Finset Bit}
    {s : State D} (hs : Supp W s) : Supp (W \ (Op.fp o).writes) (den I o s) :=
  supp_den I o _ Finset.sdiff_disjoint s (supp_mono Finset.sdiff_subset hs)

theorem supp_afterB {D : Type} [AddCommMonoid D] (I : Interp D) (l : List Op) {W : Finset Bit}
    {s : State D} (hs : Supp W s) : Supp (W \ (Op.fps l).writes) (denB I l s) :=
  supp_denB I l _ Finset.sdiff_disjoint s (supp_mono Finset.sdiff_subset hs)

/-! ## Folding with known-zero bits -/

def andO : Option Bool → Option Bool → Option Bool
  | some false, _ => some false
  | _, some false => some false
  | some true, some true => some true
  | _, _ => none

def orO : Option Bool → Option Bool → Option Bool
  | some true, _ => some true
  | _, some true => some true
  | some false, some false => some false
  | _, _ => none

def xorO : Option Bool → Option Bool → Option Bool
  | some x, some y => some (Bool.xor x y)
  | _, _ => none

/-- Evaluation with partial knowledge `k` of the bits. -/
def SExpr.peval (k : Bit → Option Bool) : SExpr → Option Bool
  | .const v => some v
  | .var b => k b
  | .not e => (e.peval k).map (!·)
  | .and a b => andO (a.peval k) (b.peval k)
  | .or a b => orO (a.peval k) (b.peval k)
  | .xor a b => xorO (a.peval k) (b.peval k)

theorem SExpr.peval_sound (k : Bit → Option Bool) (β : Assign)
    (hk : ∀ b v, k b = some v → β b = v) (e : SExpr) :
    ∀ v, e.peval k = some v → e.eval β = v := by
  induction e with
  | const w => intro v h; simpa [SExpr.peval, SExpr.eval] using h
  | var b => intro v h; exact hk b v h
  | not e ih =>
    intro v h
    simp only [SExpr.peval, Option.map_eq_some_iff] at h
    obtain ⟨w, hw, rfl⟩ := h
    simp [SExpr.eval, ih w hw]
  | and a b iha ihb =>
    intro v h
    simp only [SExpr.peval] at h
    simp only [SExpr.eval]
    rcases ha : a.peval k with _ | _ | _ <;> rcases hb : b.peval k with _ | _ | _ <;>
      simp_all [andO]
  | or a b iha ihb =>
    intro v h
    simp only [SExpr.peval] at h
    simp only [SExpr.eval]
    rcases ha : a.peval k with _ | _ | _ <;> rcases hb : b.peval k with _ | _ | _ <;>
      simp_all [orO]
  | xor a b iha ihb =>
    intro v h
    simp only [SExpr.peval] at h
    simp only [SExpr.eval]
    rcases ha : a.peval k with _ | _ | _ <;> rcases hb : b.peval k with _ | _ | _ <;>
      simp_all [xorO]

/-- Bits of `W` read 0, others are unknown. -/
def knownZero (W : Finset Bit) (b : Bit) : Option Bool := if b ∈ W then some false else none

/-- `c` is `v` whenever the bits of `W` are 0. -/
def foldsTo (W : Finset Bit) (c : SExpr) (v : Bool) : Bool := c.peval (knownZero W) == some v

theorem foldsTo_sound {W : Finset Bit} {c : SExpr} {v : Bool} (h : foldsTo W c v = true)
    (β : Assign) (hβ : ∀ b ∈ W, β b = false) : c.toCond.eval β = v := by
  have hk : ∀ b w, knownZero W b = some w → β b = w := by
    intro b w hb
    unfold knownZero at hb
    split_ifs at hb with hbW
    · cases hb; exact hβ b hbW
  exact SExpr.peval_sound _ β hk c v (by simpa [foldsTo] using h)

/-! ## Hoist and merge on syntax -/

/-- Splits `A` at the first `x`, as `pA ++ x :: rest`, when every op of
`pA` is disjoint from `x`. -/
def takeOut (x : SOp) : List SOp → Option (List SOp × List SOp)
  | [] => none
  | y :: ys =>
    if y = x then some ([], ys)
    else if (Op.fp (SOp.toOp x)).Disj (Op.fp (SOp.toOp y)) then
      (takeOut x ys).map fun p => (y :: p.1, p.2)
    else none

theorem takeOut_spec (x : SOp) : ∀ (A pA r : List SOp), takeOut x A = some (pA, r) →
    A = pA ++ x :: r ∧ ∀ y ∈ pA, (Op.fp (SOp.toOp x)).Disj (Op.fp (SOp.toOp y)) := by
  intro A
  induction A with
  | nil => intro pA r h; simp [takeOut] at h
  | cons y ys ih =>
    intro pA r h
    unfold takeOut at h
    split_ifs at h with h1 h2
    · cases h; subst h1; simp
    · simp only [Option.map_eq_some_iff] at h
      obtain ⟨⟨p1, p2⟩, hp, he⟩ := h
      cases he
      obtain ⟨hA, hd⟩ := ih p1 p2 hp
      refine ⟨by simp [hA], ?_⟩
      intro z hz
      simp only [List.mem_cons] at hz
      rcases hz with rfl | hz
      · exact h2
      · exact hd z hz

/-- Hoists each op of `H`, in order, out of both arms. -/
def hoistAll (c : SExpr) : List SOp → List SOp → List SOp → Option (List SOp × List SOp)
  | [], A, B => some (A, B)
  | h :: H, A, B =>
    if Disjoint c.bits (Op.fp (SOp.toOp h)).writes then
      match takeOut h A, takeOut h B with
      | some (pA, A1), some (pB, B1) => hoistAll c H (pA ++ A1) (pB ++ B1)
      | _, _ => none
    else none

theorem hoistAll_spec (c : SExpr) : ∀ (H A B A' B' : List SOp), hoistAll c H A B = some (A', B') →
    ∀ (D : Type) [AddCommMonoid D] (I : Interp D) (s : State D),
      den I (.ite c.toCond (SOp.toOps A) (SOp.toOps B)) s =
        denB I (SOp.toOps H ++ [.ite c.toCond (SOp.toOps A') (SOp.toOps B')]) s := by
  intro H
  induction H with
  | nil => intro A B A' B' h D _ I s; simp [hoistAll] at h; obtain ⟨rfl, rfl⟩ := h; simp [SOp.toOps, denB]
  | cons x H ih =>
    intro A B A' B' h D _ I s
    unfold hoistAll at h
    split_ifs at h with hc
    split at h
    · rename_i pA A1 pB B1 hA hB
      obtain ⟨rfl, hdA⟩ := takeOut_spec x _ _ _ hA
      obtain ⟨rfl, hdB⟩ := takeOut_spec x _ _ _ hB
      have disj : ∀ (p : List SOp), (∀ y ∈ p, (Op.fp (SOp.toOp x)).Disj (Op.fp (SOp.toOp y))) →
          ∀ y ∈ SOp.toOps p, (Op.fp (SOp.toOp x)).Disj (Op.fp y) := by
        intro p hp y hy
        rw [SOp.toOps_eq_map, List.mem_map] at hy
        obtain ⟨z, hz, rfl⟩ := hy
        exact hp z hz
      have step := hoist_sound I c.toCond (SOp.toOp x) (SOp.toOps pA) (SOp.toOps A1)
        (SOp.toOps pB) (SOp.toOps B1) (disj pA hdA) (disj pB hdB) hc s
      have rest := ih _ _ _ _ h D I (den I (SOp.toOp x) s)
      rw [SOp.toOps_append, SOp.toOps_append] at rest
      simp only [SOp.toOps_append, SOp.toOps, denB] at step ⊢
      rw [step]
      simpa [denB_append, denB] using rest
    · simp at h

/-- Splits `A` at the last `x`, as `A1 ++ x :: sA`, when every op of `sA`
is disjoint from `x`. -/
def takeOutLast (x : SOp) (A : List SOp) : Option (List SOp × List SOp) :=
  (takeOut x A.reverse).map fun p => (p.2.reverse, p.1.reverse)

theorem takeOutLast_spec (x : SOp) (A A1 sA : List SOp) (h : takeOutLast x A = some (A1, sA)) :
    A = A1 ++ x :: sA ∧ ∀ y ∈ sA, (Op.fp (SOp.toOp x)).Disj (Op.fp (SOp.toOp y)) := by
  unfold takeOutLast at h
  simp only [Option.map_eq_some_iff] at h
  obtain ⟨⟨p, r⟩, hp, he⟩ := h
  simp only [Prod.mk.injEq] at he
  obtain ⟨rfl, rfl⟩ := he
  obtain ⟨hA, hd⟩ := takeOut_spec x _ _ _ hp
  refine ⟨?_, fun y hy => hd y (List.mem_reverse.1 hy)⟩
  have := congrArg List.reverse hA
  simpa using this

/-- Merges each op of `R` (the merged ops, last first) out of both arms. -/
def mergeRev (c : SExpr) : List SOp → List SOp → List SOp → Option (List SOp × List SOp)
  | [], A, B => some (A, B)
  | m :: R, A, B =>
    match takeOutLast m A, takeOutLast m B with
    | some (A1, sA), some (B1, sB) => mergeRev c R (A1 ++ sA) (B1 ++ sB)
    | _, _ => none

theorem mergeRev_spec (c : SExpr) : ∀ (R A B A' B' : List SOp), mergeRev c R A B = some (A', B') →
    ∀ (D : Type) [AddCommMonoid D] (I : Interp D) (s : State D),
      den I (.ite c.toCond (SOp.toOps A) (SOp.toOps B)) s =
        denB I (.ite c.toCond (SOp.toOps A') (SOp.toOps B') :: SOp.toOps R.reverse) s := by
  intro R
  induction R with
  | nil => intro A B A' B' h D _ I s; simp [mergeRev] at h; obtain ⟨rfl, rfl⟩ := h; simp [SOp.toOps, denB]
  | cons x R ih =>
    intro A B A' B' h D _ I s
    unfold mergeRev at h
    split at h
    · rename_i A1 sA B1 sB hA hB
      obtain ⟨rfl, hdA⟩ := takeOutLast_spec x _ _ _ hA
      obtain ⟨rfl, hdB⟩ := takeOutLast_spec x _ _ _ hB
      have disj : ∀ (p : List SOp), (∀ y ∈ p, (Op.fp (SOp.toOp x)).Disj (Op.fp (SOp.toOp y))) →
          ∀ y ∈ SOp.toOps p, (Op.fp (SOp.toOp x)).Disj (Op.fp y) := by
        intro p hp y hy
        rw [SOp.toOps_eq_map, List.mem_map] at hy
        obtain ⟨z, hz, rfl⟩ := hy
        exact hp z hz
      have step := merge_sound I c.toCond (SOp.toOp x) (SOp.toOps A1) (SOp.toOps sA)
        (SOp.toOps B1) (SOp.toOps sB) (disj sA hdA) (disj sB hdB) s
      have mid := ih _ _ _ _ h D I s
      simp only [SOp.toOps_append, SOp.toOps] at step mid ⊢
      rw [step]
      simp only [denB] at mid ⊢
      rw [mid, List.reverse_cons, SOp.toOps_append, denB_append]
      simp [SOp.toOps, denB]
    · simp at h

/-! ## The M0 checker -/

/-- Does `tgt` follow from `src` by M0 steps, on states whose support has
the bits of `W` at 0? `fuel` bounds the recursion. -/
def checkBlock : ℕ → Finset Bit → List SOp → List SOp → Bool
  | 0, _, _, _ => false
  | _ + 1, _, [], tgt => tgt.isEmpty
  | f + 1, W, o :: rest, tgt =>
    match o with
    | .ite c A B =>
      (foldsTo W c true && checkBlock f W (A ++ rest) tgt) ||
      (foldsTo W c false && checkBlock f W (B ++ rest) tgt) ||
      (List.range tgt.length).any fun j =>
        match tgt[j]? with
        | some (.ite c' A' B') =>
          decide (c = c') &&
          match hoistAll c (tgt.take j) A B with
          | none => false
          | some (A1, B1) =>
            (List.range (tgt.length - j)).any fun m =>
              match mergeRev c ((tgt.drop (j + 1)).take m).reverse A1 B1 with
              | none => false
              | some (A2, B2) =>
                checkBlock f (W \ writesL (tgt.take j)) A2 A' &&
                checkBlock f (W \ writesL (tgt.take j)) B2 B' &&
                checkBlock f (W \ writesO (.ite c A B)) rest ((tgt.drop (j + 1)).drop m)
        | _ => false
    | .leaf l =>
      match tgt with
      | .leaf l' :: tgt' => decide (l = l') && checkBlock f (W \ writesO (.leaf l)) rest tgt'
      | _ => false
    | .loop K body c =>
      match tgt with
      | .loop K' body' c' :: tgt' =>
        decide (K = K') && decide (c = c') && checkBlock f ∅ body body' &&
          checkBlock f (W \ writesO (.loop K body c)) rest tgt'
      | _ => false
    | .switch G cs d =>
      match tgt with
      | .switch G' cs' d' :: tgt' =>
        decide (G = G') && decide (cs.map Prod.fst = cs'.map Prod.fst) &&
          ((cs.zip cs').all fun p => checkBlock f ∅ p.1.2 p.2.2) &&
          checkBlock f ∅ d d' && checkBlock f (W \ writesO (.switch G cs d)) rest tgt'
      | _ => false

/-! ## Soundness of the M0 checker -/

theorem supp_empty {D : Type} [AddCommMonoid D] (s : State D) : Supp ∅ s :=
  fun _ _ _ hb => absurd hb (Finset.notMem_empty _)

theorem eqv_cons {W : Finset Bit} {o o' : Op} {rest rest' : List Op}
    (hhead : ∀ (D : Type) [AddCommMonoid D] (I : Interp D) (s : State D), Supp W s →
      den I o s = den I o' s)
    (htail : EqvOn (W \ (Op.fp o).writes) rest rest') : EqvOn W (o :: rest) (o' :: rest') := by
  intro D _ I s hs
  simp only [denB]
  rw [htail D I _ (supp_after I o hs), hhead D I s hs]

theorem eqv_trans {W : Finset Bit} {P Q R : List Op} (h1 : EqvOn W P Q) (h2 : EqvOn W Q R) :
    EqvOn W P R := fun D _ I s hs => (h1 D I s hs).trans (h2 D I s hs)

/-- A loop with an equivalent body (on every state) is equivalent. -/
theorem loop_congr {K : ℕ} {c : Cond} {body body' : List Op} (h : EqvOn ∅ body body')
    (D : Type) [AddCommMonoid D] (I : Interp D) (s : State D) :
    den I (.loop K body c) s = den I (.loop K body' c) s := by
  have hf : (fun t => denB I body t) = (fun t => denB I body' t) :=
    funext fun t => h D I t (supp_empty t)
  simp only [den, hf]

theorem cases_congr (G : List Bit) (G' : Finset Bit) {d d' : List Op} (hd : EqvOn ∅ d d') :
    ∀ (cs cs' : List (List Bool × List SOp)), cs.map Prod.fst = cs'.map Prod.fst →
      (∀ p ∈ cs.zip cs', EqvOn ∅ (SOp.toOps p.1.2) (SOp.toOps p.2.2)) →
      ∀ (D : Type) [AddCommMonoid D] (I : Interp D) (s : State D),
        denCases I G' (SOp.toCases G cs) d s = denCases I G' (SOp.toCases G cs') d' s := by
  intro cs
  induction cs with
  | nil =>
    intro cs' hv _ D _ I s
    cases cs' with
    | nil => simp only [SOp.toCases, denCases]; exact hd D I s (supp_empty s)
    | cons _ _ => simp at hv
  | cons p cs ih =>
    intro cs' hv hb D _ I s
    cases cs' with
    | nil => simp at hv
    | cons p' cs' =>
      obtain ⟨v, blk⟩ := p
      obtain ⟨v', blk'⟩ := p'
      simp only [List.map_cons, List.cons.injEq] at hv
      obtain ⟨rfl, hv⟩ := hv
      simp only [SOp.toCases, denCases]
      rw [hb ((v, blk), (v, blk')) (by simp) D I _ (supp_empty _),
        ih cs' hv (fun q hq => hb q (by simp [hq])) D I _]

theorem fold_eqv {W : Finset Bit} {c : SExpr} {A B rest : List SOp} {tgt : List Op} (v : Bool)
    (hf : foldsTo W c v = true)
    (h : EqvOn W (SOp.toOps ((if v then A else B) ++ rest)) tgt) :
    EqvOn W (SOp.toOp (.ite c A B) :: SOp.toOps rest) tgt := by
  intro D _ I s hs
  have hc := foldsTo_sound hf
  have e : den I (SOp.toOp (.ite c A B)) s = denB I (SOp.toOps (if v then A else B)) s := by
    cases v
    · exact fold_false I c.toCond _ _ W (fun β hβ => hc β hβ) s hs
    · exact fold_true I c.toCond _ _ W (fun β hβ => hc β hβ) s hs
  rw [← h D I s hs, SOp.toOps_append, denB_append]
  simp only [denB, e]

/-- One hoist-and-merge step of the checker, as an equivalence. -/
theorem ite_step {W : Finset Bit} {c : SExpr} {A B rest H A' B' M T' A1 B1 A2 B2 : List SOp}
    (hH : hoistAll c H A B = some (A1, B1))
    (hM : mergeRev c M.reverse A1 B1 = some (A2, B2))
    (hA : EqvOn (W \ writesL H) (SOp.toOps A2) (SOp.toOps A'))
    (hB : EqvOn (W \ writesL H) (SOp.toOps B2) (SOp.toOps B'))
    (hR : EqvOn (W \ writesO (.ite c A B)) (SOp.toOps rest) (SOp.toOps T')) :
    EqvOn W (SOp.toOps (.ite c A B :: rest)) (SOp.toOps (H ++ .ite c A' B' :: (M ++ T'))) := by
  intro D _ I s hs
  have hh := hoistAll_spec c H A B A1 B1 hH D I s
  have hm := mergeRev_spec c M.reverse A1 B1 A2 B2 hM D I (denB I (SOp.toOps H) s)
  rw [List.reverse_reverse] at hm
  have ht : Supp (W \ writesL H) (denB I (SOp.toOps H) s) := supp_afterB I _ hs
  have harms : den I (.ite c.toCond (SOp.toOps A2) (SOp.toOps B2)) (denB I (SOp.toOps H) s) =
      den I (.ite c.toCond (SOp.toOps A') (SOp.toOps B')) (denB I (SOp.toOps H) s) := by
    simp only [den]
    rw [hA D I _ (supp_restrict _ ht), hB D I _ (supp_restrict _ ht)]
  have key : den I (SOp.toOp (.ite c A B)) s =
      denB I (SOp.toOps (H ++ .ite c A' B' :: M)) s := by
    simp only [SOp.toOp]
    rw [hh, denB_append]
    simp only [denB]
    rw [hm]
    simp only [denB]
    rw [harms, SOp.toOps_append, denB_append]
    simp [SOp.toOps, denB, SOp.toOp]
  simp only [SOp.toOps, denB]
  rw [hR D I _ (supp_after I _ hs), key]
  simp only [SOp.toOps_append, denB_append, SOp.toOps, denB]

/-- A `true` answer of the M0 checker implies equal denotations. -/
theorem checkBlock_sound : ∀ (f : ℕ) (W : Finset Bit) (src tgt : List SOp),
    checkBlock f W src tgt = true → EqvOn W (SOp.toOps src) (SOp.toOps tgt) := by
  intro f
  induction f with
  | zero => intro W src tgt h; simp [checkBlock] at h
  | succ f ih =>
    intro W src tgt h
    cases src with
    | nil =>
      simp only [checkBlock, List.isEmpty_iff] at h
      subst h
      intro D _ I s _
      rfl
    | cons o rest =>
      cases o with
      | leaf l =>
        simp only [checkBlock] at h
        split at h
        · rename_i l' tgt'
          simp only [Bool.and_eq_true, decide_eq_true_eq] at h
          obtain ⟨rfl, ht⟩ := h
          simp only [SOp.toOps]
          exact eqv_cons (fun _ _ _ _ _ => rfl) (ih _ _ _ ht)
        · simp at h
      | loop K body c =>
        simp only [checkBlock] at h
        split at h
        · rename_i K' body' c' tgt'
          simp only [Bool.and_eq_true, decide_eq_true_eq] at h
          obtain ⟨⟨⟨rfl, rfl⟩, hb⟩, ht⟩ := h
          simp only [SOp.toOps, SOp.toOp]
          exact eqv_cons (fun D _ I s _ => loop_congr (ih _ _ _ hb) D I s) (ih _ _ _ ht)
        · simp at h
      | switch G cs d =>
        simp only [checkBlock] at h
        split at h
        · rename_i G' cs' d' tgt'
          simp only [Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at h
          obtain ⟨⟨⟨⟨rfl, hv⟩, hcs⟩, hd⟩, ht⟩ := h
          simp only [SOp.toOps, SOp.toOp]
          refine eqv_cons (fun D _ I s _ => ?_) (ih _ _ _ ht)
          simp only [den]
          exact cases_congr G _ (ih _ _ _ hd) cs cs' hv (fun p hp => ih _ _ _ (hcs p hp)) D I s
        · simp at h
      | ite c A B =>
        simp only [checkBlock, Bool.or_eq_true, Bool.and_eq_true] at h
        rcases h with (⟨hf, hr⟩ | ⟨hf, hr⟩) | hany
        · simp only [SOp.toOps]
          exact fold_eqv true hf (by simpa using ih _ _ _ hr)
        · simp only [SOp.toOps]
          exact fold_eqv false hf (by simpa using ih _ _ _ hr)
        · rw [List.any_eq_true] at hany
          obtain ⟨j, -, hm⟩ := hany
          split at hm
          · rename_i c' A' B' hget
            simp only [Bool.and_eq_true, decide_eq_true_eq] at hm
            obtain ⟨rfl, hm⟩ := hm
            split at hm
            · simp at hm
            · rename_i A1 B1 hH
              rw [List.any_eq_true] at hm
              obtain ⟨m, -, hm⟩ := hm
              split at hm
              · simp at hm
              · rename_i A2 B2 hM
                simp only [Bool.and_eq_true] at hm
                obtain ⟨⟨hA, hB⟩, hR⟩ := hm
                obtain ⟨hj, hget⟩ := List.getElem?_eq_some_iff.1 hget
                have htgt : tgt = tgt.take j ++ SOp.ite c A' B' ::
                    ((tgt.drop (j + 1)).take m ++ (tgt.drop (j + 1)).drop m) := by
                  rw [List.take_append_drop, ← hget, ← List.drop_eq_getElem_cons hj,
                    List.take_append_drop]
                rw [htgt]
                exact ite_step hH hM (ih _ _ _ hA) (ih _ _ _ hB) (ih _ _ _ hR)
          · simp at hm

/-! ## The fast-path checker -/

def isIteS : SOp → Bool
  | .ite _ _ _ => true
  | _ => false

/-- The arm of an If that `v` selects; other ops stay (`sel`). -/
def selS (v : Assign) : SOp → List SOp
  | .ite c A B => if c.eval v then A else B
  | o => [o]

def selectedS (v : Assign) (grp : List SOp) : List SOp := (grp.map (selS v)).flatten

theorem toOps_selS (v : Assign) (o : SOp) : SOp.toOps (selS v o) = sel v (SOp.toOp o) := by
  cases o with
  | ite c A B =>
    simp only [selS, SOp.toOp, sel, SExpr.toCond]
    split_ifs <;> rfl
  | leaf l => simp [selS, SOp.toOp, sel, SOp.toOps]
  | loop K b c => simp [selS, SOp.toOp, sel, SOp.toOps]
  | switch G cs d => simp [selS, SOp.toOp, sel, SOp.toOps]

theorem toOps_selectedS (v : Assign) (grp : List SOp) :
    SOp.toOps (selectedS v grp) = selected v (SOp.toOps grp) := by
  induction grp with
  | nil => simp [selectedS, selected, SOp.toOps]
  | cons o os ih =>
    simp only [selectedS, List.map_cons, List.flatten_cons, SOp.toOps_append] at ih ⊢
    rw [ih, toOps_selS]
    simp [selected, SOp.toOps]

theorem toCases_eq_map (G : List Bit) (cs : List (List Bool × List SOp)) :
    SOp.toCases G cs = cs.map fun p => (assignOf G p.1, SOp.toOps p.2) := by
  induction cs with
  | nil => simp [SOp.toCases]
  | cons p cs ih => obtain ⟨v, b⟩ := p; simp [SOp.toCases, ih]

/-- One dispatch: `T = [switch G cs P]`, `P` a group of Ifs on bits of `G`
that writes no bit of `G`, then the rest, and `rec` accepts each case body
against the arms its value selects, then the rest. -/
def fpSwitch (rec : List SOp → List SOp → Bool) (P T : List SOp) : Bool :=
  match T with
  | [.switch G cs dflt] =>
    decide (dflt = P) &&
    (List.range (P.length + 1)).any fun i =>
      (P.take i).all (fun o => match o with
        | .ite c _ _ => decide (c.bits ⊆ G.toFinset)
        | _ => false) &&
      decide (Disjoint G.toFinset (writesL (P.take i))) &&
      cs.all fun p => rec (selectedS (assignOf G p.1) (P.take i) ++ P.drop i) p.2
  | _ => false

/-- An equal head, and `rec` accepts the tails. -/
def fpHead (rec : List SOp → List SOp → Bool) (P T : List SOp) : Bool :=
  match T, P with
  | o :: T', o' :: P' => decide (o = o') && rec P' T'
  | _, _ => false

/-- Is `T` a fast path of `P`? Equal, or one dispatch, or an equal head and
a fast path of the tail. -/
def checkFP : ℕ → List SOp → List SOp → Bool
  | 0, _, _ => false
  | f + 1, P, T => decide (T = P) || fpSwitch (checkFP f) P T || fpHead (checkFP f) P T

/-- A `true` answer of the fast-path checker implies equal denotations. -/
theorem checkFP_sound : ∀ (f : ℕ) (P T : List SOp), checkFP f P T = true →
    ∀ (D : Type) [AddCommMonoid D] (I : Interp D) (s : State D),
      denB I (SOp.toOps T) s = denB I (SOp.toOps P) s := by
  intro f
  induction f with
  | zero => intro P T h; simp [checkFP] at h
  | succ f ih =>
    intro P T h D _ I s
    simp only [checkFP, Bool.or_eq_true, decide_eq_true_eq] at h
    rcases h with (rfl | h) | h
    · rfl
    · unfold fpSwitch at h
      split at h
      · rename_i G cs dflt
        simp only [Bool.and_eq_true, decide_eq_true_eq, List.any_eq_true] at h
        obtain ⟨rfl, i, -, ⟨⟨hbits, hw⟩, hcs⟩⟩ := h
        rw [List.all_eq_true] at hbits hcs
        simp only [SOp.toOps, SOp.toOp, denB]
        rw [← List.take_append_drop i dflt, SOp.toOps_append]
        refine fastpath_step I G.toFinset _ _ _ ?_ ?_ ?_ s
        · intro o ho c A B hoc
          rw [SOp.toOps_eq_map, List.mem_map] at ho
          obtain ⟨x, hx, rfl⟩ := ho
          have hb := hbits x hx
          cases x with
          | ite c' A' B' =>
            simp only [SOp.toOp, Op.ite.injEq] at hoc
            rw [← hoc.1]
            simpa using hb
          | leaf l => simp [SOp.toOp] at hoc
          | loop K b c => simp [SOp.toOp] at hoc
          | switch G cs d => simp [SOp.toOp] at hoc
        · simpa [writesL] using hw
        · intro p hp t
          rw [toCases_eq_map, List.mem_map] at hp
          obtain ⟨⟨v, B⟩, hvB, rfl⟩ := hp
          have := ih _ _ (hcs (v, B) hvB) D I t
          rw [SOp.toOps_append, toOps_selectedS] at this
          exact this
      · simp at h
    · unfold fpHead at h
      split at h
      · rename_i o T' o' P'
        simp only [Bool.and_eq_true, decide_eq_true_eq] at h
        obtain ⟨rfl, ht⟩ := h
        simp only [SOp.toOps, denB]
        exact ih _ _ ht D I _
      · simp at h

end Qlin.TV





