import Qlin.Sem

/-!
# R1: structure of the denotation

- The denotation is additive (`den_add`, `den_zero`).
- A1 lifts from leaves to every op (`den_restrict`).
- A2 lifts from leaves to every op (`den_comm`).
- Bits an op does not write keep their value on the support
  (`supp_den`): this is A3 of the plan, derived from A1.
-/

namespace Qlin

variable {D : Type*} [AddCommMonoid D]

/-- The branches of `s` with nonzero weight have every bit of `W` false.
Before any op writes a bit, the bit holds 0 (`Known` in
`src/analysis/core.rs`). -/
def Supp (W : Finset Bit) (s : State D) : Prop :=
  ∀ β, s β ≠ 0 → ∀ b ∈ W, β b = false

theorem restrict_add (c : Cond) (s t : State D) :
    restrict c (s + t) = restrict c s + restrict c t := by
  ext β; unfold restrict; by_cases h : c.eval β <;> simp [h]

theorem restrict_zero (c : Cond) : restrict c (0 : State D) = 0 := by
  ext β; unfold restrict; by_cases h : c.eval β <;> simp [h]

theorem restrict_comm (c c' : Cond) (s : State D) :
    restrict c (restrict c' s) = restrict c' (restrict c s) := by
  ext β; unfold restrict; by_cases h : c.eval β <;> by_cases h' : c'.eval β <;> simp [h, h']

/-- A state splits into the branches where `c` holds and the rest. -/
theorem restrict_split (c : Cond) (s : State D) :
    restrict c s + restrict c.not s = s := by
  ext β; unfold restrict Cond.not; by_cases h : c.eval β <;> simp [h]

theorem Footprint.Disj.symm {f g : Footprint} (h : f.Disj g) : g.Disj f := by
  obtain ⟨h1, h2, h3, h4⟩ := h
  exact ⟨h1.symm, h2.symm, h4.symm, h3.symm⟩

theorem denB_append (I : Interp D) (A B : List Op) (s : State D) :
    denB I (A ++ B) s = denB I B (denB I A s) := by
  induction A generalizing s with
  | nil => simp [denB]
  | cons o os ih => simp [denB, ih]


private theorem fp_union_writes (f g : Footprint) : (f ∪ g).writes = f.writes ∪ g.writes := rfl
private theorem fp_union_reads (f g : Footprint) : (f ∪ g).reads = f.reads ∪ g.reads := rfl
private theorem fp_union_qubits (f g : Footprint) : (f ∪ g).qubits = f.qubits ∪ g.qubits := rfl

private theorem disj_union_right {f g g' : Footprint} (h : f.Disj (g ∪ g')) :
    f.Disj g ∧ f.Disj g' := by
  obtain ⟨h1, h2, h3, h4⟩ := h
  rw [fp_union_qubits, Finset.disjoint_union_right] at h1
  rw [fp_union_writes, Finset.disjoint_union_right] at h2 h4
  rw [fp_union_reads, Finset.disjoint_union_right] at h3
  exact ⟨⟨h1.1, h2.1, h3.1, h4.1⟩, ⟨h1.2, h2.2, h3.2, h4.2⟩⟩

private theorem loopIter_add (f : State D → State D) (hf : ∀ s t, f (s + t) = f s + f t)
    (c : Cond) (K : ℕ) (s t : State D) :
    loopIter f c K (s + t) = loopIter f c K s + loopIter f c K t := by
  induction K generalizing s t with
  | zero => rfl
  | succ K ih =>
    simp only [loopIter, hf, restrict_add, ih]
    abel

mutual
private theorem den_add_aux (I : Interp D) : ∀ (o : Op) (s t : State D),
    den I o (s + t) = den I o s + den I o t
  | .leaf i f, s, t => by simp only [den, map_add]
  | .ite c A B, s, t => by
    simp only [den, restrict_add, denB_add_aux I A, denB_add_aux I B]
    abel
  | .loop K body c, s, t => by
    simp only [den]
    exact loopIter_add _ (fun s t => denB_add_aux I body s t) c K s t
  | .switch G cs dflt, s, t => by
    simp only [den]
    exact denCases_add_aux I G cs dflt (denB_add_aux I dflt) s t
private theorem denB_add_aux (I : Interp D) : ∀ (l : List Op) (s t : State D),
    denB I l (s + t) = denB I l s + denB I l t
  | [], s, t => by simp only [denB]
  | o :: os, s, t => by simp only [denB, den_add_aux I o, denB_add_aux I os]
private theorem denCases_add_aux (I : Interp D) (G : Finset Bit) :
    ∀ (cs : List (Assign × List Op)) (dflt : List Op),
    (∀ s t, denB I dflt (s + t) = denB I dflt s + denB I dflt t) →
    ∀ (s t : State D),
      denCases I G cs dflt (s + t) = denCases I G cs dflt s + denCases I G cs dflt t
  | [], dflt, hd, s, t => by simp only [denCases]; exact hd s t
  | (v, blk) :: cs, dflt, hd, s, t => by
    simp only [denCases, restrict_add, denB_add_aux I blk, denCases_add_aux I G cs dflt hd]
    abel
end

/-- What a map `g` needs to commute with the denotation of every op whose
footprint satisfies `P`: it is additive, commutes with each leaf and each
condition that `P` allows, and `P` passes to both parts of a union.
`den_restrict` uses `g = restrict c`, `den_comm` uses `g = den I o'`. -/
private structure CommHyp (I : Interp D) (g : State D → State D) (P : Footprint → Prop) :
    Prop where
  hadd : ∀ s t, g (s + t) = g s + g t
  hleaf : ∀ i f, P f → ∀ s, g (I.leaf i f s) = I.leaf i f (g s)
  hcond : ∀ c : Cond, P ⟨∅, c.bits, ∅⟩ → ∀ s, g (restrict c s) = restrict c (g s)
  hunion : ∀ f f', P (f ∪ f') → P f ∧ P f'

/-- `g` commutes with a bounded loop when it commutes with the body and the exit test. -/
private theorem gen_loop (g : State D → State D) (hadd : ∀ s t, g (s + t) = g s + g t)
    (f : State D → State D) (c : Cond)
    (hf : ∀ s, g (f s) = f (g s)) (hc : ∀ s, g (restrict c s) = restrict c (g s))
    (hc' : ∀ s, g (restrict c.not s) = restrict c.not (g s)) :
    ∀ K s, g (loopIter f c K s) = loopIter f c K (g s) := by
  intro K
  induction K with
  | zero => intro s; rfl
  | succ K ih => intro s; simp only [loopIter]; rw [hadd, hc, hf, ih, hc', hf]

mutual
/-- Under `CommHyp I g P`, `g` commutes with the denotation of every op whose
footprint satisfies `P`. -/
private theorem gen_den {I : Interp D} {g : State D → State D} {P : Footprint → Prop}
    (H : CommHyp I g P) : ∀ (o : Op), P (Op.fp o) → ∀ s, g (den I o s) = den I o (g s)
  | .leaf i f, h, s => by
    simp only [Op.fp] at h
    simp only [den]; exact H.hleaf i f h s
  | .ite c A B, h, s => by
    simp only [Op.fp] at h
    obtain ⟨h1, hB⟩ := H.hunion _ _ h
    obtain ⟨hc, hA⟩ := H.hunion _ _ h1
    simp only [den]
    rw [H.hadd, gen_denB H A hA, gen_denB H B hB, H.hcond c hc, H.hcond c.not hc]
  | .loop K body c, h, s => by
    simp only [Op.fp] at h
    obtain ⟨hc, hb⟩ := H.hunion _ _ h
    simp only [den]
    exact gen_loop g H.hadd _ c (gen_denB H body hb) (H.hcond c hc) (H.hcond c.not hc) K s
  | .switch G cs dflt, h, s => by
    simp only [Op.fp] at h
    obtain ⟨h1, hd⟩ := H.hunion _ _ h
    obtain ⟨hG, hcs⟩ := H.hunion _ _ h1
    simp only [den]
    exact gen_cases H G cs dflt hcs (gen_denB H dflt hd) hG s
/-- `gen_den` for a block. -/
private theorem gen_denB {I : Interp D} {g : State D → State D} {P : Footprint → Prop}
    (H : CommHyp I g P) : ∀ (l : List Op), P (Op.fps l) → ∀ s, g (denB I l s) = denB I l (g s)
  | [], _, s => by simp only [denB]
  | o :: os, h, s => by
    simp only [Op.fps] at h
    obtain ⟨ho, hos⟩ := H.hunion _ _ h
    simp only [denB]
    rw [gen_denB H os hos, gen_den H o ho]
/-- `gen_den` for the cases of a switch. -/
private theorem gen_cases {I : Interp D} {g : State D → State D} {P : Footprint → Prop}
    (H : CommHyp I g P) (G : Finset Bit) : ∀ (cs : List (Assign × List Op)) (dflt : List Op),
    P (Op.fpsCases cs) → (∀ s, g (denB I dflt s) = denB I dflt (g s)) → P ⟨∅, G, ∅⟩ →
    ∀ s, g (denCases I G cs dflt s) = denCases I G cs dflt (g s)
  | [], dflt, _, hd, _, s => by simp only [denCases]; exact hd s
  | (v, blk) :: cs, dflt, h, hd, hG, s => by
    simp only [Op.fpsCases] at h
    obtain ⟨hb, hcs⟩ := H.hunion _ _ h
    simp only [denCases]
    rw [H.hadd, gen_denB H blk hb, gen_cases H G cs dflt hcs hd hG, H.hcond (Cond.matches G v) hG,
      H.hcond (Cond.matches G v).not hG]
end

theorem den_add (I : Interp D) (o : Op) (s t : State D) :
    den I o (s + t) = den I o s + den I o t :=
  den_add_aux I o s t

theorem den_zero (I : Interp D) (o : Op) : den I o 0 = 0 :=
  (gen_den (g := fun _ => (0 : State D)) (P := fun _ => True)
    ⟨fun _ _ => (add_zero 0).symm, fun i f _ _ => (map_zero (I.leaf i f)).symm,
      fun c _ _ => (restrict_zero c).symm, fun _ _ _ => ⟨trivial, trivial⟩⟩ o trivial 0).symm

theorem denB_add (I : Interp D) (l : List Op) (s t : State D) :
    denB I l (s + t) = denB I l s + denB I l t :=
  denB_add_aux I l s t

theorem denB_zero (I : Interp D) (l : List Op) : denB I l 0 = 0 :=
  (gen_denB (g := fun _ => (0 : State D)) (P := fun _ => True)
    ⟨fun _ _ => (add_zero 0).symm, fun i f _ _ => (map_zero (I.leaf i f)).symm,
      fun c _ _ => (restrict_zero c).symm, fun _ _ _ => ⟨trivial, trivial⟩⟩ l trivial 0).symm

private theorem restrict_commHyp (I : Interp D) (c : Cond) :
    CommHyp I (restrict c) (fun f => Disjoint c.bits f.writes) where
  hadd := restrict_add c
  hleaf i f hf s := (I.local_ i f c hf s).symm
  hcond c' _ s := restrict_comm c c' s
  hunion f f' hff := by
    simp only [fp_union_writes, Finset.disjoint_union_right] at hff; exact hff

/-- A1 for every op: an op commutes with a condition on bits it does not
write. -/
theorem den_restrict (I : Interp D) (o : Op) (c : Cond)
    (h : Disjoint c.bits (Op.fp o).writes) (s : State D) :
    den I o (restrict c s) = restrict c (den I o s) :=
  (gen_den (restrict_commHyp I c) o h s).symm

theorem denB_restrict (I : Interp D) (l : List Op) (c : Cond)
    (h : Disjoint c.bits (Op.fps l).writes) (s : State D) :
    denB I l (restrict c s) = restrict c (denB I l s) :=
  (gen_denB (restrict_commHyp I c) l h s).symm

private theorem leaf_comm_den (I : Interp D) (i : ℕ) (f : Footprint) (o : Op)
    (h : f.Disj (Op.fp o)) (s : State D) :
    I.leaf i f (den I o s) = den I o (I.leaf i f s) :=
  gen_den (g := I.leaf i f) (P := fun g => f.Disj g)
    ⟨map_add (I.leaf i f), fun j g hg s => I.comm i f j g hg s,
      fun c hc s => I.local_ i f c hc.2.2.1.symm s, fun _ _ hff => disj_union_right hff⟩ o h s

/-- A2 for every op: ops with disjoint footprints commute. -/
theorem den_comm (I : Interp D) (o o' : Op) (h : (Op.fp o).Disj (Op.fp o'))
    (s : State D) : den I o (den I o' s) = den I o' (den I o s) :=
  (gen_den (g := den I o') (P := fun g => (Op.fp o').Disj g)
    ⟨den_add I o', fun i f hf s => (leaf_comm_den I i f o' hf.symm s).symm,
      fun c hc s => den_restrict I o' c hc.2.2.1.symm s,
      fun _ _ hff => disj_union_right hff⟩ o h.symm s).symm

/-- An op that writes no bit of `W` keeps those bits false on the
support. -/
theorem supp_den (I : Interp D) (o : Op) (W : Finset Bit)
    (h : Disjoint W (Op.fp o).writes) (s : State D) (hs : Supp W s) :
    Supp W (den I o s) := by
  intro β hβ b hb
  set c := Cond.matches W (fun _ => false) with hcdef
  have hs' : restrict c s = s := by
    funext β'
    unfold restrict
    split_ifs with hc
    · rfl
    · by_contra hne
      apply hc
      simp only [hcdef, Cond.matches, decide_eq_true_eq]
      exact hs β' (Ne.symm hne)
  have key : den I o s = restrict c (den I o s) := by
    rw [← den_restrict I o c h s, hs']
  rw [key] at hβ
  unfold restrict at hβ
  split_ifs at hβ with hc
  · simp only [hcdef, Cond.matches, decide_eq_true_eq] at hc
    exact hc b hb
  · exact absurd rfl hβ

theorem supp_denB (I : Interp D) (l : List Op) (W : Finset Bit)
    (h : Disjoint W (Op.fps l).writes) (s : State D) (hs : Supp W s) :
    Supp W (denB I l s) := by
  intro β hβ b hb
  set c := Cond.matches W (fun _ => false) with hcdef
  have hs' : restrict c s = s := by
    funext β'
    unfold restrict
    split_ifs with hc
    · rfl
    · by_contra hne
      apply hc
      simp only [hcdef, Cond.matches, decide_eq_true_eq]
      exact hs β' (Ne.symm hne)
  have key : denB I l s = restrict c (denB I l s) := by
    rw [← denB_restrict I l c h s, hs']
  rw [key] at hβ
  unfold restrict at hβ
  split_ifs at hβ with hc
  · simp only [hcdef, Cond.matches, decide_eq_true_eq] at hc
    exact hc b hb
  · exact absurd rfl hβ

end Qlin
