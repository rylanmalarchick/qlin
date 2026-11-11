import Qlin.Block

/-!
# The block model: monotonicity

`hoist_block_can_delay` (Block.lean) shows that a hoisted branch can add
latency in the block model. This file builds the tools for the positive
side: the block replay is monotone in its start state, in the controller
time, and in its gate bits (`runK_mono`, `runKB_mono`).
-/

namespace Qlin

open scoped NNReal

/-- `a` is no later than `b` in the block model: the replay state is no
later, and the controller is free no later. -/
def BState.Le (a b : BState) : Prop := a.st.Le b.st ∧ a.free ≤ b.free

theorem BState.Le.refl (a : BState) : a.Le a := ⟨TState.Le.refl _, le_rfl⟩

theorem BState.Le.trans {a b c : BState} (h1 : a.Le b) (h2 : b.Le c) : a.Le c :=
  ⟨h1.1.trans h2.1, h1.2.trans h2.2⟩

/-- The gate time is monotone in the state and in the gate bits. -/
theorem gateTime_mono (C : Cost) {a b : TState} (h : a.Le b) {g1 g2 : Finset Bit}
    (hg : g1 ⊆ g2) : gateTime C a g1 ≤ gateTime C b g2 := by
  unfold gateTime
  refine Finset.sup_le fun z hz => ?_
  refine le_trans ?_ (Finset.le_sup (f := fun z => match b.measEnd z with
    | some t => t + C.tff
    | none => 0) (hg hz))
  have hz' := h.2.2.2.2 z
  cases ha : a.measEnd z with
  | none => simp
  | some t =>
    cases hb : b.measEnd z with
    | none => rw [ha, hb] at hz'; exact absurd hz' (by simp [OptLe])
    | some t' =>
      rw [ha, hb] at hz'
      simp only [OptLe] at hz'
      simpa using hz'

theorem stall_mono (C : BCost) (f : Footprint) (bits : Finset Bit) {g1 g2 : Finset Bit}
    (hg : g1 ⊆ g2) (n : ℕ) {a b : BState} (h : a.Le b) :
    (stall C f bits g1 n a).Le (stall C f bits g2 n b) := by
  have ht : max (max (gateTime C.base a.st bits) (gateTime C.base a.st g1)) a.free + C.tb * n ≤
      max (max (gateTime C.base b.st bits) (gateTime C.base b.st g2)) b.free + C.tb * n := by
    gcongr
    · exact gateTime_mono C.base h.1 (Finset.Subset.refl _)
    · exact gateTime_mono C.base h.1 hg
    · exact h.2
  refine ⟨⟨h.1.1, h.1.2.1, h.1.2.2.1, fun q => ?_, h.1.2.2.2.2⟩, ht⟩
  simp only [stall]
  split_ifs
  · exact max_le_max (h.1.2.2.2.1 q) ht
  · exact h.1.2.2.2.1 q

theorem loopK_mono (body1 body2 : Finset Bit → BState → BState) (stl1 stl2 : BState → BState)
    (c : Cond) (g1 g2 : Finset Bit) (hg : g1 ⊆ g2)
    (hbody : ∀ g g' a b, g ⊆ g' → BState.Le a b → (body1 g a).Le (body2 g' b))
    (hstl : ∀ a b, BState.Le a b → (stl1 a).Le (stl2 b)) :
    ∀ (k : ℕ) (first : Bool) (a b : BState), a.Le b →
      (loopK body1 stl1 c g1 k first a).Le (loopK body2 stl2 c g2 k first b)
  | 0, _, a, b, hab => by
    simp only [loopK]
    exact ⟨⟨hab.1.1, hab.1.2.1, rfl, hab.1.2.2.2.1, hab.1.2.2.2.2⟩, hab.2⟩
  | k + 1, first, a, b, hab => by
    have hg' : (if first = true then g1 else g1 ∪ c.bits) ⊆
        (if first = true then g2 else g2 ∪ c.bits) := by
      cases first
      · exact Finset.union_subset_union hg (Finset.Subset.refl _)
      · exact hg
    have h1 := hbody _ _ a b hg' hab
    simp only [loopK]
    generalize body1 (if first = true then g1 else g1 ∪ c.bits) a = x at h1 ⊢
    generalize body2 (if first = true then g2 else g2 ∪ c.bits) b = y at h1 ⊢
    have h2 : (if x.st.stopped = true then x else stl1 x).Le
        (if y.st.stopped = true then y else stl2 y) := by
      rw [h1.1.2.2.1]
      split_ifs
      · exact h1
      · exact hstl x y h1
    generalize (if x.st.stopped = true then x else stl1 x) = x' at h2 ⊢
    generalize (if y.st.stopped = true then y else stl2 y) = y' at h2 ⊢
    rw [h2.1.2.2.1, h2.1.1]
    split_ifs
    · exact h2
    · exact loopK_mono body1 body2 stl1 stl2 c g1 g2 hg hbody hstl k false x' y' h2

mutual
/-- The block replay is monotone in the start state and the gate bits. -/
theorem runK_mono (C : BCost) (R : Record) : ∀ (o : Op) (g1 g2 : Finset Bit), g1 ⊆ g2 →
    ∀ a b : BState, a.Le b → (runK C R o g1 a).Le (runK C R o g2 b)
  | .leaf i f, g1, g2, hg, a, b, hab => by
    simp only [runK]
    have h := run_mono C.base R (.leaf i f) g1 g2 hg a.st b.st hab.1
    simp only [run] at h
    exact ⟨h, hab.2⟩
  | .ite c A B, g1, g2, hg, a, b, hab => by
    have hst := stall_mono C (Op.fp (.ite c A B)) c.bits hg 1 hab
    have hg' : g1 ∪ c.bits ⊆ g2 ∪ c.bits := Finset.union_subset_union hg (Finset.Subset.refl _)
    simp only [runK]
    rw [hab.1.2.2.1, hab.1.1]
    split_ifs
    · exact hab
    · exact runKB_mono C R A _ _ hg' _ _ hst
    · exact runKB_mono C R B _ _ hg' _ _ hst
  | .loop K body c, g1, g2, hg, a, b, hab => by
    simp only [runK]
    rw [hab.1.2.2.1]
    split_ifs
    · exact hab
    · exact loopK_mono _ _ _ _ c g1 g2 hg
        (fun g g' a' b' h1 h2 => runKB_mono C R body g g' h1 a' b' h2)
        (fun a' b' h => stall_mono C _ c.bits hg 1 h) K true a b hab
  | .switch G cs dflt, g1, g2, hg, a, b, hab => by
    have hg' : g1 ∪ G ⊆ g2 ∪ G := Finset.union_subset_union hg (Finset.Subset.refl _)
    simp only [runK]
    rw [hab.1.2.2.1, hab.1.1]
    split_ifs
    · exact hab
    · exact runKCases_mono C R G cs dflt _ _ hg'
        (fun a' b' h => runKB_mono C R dflt _ _ hg' a' b' h) _ _ (stall_mono C _ G hg _ hab)

theorem runKB_mono (C : BCost) (R : Record) : ∀ (l : List Op) (g1 g2 : Finset Bit), g1 ⊆ g2 →
    ∀ a b : BState, a.Le b → (runKB C R l g1 a).Le (runKB C R l g2 b)
  | [], _, _, _, a, b, hab => by simp only [runKB]; exact hab
  | o :: os, g1, g2, hg, a, b, hab => by
    simp only [runKB]
    exact runKB_mono C R os g1 g2 hg _ _ (runK_mono C R o g1 g2 hg a b hab)

theorem runKCases_mono (C : BCost) (R : Record) (G : Finset Bit) :
    ∀ (cs : List (Assign × List Op)) (dflt : List Op) (g1 g2 : Finset Bit), g1 ⊆ g2 →
    (∀ a b : BState, a.Le b → (runKB C R dflt g1 a).Le (runKB C R dflt g2 b)) →
    ∀ a b : BState, a.Le b →
      (runKCases C R G cs dflt g1 a).Le (runKCases C R G cs dflt g2 b)
  | [], dflt, g1, g2, _, hd, a, b, hab => by
    simp only [runKCases]
    exact hd a b hab
  | (v, blk) :: cs, dflt, g1, g2, hg, hd, a, b, hab => by
    simp only [runKCases]
    rw [hab.1.1]
    split_ifs
    · exact runKB_mono C R blk g1 g2 hg a b hab
    · exact runKCases_mono C R G cs dflt g1 g2 hg hd a b hab
end

/-! ### A leaf as a state update, and independence

`put R f er em` is the effect of a leaf with footprint `f` that ends at
`er` on its qubits and records `em` as the end of its measurements.
`runK_put`: an op whose footprint is disjoint from `f`, under gate bits
that `f` does not write, runs the same before and after the update. -/

theorem Footprint.union_qubits (f g : Footprint) : (f ∪ g).qubits = f.qubits ∪ g.qubits := rfl
theorem Footprint.union_reads (f g : Footprint) : (f ∪ g).reads = f.reads ∪ g.reads := rfl
theorem Footprint.union_writes (f g : Footprint) : (f ∪ g).writes = f.writes ∪ g.writes := rfl

theorem Footprint.disj_union_right {f g h : Footprint} :
    f.Disj (g ∪ h) ↔ f.Disj g ∧ f.Disj h := by
  simp only [Footprint.Disj, Footprint.union_qubits, Footprint.union_reads,
    Footprint.union_writes, Finset.disjoint_union_right]
  tauto

theorem TState.ext' {a b : TState} (h1 : a.ready = b.ready) (h2 : a.measEnd = b.measEnd)
    (h3 : a.vals = b.vals) (h4 : a.cursor = b.cursor) (h5 : a.stopped = b.stopped) : a = b := by
  cases a; cases b; simp_all

/-- The update of a leaf with footprint `f`. -/
def put (R : Record) (f : Footprint) (er em : ℝ≥0) (st : TState) : TState :=
  { ready := fun q => if q ∈ f.qubits then er else st.ready q
    measEnd := fun b => if b ∈ f.writes then some em else st.measEnd b
    vals := fun b => if b ∈ f.writes then R b (st.cursor b) else st.vals b
    cursor := fun b => if b ∈ f.writes then st.cursor b + 1 else st.cursor b
    stopped := st.stopped }

def putB (R : Record) (f : Footprint) (er em : ℝ≥0) (s : BState) : BState :=
  ⟨put R f er em s.st, s.free⟩

theorem leafT_eq_put (C : Cost) (R : Record) (i : ℕ) (f : Footprint) (g : Finset Bit)
    (st : TState) (h : st.stopped = false) :
    leafT C R i f g st =
      put R f (max (gateTime C st g) (f.qubits.sup st.ready) + C.dur i f)
        (max (gateTime C st g) (f.qubits.sup st.ready) + C.dur i f) st := by
  simp [leafT, put, h]

theorem gateTime_put (C : Cost) (R : Record) (f : Footprint) (er em : ℝ≥0) (st : TState)
    (g : Finset Bit) (hg : Disjoint g f.writes) :
    gateTime C (put R f er em st) g = gateTime C st g := by
  unfold gateTime
  refine Finset.sup_congr rfl fun z hz => ?_
  simp [put, Finset.disjoint_left.1 hg hz]

theorem eval_put (R : Record) (f : Footprint) (er em : ℝ≥0) (st : TState) (c : Cond)
    (hc : Disjoint c.bits f.writes) : c.eval (put R f er em st).vals = c.eval st.vals :=
  c.dep _ _ fun z hz => by simp [put, Finset.disjoint_left.1 hc hz]

theorem agrees_put (R : Record) (f : Footprint) (er em : ℝ≥0) (st : TState) (G : Finset Bit)
    (v : Assign) (hG : Disjoint G f.writes) :
    agrees G (put R f er em st).vals v ↔ agrees G st.vals v := by
  unfold agrees
  refine forall₂_congr fun z hz => ?_
  simp [put, Finset.disjoint_left.1 hG hz]

theorem armIdx_put (R : Record) (f : Footprint) (er em : ℝ≥0) (st : TState) (G : Finset Bit)
    (hG : Disjoint G f.writes) : ∀ cs : List (Assign × List Op),
    armIdx G (put R f er em st).vals cs = armIdx G st.vals cs
  | [] => rfl
  | (v, _) :: cs => by
    simp only [armIdx, armIdx_put R f er em st G hG cs]
    by_cases h : agrees G st.vals v
    · rw [if_pos h, if_pos ((agrees_put R f er em st G v hG).2 h)]
    · rw [if_neg h, if_neg (fun h' => h ((agrees_put R f er em st G v hG).1 h'))]

/-- A leaf on a disjoint footprint commutes with the update. -/
theorem leafT_put (C : Cost) (R : Record) (j : ℕ) (f' : Footprint) (g : Finset Bit)
    (f : Footprint) (er em : ℝ≥0) (st : TState)
    (hq : Disjoint f.qubits f'.qubits) (hw : Disjoint f.writes f'.writes)
    (hg : Disjoint g f.writes) :
    leafT C R j f' g (put R f er em st) = put R f er em (leafT C R j f' g st) := by
  have hsup : f'.qubits.sup (put R f er em st).ready = f'.qubits.sup st.ready :=
    Finset.sup_congr rfl fun q hq' => by simp [put, Finset.disjoint_right.1 hq hq']
  by_cases hs : st.stopped = true
  · have hs' : (put R f er em st).stopped = true := hs
    simp [leafT, hs, hs']
  · have hs0 : st.stopped = false := by simpa using hs
    have hs' : (put R f er em st).stopped = false := hs0
    unfold leafT
    rw [if_neg (by simp [hs']), if_neg (by simp [hs0]), gateTime_put C R f er em st g hg, hsup]
    apply TState.ext'
    · funext q
      by_cases h1 : q ∈ f'.qubits
      · have h2 : q ∉ f.qubits := Finset.disjoint_right.1 hq h1
        simp [put, h1, h2]
      · simp [put, h1]
    · funext b
      by_cases h1 : b ∈ f'.writes
      · have h2 : b ∉ f.writes := Finset.disjoint_right.1 hw h1
        simp [put, h1, h2]
      · simp [put, h1]
    · funext b
      by_cases h1 : b ∈ f'.writes
      · have h2 : b ∉ f.writes := Finset.disjoint_right.1 hw h1
        simp [put, h1, h2]
      · simp [put, h1]
    · funext b
      by_cases h1 : b ∈ f'.writes
      · have h2 : b ∉ f.writes := Finset.disjoint_right.1 hw h1
        simp [put, h1, h2]
      · simp [put, h1]
    · rfl

/-- A controller step of a branch on disjoint qubits commutes with the update. -/
theorem stall_put (C : BCost) (R : Record) (F : Footprint) (bits g : Finset Bit) (n : ℕ)
    (f : Footprint) (er em : ℝ≥0) (s : BState)
    (hq : Disjoint f.qubits F.qubits) (hb : Disjoint bits f.writes) (hg : Disjoint g f.writes) :
    stall C F bits g n (putB R f er em s) = putB R f er em (stall C F bits g n s) := by
  simp only [stall, putB, gateTime_put C.base R f er em s.st bits hb,
    gateTime_put C.base R f er em s.st g hg]
  congr 1
  apply TState.ext'
  · funext q
    by_cases h1 : q ∈ F.qubits
    · have h2 : q ∉ f.qubits := Finset.disjoint_right.1 hq h1
      simp [put, h1, h2]
    · simp [put, h1]
  · rfl
  · rfl
  · rfl
  · rfl

theorem loopK_put (R : Record) (f : Footprint) (er em : ℝ≥0)
    (body : Finset Bit → BState → BState) (stl : BState → BState) (c : Cond) (g : Finset Bit)
    (hc : Disjoint c.bits f.writes) (hg : Disjoint g f.writes)
    (hbody : ∀ g' s, Disjoint g' f.writes → body g' (putB R f er em s) = putB R f er em (body g' s))
    (hstl : ∀ s, stl (putB R f er em s) = putB R f er em (stl s)) :
    ∀ (k : ℕ) (first : Bool) (s : BState),
      loopK body stl c g k first (putB R f er em s) = putB R f er em (loopK body stl c g k first s)
  | 0, _, s => by
    simp only [loopK, putB]
    congr 1
  | k + 1, first, s => by
    have hg' : Disjoint (if first = true then g else g ∪ c.bits) f.writes := by
      cases first
      · exact Finset.disjoint_union_left.2 ⟨hg, hc⟩
      · exact hg
    simp only [loopK]
    rw [hbody _ s hg']
    generalize body (if first = true then g else g ∪ c.bits) s = x
    have hx : (putB R f er em x).st.stopped = x.st.stopped := rfl
    rw [hx]
    by_cases h1 : x.st.stopped = true
    · rw [if_pos h1, if_pos h1]
      have h2 : (putB R f er em x).st.stopped = true := h1
      simp [h1, h2]
    · rw [if_neg h1, if_neg h1, hstl x]
      generalize stl x = y
      have hy : (putB R f er em y).st.stopped = y.st.stopped := rfl
      have hv : c.eval (putB R f er em y).st.vals = c.eval y.st.vals :=
        eval_put R f er em y.st c hc
      rw [hy, hv]
      split_ifs
      · rfl
      · exact loopK_put R f er em body stl c g hc hg hbody hstl k false y

mutual
/-- Independence: an op on a disjoint footprint, under gate bits that `f`
does not write, commutes with the update of `f`. -/
theorem runK_put (C : BCost) (R : Record) (f : Footprint) (er em : ℝ≥0) :
    ∀ (o : Op) (g : Finset Bit) (s : BState), f.Disj (Op.fp o) → Disjoint g f.writes →
      runK C R o g (putB R f er em s) = putB R f er em (runK C R o g s)
  | .leaf j f', g, s, hD, hg => by
    simp only [runK, putB]
    congr 1
    exact leafT_put C.base R j f' g f er em s.st hD.1 hD.2.1 hg
  | .ite c A B, g, s, hD, hg => by
    have hD' := hD
    simp only [Op.fp] at hD'
    obtain ⟨h1, hDB⟩ := Footprint.disj_union_right.1 hD'
    obtain ⟨hDc, hDA⟩ := Footprint.disj_union_right.1 h1
    have hc : Disjoint c.bits f.writes := hDc.2.2.1.symm
    have hg' : Disjoint (g ∪ c.bits) f.writes := Finset.disjoint_union_left.2 ⟨hg, hc⟩
    have hst := stall_put C R (Op.fp (.ite c A B)) c.bits g 1 f er em s hD.1 hc hg
    have hs : (putB R f er em s).st.stopped = s.st.stopped := rfl
    have hv : c.eval (putB R f er em s).st.vals = c.eval s.st.vals := eval_put R f er em s.st c hc
    simp only [runK]
    rw [hs, hv, hst]
    split_ifs
    · rfl
    · exact runKB_put C R f er em A _ _ hDA hg'
    · exact runKB_put C R f er em B _ _ hDB hg'
  | .loop K body c, g, s, hD, hg => by
    have hD' := hD
    simp only [Op.fp] at hD'
    obtain ⟨hDc, hDb⟩ := Footprint.disj_union_right.1 hD'
    have hc : Disjoint c.bits f.writes := hDc.2.2.1.symm
    have hs : (putB R f er em s).st.stopped = s.st.stopped := rfl
    simp only [runK]
    rw [hs]
    split_ifs
    · rfl
    · exact loopK_put R f er em _ _ c g hc hg
        (fun g' s' hg' => runKB_put C R f er em body g' s' hDb hg')
        (fun s' => stall_put C R _ c.bits g 1 f er em s' hD.1 hc hg) K true s
  | .switch G cs dflt, g, s, hD, hg => by
    have hD' := hD
    simp only [Op.fp] at hD'
    obtain ⟨h1, hDd⟩ := Footprint.disj_union_right.1 hD'
    obtain ⟨hDG, hDcs⟩ := Footprint.disj_union_right.1 h1
    have hG : Disjoint G f.writes := hDG.2.2.1.symm
    have hg' : Disjoint (g ∪ G) f.writes := Finset.disjoint_union_left.2 ⟨hg, hG⟩
    have hs : (putB R f er em s).st.stopped = s.st.stopped := rfl
    have hi : armIdx G (putB R f er em s).st.vals cs = armIdx G s.st.vals cs :=
      armIdx_put R f er em s.st G hG cs
    simp only [runK]
    rw [hs, hi, stall_put C R _ G g _ f er em s hD.1 hG hg]
    split_ifs
    · rfl
    · exact runKCases_put C R f er em G cs dflt _ hG hDcs
        (fun s' => runKB_put C R f er em dflt _ s' hDd hg') _ hg'

theorem runKB_put (C : BCost) (R : Record) (f : Footprint) (er em : ℝ≥0) :
    ∀ (l : List Op) (g : Finset Bit) (s : BState), f.Disj (Op.fps l) → Disjoint g f.writes →
      runKB C R l g (putB R f er em s) = putB R f er em (runKB C R l g s)
  | [], _, _, _, _ => by simp only [runKB]
  | o :: os, g, s, hD, hg => by
    have hD' := hD
    simp only [Op.fps] at hD'
    obtain ⟨hDo, hDos⟩ := Footprint.disj_union_right.1 hD'
    simp only [runKB]
    rw [runK_put C R f er em o g s hDo hg]
    exact runKB_put C R f er em os g _ hDos hg

theorem runKCases_put (C : BCost) (R : Record) (f : Footprint) (er em : ℝ≥0) (G : Finset Bit) :
    ∀ (cs : List (Assign × List Op)) (dflt : List Op) (g : Finset Bit),
    Disjoint G f.writes → f.Disj (Op.fpsCases cs) →
    (∀ s, runKB C R dflt g (putB R f er em s) = putB R f er em (runKB C R dflt g s)) →
    ∀ s : BState, Disjoint g f.writes →
      runKCases C R G cs dflt g (putB R f er em s) = putB R f er em (runKCases C R G cs dflt g s)
  | [], dflt, g, _, _, hd, s, _ => by
    simp only [runKCases]
    exact hd s
  | (v, blk) :: cs, dflt, g, hG, hD, hd, s, hg => by
    have hD' := hD
    simp only [Op.fpsCases] at hD'
    obtain ⟨hDb, hDcs⟩ := Footprint.disj_union_right.1 hD'
    have ha : agrees G (putB R f er em s).st.vals v ↔ agrees G s.st.vals v :=
      agrees_put R f er em s.st G v hG
    simp only [runKCases]
    by_cases h : agrees G s.st.vals v
    · rw [if_pos h, if_pos (ha.2 h)]
      exact runKB_put C R f er em blk g s hDb hg
    · rw [if_neg h, if_neg (fun h' => h (ha.1 h'))]
      exact runKCases_put C R f er em G cs dflt g hG hDcs hd s hg
end

/-! ### Frame: what a block run leaves alone

`Frm C F g a b`: from `a` to `b`, `ready` is unchanged outside the qubits
of `F`, `measEnd` is unchanged outside the writes of `F`, and the gate
time of every set of gate bits inside `g` only grows. -/

structure Frm (C : Cost) (F : Footprint) (g : Finset Bit) (a b : TState) : Prop where
  ready : ∀ q, q ∉ F.qubits → b.ready q = a.ready q
  meas : ∀ z, z ∉ F.writes → b.measEnd z = a.measEnd z
  vals : ∀ z, z ∉ F.writes → b.vals z = a.vals z
  grow : ∀ g0, g0 ⊆ g → gateTime C a g0 ≤ gateTime C b g0

theorem Frm.refl (C : Cost) (F : Footprint) (g : Finset Bit) (a : TState) : Frm C F g a a :=
  ⟨fun _ _ => rfl, fun _ _ => rfl, fun _ _ => rfl, fun _ _ => le_rfl⟩

theorem Frm.trans {C : Cost} {F : Footprint} {g : Finset Bit} {a b c : TState}
    (h1 : Frm C F g a b) (h2 : Frm C F g b c) : Frm C F g a c :=
  ⟨fun q hq => (h2.ready q hq).trans (h1.ready q hq),
    fun z hz => (h2.meas z hz).trans (h1.meas z hz),
    fun z hz => (h2.vals z hz).trans (h1.vals z hz),
    fun g0 hg0 => (h1.grow g0 hg0).trans (h2.grow g0 hg0)⟩

theorem Frm.mono {C : Cost} {F F' : Footprint} {g g' : Finset Bit} {a b : TState}
    (h : Frm C F g a b) (hq : F.qubits ⊆ F'.qubits) (hw : F.writes ⊆ F'.writes) (hg : g' ⊆ g) :
    Frm C F' g' a b :=
  ⟨fun q hq' => h.ready q fun h' => hq' (hq h'), fun z hz => h.meas z fun h' => hz (hw h'),
    fun z hz => h.vals z fun h' => hz (hw h'), fun g0 hg0 => h.grow g0 (hg0.trans hg)⟩

/-- The gate time of `g0` when `measEnd` agrees on `g0`. -/
theorem gateTime_congr (C : Cost) (a b : TState) (g0 : Finset Bit)
    (h : ∀ z ∈ g0, b.measEnd z = a.measEnd z) : gateTime C b g0 = gateTime C a g0 := by
  unfold gateTime
  exact Finset.sup_congr rfl fun z hz => by rw [h z hz]

theorem leafT_frm (C : Cost) (R : Record) (i : ℕ) (f : Footprint) (g : Finset Bit)
    (st : TState) : Frm C f g st (leafT C R i f g st) := by
  by_cases hs : st.stopped = true
  · have : leafT C R i f g st = st := by simp [leafT, hs]
    rw [this]
    exact Frm.refl C f g st
  · have hs0 : st.stopped = false := by simpa using hs
    rw [leafT_eq_put C R i f g st hs0]
    refine ⟨fun q hq => by simp [put, hq], fun z hz => by simp [put, hz],
      fun z hz => by simp [put, hz], fun g0 hg0 => ?_⟩
    unfold gateTime
    refine Finset.sup_le fun z hz => ?_
    refine le_trans ?_ (Finset.le_sup (f := fun z =>
      match (put R f (max (gateTime C st g) (f.qubits.sup st.ready) + C.dur i f)
        (max (gateTime C st g) (f.qubits.sup st.ready) + C.dur i f) st).measEnd z with
      | some t => t + C.tff
      | none => 0) hz)
    by_cases hw : z ∈ f.writes
    · have h1 : (match st.measEnd z with
          | some t => t + C.tff
          | none => 0) ≤ gateTime C st g := by
        unfold gateTime
        exact Finset.le_sup (f := fun z => match st.measEnd z with
          | some t => t + C.tff
          | none => 0) (hg0 hz)
      simp only [put, hw, if_true]
      exact h1.trans ((le_max_left _ _).trans (le_self_add.trans le_self_add))
    · simp only [put, if_neg hw]
      exact le_rfl

theorem stall_frm (C : BCost) (F : Footprint) (bits g : Finset Bit) (n : ℕ) (g' : Finset Bit)
    (s : BState) : Frm C.base F g' s.st (stall C F bits g n s).st :=
  ⟨fun q hq => by simp [stall, hq], fun _ _ => rfl, fun _ _ => rfl,
    fun g0 _ => le_of_eq (gateTime_congr C.base _ _ g0 fun _ _ => rfl).symm⟩

theorem loopK_frm (C : Cost) (F : Footprint) (c : Cond) (g : Finset Bit)
    (body : Finset Bit → BState → BState) (stl : BState → BState)
    (hbody : ∀ g' s, g ⊆ g' → Frm C F g s.st (body g' s).st)
    (hstl : ∀ s, Frm C F g s.st (stl s).st) :
    ∀ (k : ℕ) (first : Bool) (s : BState), Frm C F g s.st (loopK body stl c g k first s).st
  | 0, _, s => by
    simp only [loopK]
    exact ⟨fun _ _ => rfl, fun _ _ => rfl, fun _ _ => rfl,
      fun g0 _ => le_of_eq (gateTime_congr C _ _ g0 fun _ _ => rfl).symm⟩
  | k + 1, first, s => by
    have hg' : g ⊆ (if first = true then g else g ∪ c.bits) := by
      cases first
      · exact Finset.subset_union_left
      · exact Finset.Subset.refl _
    have h1 := hbody _ s hg'
    simp only [loopK]
    generalize body (if first = true then g else g ∪ c.bits) s = x at h1 ⊢
    have h2 : Frm C F g s.st (if x.st.stopped = true then x else stl x).st := by
      split_ifs
      · exact h1
      · exact h1.trans (hstl x)
    generalize (if x.st.stopped = true then x else stl x) = y at h2 ⊢
    split_ifs
    · exact h2
    · exact h2.trans (loopK_frm C F c g body stl hbody hstl k false y)

theorem fps_sub_ite_left (c : Cond) (A B : List Op) :
    (Op.fps A).qubits ⊆ (Op.fp (.ite c A B)).qubits ∧
      (Op.fps A).writes ⊆ (Op.fp (.ite c A B)).writes := by
  simp only [Op.fp, Footprint.union_qubits, Footprint.union_writes]
  exact ⟨Finset.subset_union_right.trans Finset.subset_union_left,
    Finset.subset_union_right.trans Finset.subset_union_left⟩

theorem fps_sub_ite_right (c : Cond) (A B : List Op) :
    (Op.fps B).qubits ⊆ (Op.fp (.ite c A B)).qubits ∧
      (Op.fps B).writes ⊆ (Op.fp (.ite c A B)).writes := by
  simp only [Op.fp, Footprint.union_qubits, Footprint.union_writes]
  exact ⟨Finset.subset_union_right, Finset.subset_union_right⟩

mutual
/-- A block-model run of `o` under `g` changes only the footprint of `o`,
and the gate times inside `g` only grow. -/
theorem runK_frm (C : BCost) (R : Record) : ∀ (o : Op) (g : Finset Bit) (s : BState),
    Frm C.base (Op.fp o) g s.st (runK C R o g s).st
  | .leaf i f, g, s => by
    simp only [runK, Op.fp]
    exact leafT_frm C.base R i f g s.st
  | .ite c A B, g, s => by
    have hst := stall_frm C (Op.fp (.ite c A B)) c.bits g 1 g s
    simp only [runK]
    split_ifs
    · exact Frm.refl _ _ _ _
    · exact hst.trans ((runKB_frm C R A _ _).mono (fps_sub_ite_left c A B).1
        (fps_sub_ite_left c A B).2 Finset.subset_union_left)
    · exact hst.trans ((runKB_frm C R B _ _).mono (fps_sub_ite_right c A B).1
        (fps_sub_ite_right c A B).2 Finset.subset_union_left)
  | .loop K body c, g, s => by
    have hq : (Op.fps body).qubits ⊆ (Op.fp (.loop K body c)).qubits := by
      simp only [Op.fp, Footprint.union_qubits]; exact Finset.subset_union_right
    have hw : (Op.fps body).writes ⊆ (Op.fp (.loop K body c)).writes := by
      simp only [Op.fp, Footprint.union_writes]; exact Finset.subset_union_right
    simp only [runK]
    split_ifs
    · exact Frm.refl _ _ _ _
    · exact loopK_frm C.base _ c g _ _
        (fun g' s' hg' => (runKB_frm C R body g' s').mono hq hw hg')
        (fun s' => stall_frm C _ c.bits g 1 g s') K true s
  | .switch G cs dflt, g, s => by
    have hqd : (Op.fps dflt).qubits ⊆ (Op.fp (.switch G cs dflt)).qubits := by
      simp only [Op.fp, Footprint.union_qubits]; exact Finset.subset_union_right
    have hwd : (Op.fps dflt).writes ⊆ (Op.fp (.switch G cs dflt)).writes := by
      simp only [Op.fp, Footprint.union_writes]; exact Finset.subset_union_right
    have hqc : (Op.fpsCases cs).qubits ⊆ (Op.fp (.switch G cs dflt)).qubits := by
      simp only [Op.fp, Footprint.union_qubits]
      exact Finset.subset_union_right.trans Finset.subset_union_left
    have hwc : (Op.fpsCases cs).writes ⊆ (Op.fp (.switch G cs dflt)).writes := by
      simp only [Op.fp, Footprint.union_writes]
      exact Finset.subset_union_right.trans Finset.subset_union_left
    simp only [runK]
    split_ifs
    · exact Frm.refl _ _ _ _
    · refine (stall_frm C _ G g (C.dec G.card cs.length (armIdx G s.st.vals cs)) g s).trans ?_
      exact (runKCases_frm C R G cs dflt (g ∪ G) (Op.fp (.switch G cs dflt)) hqc hwc
        (fun s' => (runKB_frm C R dflt _ s').mono hqd hwd (Finset.Subset.refl _)) _).mono
        (Finset.Subset.refl _) (Finset.Subset.refl _) Finset.subset_union_left

theorem runKB_frm (C : BCost) (R : Record) : ∀ (l : List Op) (g : Finset Bit) (s : BState),
    Frm C.base (Op.fps l) g s.st (runKB C R l g s).st
  | [], g, s => by simp only [runKB]; exact Frm.refl _ _ _ _
  | o :: os, g, s => by
    simp only [runKB, Op.fps]
    exact ((runK_frm C R o g s).mono (by simp [Footprint.union_qubits])
      (by simp [Footprint.union_writes]) (Finset.Subset.refl _)).trans
      ((runKB_frm C R os g _).mono (by simp [Footprint.union_qubits])
        (by simp [Footprint.union_writes]) (Finset.Subset.refl _))

theorem runKCases_frm (C : BCost) (R : Record) (G : Finset Bit) :
    ∀ (cs : List (Assign × List Op)) (dflt : List Op) (g : Finset Bit) (F : Footprint),
    (Op.fpsCases cs).qubits ⊆ F.qubits → (Op.fpsCases cs).writes ⊆ F.writes →
    (∀ s, Frm C.base F g s.st (runKB C R dflt g s).st) →
    ∀ s : BState, Frm C.base F g s.st (runKCases C R G cs dflt g s).st
  | [], dflt, g, F, _, _, hd, s => by
    simp only [runKCases]
    exact hd s
  | (v, blk) :: cs, dflt, g, F, hq, hw, hd, s => by
    simp only [Op.fpsCases, Footprint.union_qubits, Footprint.union_writes] at hq hw
    simp only [runKCases]
    split_ifs
    · exact (runKB_frm C R blk g s).mono (Finset.subset_union_left.trans hq)
        (Finset.subset_union_left.trans hw) (Finset.Subset.refl _)
    · exact runKCases_frm C R G cs dflt g F (Finset.subset_union_right.trans hq)
        (Finset.subset_union_right.trans hw) hd s
end

/-! ### C1 in the block model, for a hoisted or merged leaf -/

theorem optLe_refl' (x : Option ℝ≥0) : OptLe x x := by cases x <;> simp [OptLe]

/-- The end time of a leaf (`leafT`). -/
def leafEnd (C : Cost) (i : ℕ) (f : Footprint) (g : Finset Bit) (st : TState) : ℝ≥0 :=
  max (gateTime C st g) (f.qubits.sup st.ready) + C.dur i f

theorem runKB_nil (C : BCost) (R : Record) (g : Finset Bit) (s : BState) :
    runKB C R [] g s = s := by simp only [runKB]

theorem runKB_cons (C : BCost) (R : Record) (o : Op) (os : List Op) (g : Finset Bit)
    (s : BState) : runKB C R (o :: os) g s = runKB C R os g (runK C R o g s) := by
  simp only [runKB]

theorem runKB_appendK (C : BCost) (R : Record) (l1 l2 : List Op) (g : Finset Bit)
    (s : BState) : runKB C R (l1 ++ l2) g s = runKB C R l2 g (runKB C R l1 g s) := by
  induction l1 generalizing s with
  | nil => simp only [List.nil_append, runKB]
  | cons o os ih => simp only [List.cons_append, runKB, ih]

theorem runK_stoppedK (C : BCost) (R : Record) (o : Op) (g : Finset Bit) (s : BState)
    (h : s.st.stopped = true) : runK C R o g s = s := by
  cases o <;> simp [runK, leafT, h]

theorem runKB_stoppedK (C : BCost) (R : Record) (l : List Op) (g : Finset Bit) (s : BState)
    (h : s.st.stopped = true) : runKB C R l g s = s := by
  induction l with
  | nil => simp only [runKB]
  | cons o os ih => simp only [runKB, runK_stoppedK C R o g s h, ih]

theorem runK_leaf_put (C : BCost) (R : Record) (i : ℕ) (f : Footprint) (g : Finset Bit)
    (s : BState) (hs : s.st.stopped = false) :
    runK C R (.leaf i f) g s =
      putB R f (leafEnd C.base i f g s.st) (leafEnd C.base i f g s.st) s := by
  simp only [runK, putB, leafEnd]
  rw [← leafT_eq_put C.base R i f g s.st hs]

theorem runK_ite (C : BCost) (R : Record) (c : Cond) (A B : List Op) (g : Finset Bit)
    (s : BState) (hs : s.st.stopped = false) :
    runK C R (.ite c A B) g s =
      if c.eval s.st.vals then
        runKB C R A (g ∪ c.bits) (stall C (Op.fp (.ite c A B)) c.bits g 1 s)
      else runKB C R B (g ∪ c.bits) (stall C (Op.fp (.ite c A B)) c.bits g 1 s) := by
  simp only [runK, hs, Bool.false_eq_true, if_false]

theorem evalB_put (R : Record) (f : Footprint) (er em : ℝ≥0) (s : BState) (c : Cond)
    (hc : Disjoint c.bits f.writes) : c.eval (putB R f er em s).st.vals = c.eval s.st.vals :=
  eval_put R f er em s.st c hc

theorem disj_fps (f : Footprint) :
    ∀ (p : List Op), (∀ y ∈ p, f.Disj (Op.fp y)) → f.Disj (Op.fps p)
  | [], _ => by simp [Op.fps, Footprint.Disj, Footprint.empty]
  | o :: os, h => by
    simp only [Op.fps]
    exact Footprint.disj_union_right.2
      ⟨h o (by simp), disj_fps f os fun y hy => h y (by simp [hy])⟩

theorem disj_fps_writes (g : Finset Bit) :
    ∀ (l : List Op), (∀ y ∈ l, Disjoint g (Op.fp y).writes) → Disjoint g (Op.fps l).writes
  | [], _ => by simp [Op.fps, Footprint.empty]
  | o :: os, h => by
    simp only [Op.fps, Footprint.union_writes, Finset.disjoint_union_right]
    exact ⟨h o (by simp), disj_fps_writes g os fun y hy => h y (by simp [hy])⟩

theorem fps_append_qubits : ∀ (l1 l2 : List Op),
    (Op.fps (l1 ++ l2)).qubits = (Op.fps l1).qubits ∪ (Op.fps l2).qubits
  | [], l2 => by simp [Op.fps, Footprint.empty]
  | o :: os, l2 => by
    simp only [List.cons_append, Op.fps, Footprint.union_qubits, fps_append_qubits os l2,
      Finset.union_assoc]

/-- Two updates of the same leaf: the later one on a later state is later. -/
theorem putB_le (R : Record) (f : Footprint) {er er' em em' : ℝ≥0} {a b : BState}
    (hab : a.Le b) (her : ∀ q ∈ f.qubits, er ≤ er') (hem : em ≤ em') :
    (putB R f er em a).Le (putB R f er' em' b) := by
  obtain ⟨⟨hv, hc, hs, hr, hm⟩, hf⟩ := hab
  refine ⟨⟨?_, ?_, hs, fun q => ?_, fun z => ?_⟩, hf⟩
  · show (fun z => if z ∈ f.writes then R z (a.st.cursor z) else a.st.vals z) =
      (fun z => if z ∈ f.writes then R z (b.st.cursor z) else b.st.vals z)
    rw [hv, hc]
  · show (fun z => if z ∈ f.writes then a.st.cursor z + 1 else a.st.cursor z) =
      (fun z => if z ∈ f.writes then b.st.cursor z + 1 else b.st.cursor z)
    rw [hc]
  · show (if q ∈ f.qubits then er else a.st.ready q) ≤ (if q ∈ f.qubits then er' else b.st.ready q)
    by_cases h : q ∈ f.qubits
    · rw [if_pos h, if_pos h]; exact her q h
    · rw [if_neg h, if_neg h]; exact hr q
  · show OptLe (if z ∈ f.writes then some em else a.st.measEnd z)
      (if z ∈ f.writes then some em' else b.st.measEnd z)
    by_cases h : z ∈ f.writes
    · rw [if_pos h, if_pos h]; exact hem
    · rw [if_neg h, if_neg h]; exact hm z

/-- A controller step with a smaller footprint is no later. -/
theorem stall_sub_le (C : BCost) (Ft Fs : Footprint) (bits g : Finset Bit) (n : ℕ) (s : BState)
    (hF : Ft.qubits ⊆ Fs.qubits) : (stall C Ft bits g n s).Le (stall C Fs bits g n s) := by
  refine ⟨⟨rfl, rfl, rfl, fun q => ?_, fun z => optLe_refl' _⟩, le_rfl⟩
  show (if q ∈ Ft.qubits then max (s.st.ready q) (stall C Fs bits g n s).free else s.st.ready q) ≤
    (if q ∈ Fs.qubits then max (s.st.ready q) (stall C Fs bits g n s).free else s.st.ready q)
  by_cases h2 : q ∈ Ft.qubits
  · simp only [if_pos h2, if_pos (hF h2), le_refl]
  · simp only [if_neg h2]
    split_ifs <;> simp

/-- The controller step of the target `if` after the hoisted leaf, against
the leaf's update after the controller step of the source `if`. -/
theorem stall_putB_le (C : BCost) (R : Record) (Ft Fs : Footprint) (bits g : Finset Bit) (n : ℕ)
    (f : Footprint) (er em : ℝ≥0) (s : BState) (hF : Ft.qubits ⊆ Fs.qubits)
    (hb : Disjoint bits f.writes) (hg : Disjoint g f.writes) :
    (stall C Ft bits g n (putB R f er em s)).Le
      (putB R f (max er (stall C Fs bits g n s).free) em (stall C Fs bits g n s)) := by
  have ht : (stall C Ft bits g n (putB R f er em s)).free = (stall C Fs bits g n s).free := by
    show max (max (gateTime C.base (put R f er em s.st) bits)
        (gateTime C.base (put R f er em s.st) g)) s.free + C.tb * n =
      max (max (gateTime C.base s.st bits) (gateTime C.base s.st g)) s.free + C.tb * n
    rw [gateTime_put C.base R f er em s.st bits hb, gateTime_put C.base R f er em s.st g hg]
  refine ⟨⟨rfl, rfl, rfl, fun q => ?_, fun z => optLe_refl' _⟩, le_of_eq ht⟩
  have hl : (stall C Ft bits g n (putB R f er em s)).st.ready q =
      if q ∈ Ft.qubits then
        max (if q ∈ f.qubits then er else s.st.ready q) (stall C Fs bits g n s).free
      else (if q ∈ f.qubits then er else s.st.ready q) := by
    rw [← ht]; rfl
  have hr : (putB R f (max er (stall C Fs bits g n s).free) em (stall C Fs bits g n s)).st.ready q =
      if q ∈ f.qubits then max er (stall C Fs bits g n s).free
      else (if q ∈ Fs.qubits then max (s.st.ready q) (stall C Fs bits g n s).free
        else s.st.ready q) := rfl
  rw [hl, hr]
  generalize (stall C Fs bits g n s).free = t
  by_cases h1 : q ∈ f.qubits
  · simp only [if_pos h1]
    split_ifs <;> simp
  · simp only [if_neg h1]
    by_cases h2 : q ∈ Ft.qubits
    · simp only [if_pos h2, if_pos (hF h2), le_refl]
    · simp only [if_neg h2]
      split_ifs <;> simp

/-- One arm of a hoist. -/
theorem hoist_branch_K (C : BCost) (R : Record) (c : Cond) (i : ℕ) (f : Footprint)
    (p Z : List Op) (Ft Fs : Footprint) (g : Finset Bit) (s : BState)
    (hF : Ft.qubits ⊆ Fs.qubits) (hfF : f.qubits ⊆ Fs.qubits)
    (hp : ∀ y ∈ p, f.Disj (Op.fp y)) (hc : Disjoint c.bits f.writes)
    (henc : Disjoint g f.writes)
    (hrun : (runKB C R (p ++ .leaf i f :: Z) (g ∪ c.bits)
      (stall C Fs c.bits g 1 s)).st.stopped = false) :
    (runKB C R (p ++ Z) (g ∪ c.bits)
      (stall C Ft c.bits g 1 (putB R f (leafEnd C.base i f g s.st) (leafEnd C.base i f g s.st) s))).Le
      (runKB C R (p ++ .leaf i f :: Z) (g ∪ c.bits) (stall C Fs c.bits g 1 s)) := by
  have hw : Disjoint (g ∪ c.bits) f.writes := Finset.disjoint_union_left.2 ⟨henc, hc⟩
  have hpD := disj_fps f p hp
  rw [runKB_appendK] at hrun ⊢
  rw [runKB_appendK, runKB_cons] at *
  have hS1 : (runKB C R p (g ∪ c.bits) (stall C Fs c.bits g 1 s)).st.stopped = false := by
    cases h' : (runKB C R p (g ∪ c.bits) (stall C Fs c.bits g 1 s)).st.stopped
    · rfl
    · rw [runK_stoppedK C R _ _ _ h', runKB_stoppedK C R Z _ _ h', h'] at hrun
      exact hrun
  rw [runK_leaf_put C R i f _ _ hS1]
  have hfr : ∀ q ∈ f.qubits, (runKB C R p (g ∪ c.bits) (stall C Fs c.bits g 1 s)).st.ready q =
      max (s.st.ready q) (stall C Fs c.bits g 1 s).free := by
    intro q hq
    rw [(runKB_frm C R p (g ∪ c.bits) (stall C Fs c.bits g 1 s)).ready q
      (Finset.disjoint_left.1 hpD.1 hq)]
    show (if q ∈ Fs.qubits then max (s.st.ready q) (stall C Fs c.bits g 1 s).free
      else s.st.ready q) = _
    rw [if_pos (hfF hq)]
  have hgt : gateTime C.base s.st g ≤
      gateTime C.base (runKB C R p (g ∪ c.bits) (stall C Fs c.bits g 1 s)).st (g ∪ c.bits) := by
    have hA : gateTime C.base s.st g = gateTime C.base (stall C Fs c.bits g 1 s).st g := rfl
    rw [hA]
    exact ((runKB_frm C R p (g ∪ c.bits) _).grow g Finset.subset_union_left).trans
      (gateTime_mono C.base (TState.Le.refl _) Finset.subset_union_left)
  have hsup : f.qubits.sup s.st.ready ≤
      f.qubits.sup (runKB C R p (g ∪ c.bits) (stall C Fs c.bits g 1 s)).st.ready :=
    Finset.sup_mono_fun fun q hq => by rw [hfr q hq]; exact le_max_left _ _
  have he : leafEnd C.base i f g s.st ≤
      leafEnd C.base i f (g ∪ c.bits) (runKB C R p (g ∪ c.bits) (stall C Fs c.bits g 1 s)).st := by
    unfold leafEnd
    exact add_le_add (max_le_max hgt hsup) le_rfl
  have ht : ∀ q ∈ f.qubits, (stall C Fs c.bits g 1 s).free ≤
      leafEnd C.base i f (g ∪ c.bits) (runKB C R p (g ∪ c.bits) (stall C Fs c.bits g 1 s)).st := by
    intro q hq
    unfold leafEnd
    refine le_trans ?_ le_self_add
    refine le_trans ?_ (le_max_right _ _)
    refine le_trans ?_ (Finset.le_sup (f := (runKB C R p (g ∪ c.bits)
      (stall C Fs c.bits g 1 s)).st.ready) hq)
    rw [hfr q hq]
    exact le_max_right _ _
  have h1 := stall_putB_le C R Ft Fs c.bits g 1 f (leafEnd C.base i f g s.st)
    (leafEnd C.base i f g s.st) s hF hc henc
  have h2 := runKB_mono C R p (g ∪ c.bits) (g ∪ c.bits) (Finset.Subset.refl _) _ _ h1
  rw [runKB_put C R f _ _ p (g ∪ c.bits) _ hpD hw] at h2
  have h3 := putB_le R f (BState.Le.refl (runKB C R p (g ∪ c.bits) (stall C Fs c.bits g 1 s)))
    (fun q hq => max_le he (ht q hq)) he
  exact runKB_mono C R Z _ _ (Finset.Subset.refl _) _ _ (h2.trans h3)

/-- C1 in the block model for a hoisted leaf: the side conditions of
`hoist_latency`. -/
theorem hoist_block_leaf (C : BCost) (R : Record) (c : Cond) (i : ℕ) (f : Footprint)
    (pA A pB B : List Op) (gates : Finset Bit)
    (hA : ∀ y ∈ pA, f.Disj (Op.fp y))
    (hB : ∀ y ∈ pB, f.Disj (Op.fp y))
    (hc : Disjoint c.bits f.writes)
    (henc : Disjoint gates f.writes)
    (s : BState) (hst : s.st.stopped = false)
    (hrun : (runK C R (.ite c (pA ++ .leaf i f :: A) (pB ++ .leaf i f :: B)) gates s).st.stopped
      = false) :
    (runKB C R [.leaf i f, .ite c (pA ++ A) (pB ++ B)] gates s).Le
      (runK C R (.ite c (pA ++ .leaf i f :: A) (pB ++ .leaf i f :: B)) gates s) := by
  have hFt : (Op.fp (.ite c (pA ++ A) (pB ++ B))).qubits ⊆
      (Op.fp (.ite c (pA ++ .leaf i f :: A) (pB ++ .leaf i f :: B))).qubits := by
    intro q hq
    simp only [Op.fp, Op.fps, Footprint.union_qubits, fps_append_qubits, Finset.mem_union] at hq ⊢
    tauto
  have hfF : f.qubits ⊆ (Op.fp (.ite c (pA ++ .leaf i f :: A) (pB ++ .leaf i f :: B))).qubits := by
    intro q hq
    simp only [Op.fp, Op.fps, Footprint.union_qubits, fps_append_qubits, Finset.mem_union]
    tauto
  rw [runKB_cons, runKB_cons, runKB_nil, runK_leaf_put C R i f gates s hst,
    runK_ite C R c (pA ++ A) (pB ++ B) gates
      (putB R f (leafEnd C.base i f gates s.st) (leafEnd C.base i f gates s.st) s) hst,
    evalB_put R f _ _ s c hc,
    runK_ite C R c (pA ++ .leaf i f :: A) (pB ++ .leaf i f :: B) gates s hst]
  rw [runK_ite C R c _ _ gates s hst] at hrun
  by_cases hce : c.eval s.st.vals = true
  · simp only [if_pos hce] at hrun ⊢
    exact hoist_branch_K C R c i f pA A _ _ gates s hFt hfF hA hc henc hrun
  · simp only [if_neg hce] at hrun ⊢
    exact hoist_branch_K C R c i f pB B _ _ gates s hFt hfF hB hc henc hrun

/-- One arm of a merge. -/
theorem merge_branch_K (C : BCost) (R : Record) (c : Cond) (i : ℕ) (f : Footprint)
    (P Q : List Op) (Ft Fs : Footprint) (g : Finset Bit) (s : BState)
    (hF : Ft.qubits ⊆ Fs.qubits)
    (hq : ∀ y ∈ Q, f.Disj (Op.fp y)) (hencQ : ∀ y ∈ Q, Disjoint g (Op.fp y).writes)
    (hw : Disjoint (g ∪ c.bits) f.writes)
    (hrun : (runKB C R (P ++ .leaf i f :: Q) (g ∪ c.bits)
      (stall C Fs c.bits g 1 s)).st.stopped = false) :
    (runK C R (.leaf i f) g (runKB C R (P ++ Q) (g ∪ c.bits) (stall C Ft c.bits g 1 s))).Le
      (runKB C R (P ++ .leaf i f :: Q) (g ∪ c.bits) (stall C Fs c.bits g 1 s)) := by
  have hQD := disj_fps f Q hq
  have hgQ := disj_fps_writes g Q hencQ
  have hX := runKB_mono C R P (g ∪ c.bits) (g ∪ c.bits) (Finset.Subset.refl _) _ _
    (stall_sub_le C Ft Fs c.bits g 1 s hF)
  rw [runKB_appendK, runKB_cons] at hrun
  rw [runKB_appendK, runKB_appendK, runKB_cons]
  have hXs : (runKB C R P (g ∪ c.bits) (stall C Fs c.bits g 1 s)).st.stopped = false := by
    cases h' : (runKB C R P (g ∪ c.bits) (stall C Fs c.bits g 1 s)).st.stopped
    · rfl
    · rw [runK_stoppedK C R _ _ _ h', runKB_stoppedK C R Q _ _ h', h'] at hrun
      exact hrun
  rw [runK_leaf_put C R i f _ _ hXs, runKB_put C R f _ _ Q (g ∪ c.bits) _ hQD hw] at hrun ⊢
  have hZ := runKB_mono C R Q (g ∪ c.bits) (g ∪ c.bits) (Finset.Subset.refl _) _ _ hX
  have hZs : (runKB C R Q (g ∪ c.bits) (runKB C R P (g ∪ c.bits)
      (stall C Ft c.bits g 1 s))).st.stopped = false := by
    rw [hZ.1.2.2.1]; exact hrun
  rw [runK_leaf_put C R i f _ _ hZs]
  have hfrm := runKB_frm C R Q (g ∪ c.bits) (runKB C R P (g ∪ c.bits) (stall C Ft c.bits g 1 s))
  have hgt : gateTime C.base (runKB C R Q (g ∪ c.bits) (runKB C R P (g ∪ c.bits)
      (stall C Ft c.bits g 1 s))).st g ≤
      gateTime C.base (runKB C R P (g ∪ c.bits) (stall C Fs c.bits g 1 s)).st (g ∪ c.bits) := by
    rw [gateTime_congr C.base _ _ g fun z hz => hfrm.meas z (Finset.disjoint_left.1 hgQ hz)]
    exact (gateTime_mono C.base hX.1 (Finset.Subset.refl _)).trans
      (gateTime_mono C.base (TState.Le.refl _) Finset.subset_union_left)
  have hsup : f.qubits.sup (runKB C R Q (g ∪ c.bits) (runKB C R P (g ∪ c.bits)
      (stall C Ft c.bits g 1 s))).st.ready ≤
      f.qubits.sup (runKB C R P (g ∪ c.bits) (stall C Fs c.bits g 1 s)).st.ready :=
    Finset.sup_mono_fun fun q hq' => by
      rw [hfrm.ready q (Finset.disjoint_left.1 hQD.1 hq')]
      exact hX.1.2.2.2.1 q
  have he : leafEnd C.base i f g (runKB C R Q (g ∪ c.bits) (runKB C R P (g ∪ c.bits)
      (stall C Ft c.bits g 1 s))).st ≤
      leafEnd C.base i f (g ∪ c.bits) (runKB C R P (g ∪ c.bits) (stall C Fs c.bits g 1 s)).st := by
    unfold leafEnd
    exact add_le_add (max_le_max hgt hsup) le_rfl
  exact putB_le R f hZ (fun _ _ => he) he

/-- C1 in the block model for a merged leaf: the side conditions of
`merge_latency`, plus "the leaf writes no enclosing gate bit and no
condition bit" (`hw`). -/
theorem merge_block_leaf (C : BCost) (R : Record) (c : Cond) (i : ℕ) (f : Footprint)
    (A sA B sB : List Op) (gates : Finset Bit)
    (hA : ∀ y ∈ sA, f.Disj (Op.fp y))
    (hB : ∀ y ∈ sB, f.Disj (Op.fp y))
    (hencA : ∀ y ∈ sA, Disjoint gates (Op.fp y).writes)
    (hencB : ∀ y ∈ sB, Disjoint gates (Op.fp y).writes)
    (hw : Disjoint (gates ∪ c.bits) f.writes)
    (s : BState) (hst : s.st.stopped = false)
    (hrun : (runK C R (.ite c (A ++ .leaf i f :: sA) (B ++ .leaf i f :: sB)) gates s).st.stopped
      = false) :
    (runKB C R [.ite c (A ++ sA) (B ++ sB), .leaf i f] gates s).Le
      (runK C R (.ite c (A ++ .leaf i f :: sA) (B ++ .leaf i f :: sB)) gates s) := by
  have hFt : (Op.fp (.ite c (A ++ sA) (B ++ sB))).qubits ⊆
      (Op.fp (.ite c (A ++ .leaf i f :: sA) (B ++ .leaf i f :: sB))).qubits := by
    intro q hq
    simp only [Op.fp, Op.fps, Footprint.union_qubits, fps_append_qubits, Finset.mem_union] at hq ⊢
    tauto
  rw [runKB_cons, runKB_cons, runKB_nil, runK_ite C R c _ _ gates s hst,
    runK_ite C R c _ _ gates s hst]
  rw [runK_ite C R c _ _ gates s hst] at hrun
  by_cases hce : c.eval s.st.vals = true
  · simp only [if_pos hce] at hrun ⊢
    exact merge_branch_K C R c i f A sA _ _ gates s hFt hA hencA hw hrun
  · simp only [if_neg hce] at hrun ⊢
    exact merge_branch_K C R c i f B sB _ _ gates s hFt hB hencB hw hrun

/-! ### Closure in the block model, for leaf moves

`M0StepsK E P Q`: leaf hoists and leaf merges (with the side conditions of
`hoist_block_leaf` and `merge_block_leaf`), closed under blocks, if arms,
loop bodies, switch cases and defaults, and sequences.
`m0StepsK_latency`: the block replay of `Q` is no later than that of `P`. -/

def NoLaterAtK (C : BCost) (R : Record) (g : Finset Bit) (P Q : List Op) : Prop :=
  ∀ a b : BState, a.Le b → (runKB C R P g b).st.stopped = false →
    (runKB C R Q g a).Le (runKB C R P g b)

def NoLaterK (C : BCost) (R : Record) (E : Finset Bit) (P Q : List Op) : Prop :=
  ∀ g, g ⊆ E → NoLaterAtK C R g P Q

inductive M0StepsK : Finset Bit → List Op → List Op → Prop
  | hoist (E : Finset Bit) (c : Cond) (i : ℕ) (f : Footprint) (pA A pB B : List Op)
      (hA : ∀ y ∈ pA, f.Disj (Op.fp y)) (hB : ∀ y ∈ pB, f.Disj (Op.fp y))
      (hc : Disjoint c.bits f.writes) (henc : Disjoint E f.writes) :
      M0StepsK E [.ite c (pA ++ .leaf i f :: A) (pB ++ .leaf i f :: B)]
        [.leaf i f, .ite c (pA ++ A) (pB ++ B)]
  | merge (E : Finset Bit) (c : Cond) (i : ℕ) (f : Footprint) (A sA B sB : List Op)
      (hA : ∀ y ∈ sA, f.Disj (Op.fp y)) (hB : ∀ y ∈ sB, f.Disj (Op.fp y))
      (hencA : ∀ y ∈ sA, Disjoint E (Op.fp y).writes)
      (hencB : ∀ y ∈ sB, Disjoint E (Op.fp y).writes)
      (hw : Disjoint (E ∪ c.bits) f.writes) :
      M0StepsK E [.ite c (A ++ .leaf i f :: sA) (B ++ .leaf i f :: sB)]
        [.ite c (A ++ sA) (B ++ sB), .leaf i f]
  | frame {E : Finset Bit} {P Q : List Op} (l1 l2 : List Op) :
      M0StepsK E P Q → M0StepsK E (l1 ++ P ++ l2) (l1 ++ Q ++ l2)
  | iteL {E : Finset Bit} {A A' : List Op} (c : Cond) (B : List Op) :
      M0StepsK (E ∪ c.bits) A A' → M0StepsK E [.ite c A B] [.ite c A' B]
  | iteR {E : Finset Bit} {B B' : List Op} (c : Cond) (A : List Op) :
      M0StepsK (E ∪ c.bits) B B' → M0StepsK E [.ite c A B] [.ite c A B']
  | loop {E : Finset Bit} {body body' : List Op} (K : ℕ) (c : Cond) :
      M0StepsK (E ∪ c.bits) body body' → M0StepsK E [.loop K body c] [.loop K body' c]
  | case {E : Finset Bit} {blk blk' : List Op} (G : Finset Bit)
      (cs1 : List (Assign × List Op)) (v : Assign) (cs2 : List (Assign × List Op))
      (d : List Op) :
      M0StepsK (E ∪ G) blk blk' →
      M0StepsK E [.switch G (cs1 ++ (v, blk) :: cs2) d] [.switch G (cs1 ++ (v, blk') :: cs2) d]
  | dflt {E : Finset Bit} {d d' : List Op} (G : Finset Bit)
      (cs : List (Assign × List Op)) :
      M0StepsK (E ∪ G) d d' → M0StepsK E [.switch G cs d] [.switch G cs d']
  | refl (E : Finset Bit) (P : List Op) : M0StepsK E P P
  | trans {E : Finset Bit} {P Q S : List Op} :
      M0StepsK E P Q → M0StepsK E Q S → M0StepsK E P S

theorem runK_runningK {C : BCost} {R : Record} {o : Op} {g : Finset Bit} {b : BState}
    (h : (runK C R o g b).st.stopped = false) : b.st.stopped = false := by
  cases hs : b.st.stopped
  · rfl
  · rw [runK_stoppedK C R o g b hs, hs] at h; exact h

theorem runKB_runningK {C : BCost} {R : Record} {l : List Op} {g : Finset Bit} {b : BState}
    (h : (runKB C R l g b).st.stopped = false) : b.st.stopped = false := by
  cases hs : b.st.stopped
  · rfl
  · rw [runKB_stoppedK C R l g b hs, hs] at h; exact h

theorem runKB_single (C : BCost) (R : Record) (o : Op) (g : Finset Bit) (s : BState) :
    runKB C R [o] g s = runK C R o g s := by rw [runKB_cons, runKB_nil]

theorem fpsCases_append_qubits : ∀ (cs1 cs2 : List (Assign × List Op)),
    (Op.fpsCases (cs1 ++ cs2)).qubits = (Op.fpsCases cs1).qubits ∪ (Op.fpsCases cs2).qubits
  | [], cs2 => by simp [Op.fpsCases, Footprint.empty]
  | (v, blk) :: cs1, cs2 => by
    simp only [List.cons_append, Op.fpsCases, Footprint.union_qubits,
      fpsCases_append_qubits cs1 cs2, Finset.union_assoc]

theorem fp_ite_sub_left (c : Cond) {A A' : List Op} (B : List Op)
    (h : (Op.fps A').qubits ⊆ (Op.fps A).qubits) :
    (Op.fp (.ite c A' B)).qubits ⊆ (Op.fp (.ite c A B)).qubits := by
  intro q hq
  have h1 : q ∈ (Op.fps A').qubits → q ∈ (Op.fps A).qubits := fun h' => h h'
  simp only [Op.fp, Footprint.union_qubits, Finset.mem_union] at hq ⊢
  tauto

theorem fp_ite_sub_right (c : Cond) (A : List Op) {B B' : List Op}
    (h : (Op.fps B').qubits ⊆ (Op.fps B).qubits) :
    (Op.fp (.ite c A B')).qubits ⊆ (Op.fp (.ite c A B)).qubits := by
  intro q hq
  have h1 : q ∈ (Op.fps B').qubits → q ∈ (Op.fps B).qubits := fun h' => h h'
  simp only [Op.fp, Footprint.union_qubits, Finset.mem_union] at hq ⊢
  tauto

theorem fp_loop_sub (K : ℕ) (c : Cond) {body body' : List Op}
    (h : (Op.fps body').qubits ⊆ (Op.fps body).qubits) :
    (Op.fp (.loop K body' c)).qubits ⊆ (Op.fp (.loop K body c)).qubits := by
  intro q hq
  have h1 : q ∈ (Op.fps body').qubits → q ∈ (Op.fps body).qubits := fun h' => h h'
  simp only [Op.fp, Footprint.union_qubits, Finset.mem_union] at hq ⊢
  tauto

theorem fp_switch_sub_case (G : Finset Bit) (cs1 : List (Assign × List Op)) (v : Assign)
    (cs2 : List (Assign × List Op)) (d : List Op) {blk blk' : List Op}
    (h : (Op.fps blk').qubits ⊆ (Op.fps blk).qubits) :
    (Op.fp (.switch G (cs1 ++ (v, blk') :: cs2) d)).qubits ⊆
      (Op.fp (.switch G (cs1 ++ (v, blk) :: cs2) d)).qubits := by
  intro q hq
  have h1 : q ∈ (Op.fps blk').qubits → q ∈ (Op.fps blk).qubits := fun h' => h h'
  simp only [Op.fp, Footprint.union_qubits, fpsCases_append_qubits, Op.fpsCases,
    Finset.mem_union] at hq ⊢
  tauto

theorem fp_switch_sub_dflt (G : Finset Bit) (cs : List (Assign × List Op)) {d d' : List Op}
    (h : (Op.fps d').qubits ⊆ (Op.fps d).qubits) :
    (Op.fp (.switch G cs d')).qubits ⊆ (Op.fp (.switch G cs d)).qubits := by
  intro q hq
  have h1 : q ∈ (Op.fps d').qubits → q ∈ (Op.fps d).qubits := fun h' => h h'
  simp only [Op.fp, Footprint.union_qubits, Finset.mem_union] at hq ⊢
  tauto

/-- The taken arm index does not depend on the case blocks. -/
theorem armIdx_case (G : Finset Bit) (vals : Assign) (v : Assign) (blk blk' : List Op)
    (cs2 : List (Assign × List Op)) : ∀ cs1 : List (Assign × List Op),
    armIdx G vals (cs1 ++ (v, blk') :: cs2) = armIdx G vals (cs1 ++ (v, blk) :: cs2)
  | [] => by simp only [List.nil_append, armIdx]
  | (w, b0) :: cs1 => by
    simp only [List.cons_append, armIdx, armIdx_case G vals v blk blk' cs2 cs1]

/-- A no-later step that keeps the stop flag: a controller step. -/
theorem loopK_noLaterK (c : Cond) (g : Finset Bit) (f f' : Finset Bit → BState → BState)
    (stl stl' : BState → BState)
    (H : ∀ g', g' ⊆ g ∪ c.bits → ∀ a b : BState, a.Le b → (f g' b).st.stopped = false →
      (f' g' a).Le (f g' b))
    (Hs : ∀ a b : BState, a.Le b → (stl' a).Le (stl b))
    (hstl : ∀ s, (stl s).st.stopped = s.st.stopped) :
    ∀ (k : ℕ) (first : Bool) (a b : BState), a.Le b →
      (loopK f stl c g k first b).st.stopped = false →
      (loopK f' stl' c g k first a).Le (loopK f stl c g k first b)
  | 0, _, _, _, _, h => by simp [loopK] at h
  | k + 1, first, a, b, hab, h => by
    have hg : (if first = true then g else g ∪ c.bits) ⊆ g ∪ c.bits := by
      cases first
      · exact Finset.Subset.refl _
      · exact Finset.subset_union_left
    simp only [loopK] at h ⊢
    generalize hX : f (if first = true then g else g ∪ c.bits) b = X at h ⊢
    generalize hY : f' (if first = true then g else g ∪ c.bits) a = Y
    by_cases hs : X.st.stopped = true
    · simp [hs] at h
    · have hs' : X.st.stopped = false := by simpa using hs
      have hle : Y.Le X := by
        rw [← hX, ← hY]; exact H _ hg a b hab (by rw [hX]; exact hs')
      have hsa : Y.st.stopped = false := by rw [hle.1.2.2.1, hs']
      simp only [hs', hsa, Bool.false_eq_true, if_false] at h ⊢
      have h2 := Hs _ _ hle
      have hst2 : (stl X).st.stopped = false := by rw [hstl]; exact hs'
      have hst2' : (stl' Y).st.stopped = false := by rw [h2.1.2.2.1, hst2]
      simp only [hst2, hst2', Bool.false_or] at h ⊢
      rw [h2.1.1]
      by_cases hc : c.eval (stl X).st.vals = true
      · rw [if_pos hc, if_pos hc]; exact h2
      · rw [if_neg hc] at h ⊢
        rw [if_neg hc]
        exact loopK_noLaterK c g f f' stl stl' H Hs hstl k false _ _ h2 h

theorem runKCases_caseK (C : BCost) (R : Record) (G : Finset Bit) (d : List Op)
    (gates : Finset Bit) (v : Assign) (blk blk' : List Op) (cs2 : List (Assign × List Op))
    (H : NoLaterAtK C R gates blk blk') :
    ∀ (cs1 : List (Assign × List Op)) (a b : BState), a.Le b →
      (runKCases C R G (cs1 ++ (v, blk) :: cs2) d gates b).st.stopped = false →
      (runKCases C R G (cs1 ++ (v, blk') :: cs2) d gates a).Le
        (runKCases C R G (cs1 ++ (v, blk) :: cs2) d gates b)
  | [], a, b, hab, h => by
    simp only [List.nil_append, runKCases, hab.1.1] at h ⊢
    by_cases hv : agrees G b.st.vals v
    · rw [if_pos hv] at h
      rw [if_pos hv, if_pos hv]
      exact H a b hab h
    · rw [if_neg hv, if_neg hv]
      exact runKCases_mono C R G cs2 d gates gates (Finset.Subset.refl _)
        (fun a' b' h' => runKB_mono C R d gates gates (Finset.Subset.refl _) a' b' h') a b hab
  | (w, blk0) :: cs1, a, b, hab, h => by
    simp only [List.cons_append, runKCases, hab.1.1] at h ⊢
    by_cases hv : agrees G b.st.vals w
    · rw [if_pos hv, if_pos hv]
      exact runKB_mono C R blk0 gates gates (Finset.Subset.refl _) a b hab
    · rw [if_neg hv] at h
      rw [if_neg hv, if_neg hv]
      exact runKCases_caseK C R G d gates v blk blk' cs2 H cs1 a b hab h

theorem runKCases_dfltK (C : BCost) (R : Record) (G : Finset Bit) (d d' : List Op)
    (gates : Finset Bit) (H : NoLaterAtK C R gates d d') :
    ∀ (cs : List (Assign × List Op)) (a b : BState), a.Le b →
      (runKCases C R G cs d gates b).st.stopped = false →
      (runKCases C R G cs d' gates a).Le (runKCases C R G cs d gates b)
  | [], a, b, hab, h => by
    simp only [runKCases] at h ⊢
    exact H a b hab h
  | (w, blk0) :: cs, a, b, hab, h => by
    simp only [runKCases, hab.1.1] at h ⊢
    by_cases hv : agrees G b.st.vals w
    · rw [if_pos hv, if_pos hv]
      exact runKB_mono C R blk0 gates gates (Finset.Subset.refl _) a b hab
    · rw [if_neg hv] at h
      rw [if_neg hv, if_neg hv]
      exact runKCases_dfltK C R G d d' gates H cs a b hab h

/-- Leaf M0 steps keep the qubits of a block or shrink them. -/
theorem m0StepsK_fps {E : Finset Bit} {P Q : List Op} (h : M0StepsK E P Q) :
    (Op.fps Q).qubits ⊆ (Op.fps P).qubits := by
  induction h with
  | hoist E c i f pA A pB B =>
    intro q hq
    simp only [Op.fps, Op.fp, Footprint.union_qubits, fps_append_qubits, Finset.mem_union,
      Footprint.empty, Finset.notMem_empty, or_false, false_or] at hq ⊢
    tauto
  | merge E c i f A sA B sB =>
    intro q hq
    simp only [Op.fps, Op.fp, Footprint.union_qubits, fps_append_qubits, Finset.mem_union,
      Footprint.empty, Finset.notMem_empty, or_false, false_or] at hq ⊢
    tauto
  | frame l1 l2 _ ih =>
    intro q hq
    have h1 : q ∈ _ → q ∈ _ := fun h' => ih h'
    simp only [fps_append_qubits, Finset.mem_union] at hq ⊢
    tauto
  | iteL c B _ ih =>
    intro q hq
    simp only [Op.fps, Footprint.union_qubits, Footprint.empty, Finset.mem_union,
      Finset.notMem_empty, or_false] at hq ⊢
    exact fp_ite_sub_left c B ih hq
  | iteR c A _ ih =>
    intro q hq
    simp only [Op.fps, Footprint.union_qubits, Footprint.empty, Finset.mem_union,
      Finset.notMem_empty, or_false] at hq ⊢
    exact fp_ite_sub_right c A ih hq
  | loop K c _ ih =>
    intro q hq
    simp only [Op.fps, Footprint.union_qubits, Footprint.empty, Finset.mem_union,
      Finset.notMem_empty, or_false] at hq ⊢
    exact fp_loop_sub K c ih hq
  | case G cs1 v cs2 d _ ih =>
    intro q hq
    simp only [Op.fps, Footprint.union_qubits, Footprint.empty, Finset.mem_union,
      Finset.notMem_empty, or_false] at hq ⊢
    exact fp_switch_sub_case G cs1 v cs2 d ih hq
  | dflt G cs _ ih =>
    intro q hq
    simp only [Op.fps, Footprint.union_qubits, Footprint.empty, Finset.mem_union,
      Finset.notMem_empty, or_false] at hq ⊢
    exact fp_switch_sub_dflt G cs ih hq
  | refl E P => exact Finset.Subset.refl _
  | trans _ _ ih1 ih2 => exact ih2.trans ih1

/-- Closure of C1 in the block model, for leaf moves. -/
theorem m0StepsK_latency (C : BCost) (R : Record) {E : Finset Bit} {P Q : List Op}
    (h : M0StepsK E P Q) : NoLaterK C R E P Q := by
  induction h with
  | hoist E c i f pA A pB B hA hB hc henc =>
    intro g hg a b hab hrun
    rw [runKB_single] at hrun
    have key := hoist_block_leaf C R c i f pA A pB B g hA hB hc
      (Finset.disjoint_of_subset_left hg henc) b (runK_runningK hrun) hrun
    rw [runKB_single]
    exact (runKB_mono C R _ g g (Finset.Subset.refl _) a b hab).trans key
  | merge E c i f A sA B sB hA hB hencA hencB hw =>
    intro g hg a b hab hrun
    rw [runKB_single] at hrun
    have key := merge_block_leaf C R c i f A sA B sB g hA hB
      (fun y hy => Finset.disjoint_of_subset_left hg (hencA y hy))
      (fun y hy => Finset.disjoint_of_subset_left hg (hencB y hy))
      (Finset.disjoint_of_subset_left (Finset.union_subset_union hg (Finset.Subset.refl _)) hw)
      b (runK_runningK hrun) hrun
    rw [runKB_single]
    exact (runKB_mono C R _ g g (Finset.Subset.refl _) a b hab).trans key
  | frame l1 l2 _ ih =>
    intro g hg a b hab hrun
    rw [runKB_appendK, runKB_appendK] at hrun
    rw [runKB_appendK, runKB_appendK, runKB_appendK, runKB_appendK]
    have h1 := runKB_mono C R l1 g g (Finset.Subset.refl _) a b hab
    exact runKB_mono C R l2 g g (Finset.Subset.refl _) _ _
      (ih g hg _ _ h1 (runKB_runningK hrun))
  | @iteL E A A' c B h ih =>
    intro g hg a b hab hrun
    rw [runKB_single] at hrun
    rw [runKB_single, runKB_single]
    have hb := runK_runningK hrun
    have ha : a.st.stopped = false := by rw [hab.1.2.2.1, hb]
    have hgc : g ∪ c.bits ⊆ E ∪ c.bits := Finset.union_subset_union hg (Finset.Subset.refl _)
    have hst := (stall_mono C (Op.fp (.ite c A' B)) c.bits (Finset.Subset.refl g) 1 hab).trans
      (stall_sub_le C _ _ c.bits g 1 b (fp_ite_sub_left c B (m0StepsK_fps h)))
    rw [runK_ite C R c A B g b hb] at hrun ⊢
    rw [runK_ite C R c A' B g a ha, hab.1.1]
    by_cases hce : c.eval b.st.vals = true
    · simp only [if_pos hce] at hrun ⊢
      exact ih _ hgc _ _ hst hrun
    · simp only [if_neg hce] at hrun ⊢
      exact runKB_mono C R B _ _ (Finset.Subset.refl _) _ _ hst
  | @iteR E B B' c A h ih =>
    intro g hg a b hab hrun
    rw [runKB_single] at hrun
    rw [runKB_single, runKB_single]
    have hb := runK_runningK hrun
    have ha : a.st.stopped = false := by rw [hab.1.2.2.1, hb]
    have hgc : g ∪ c.bits ⊆ E ∪ c.bits := Finset.union_subset_union hg (Finset.Subset.refl _)
    have hst := (stall_mono C (Op.fp (.ite c A B')) c.bits (Finset.Subset.refl g) 1 hab).trans
      (stall_sub_le C _ _ c.bits g 1 b (fp_ite_sub_right c A (m0StepsK_fps h)))
    rw [runK_ite C R c A B g b hb] at hrun ⊢
    rw [runK_ite C R c A B' g a ha, hab.1.1]
    by_cases hce : c.eval b.st.vals = true
    · simp only [if_pos hce] at hrun ⊢
      exact runKB_mono C R A _ _ (Finset.Subset.refl _) _ _ hst
    · simp only [if_neg hce] at hrun ⊢
      exact ih _ hgc _ _ hst hrun
  | @loop E body body' K c h ih =>
    intro g hg a b hab hrun
    rw [runKB_single] at hrun
    rw [runKB_single, runKB_single]
    have hb := runK_runningK hrun
    have ha : a.st.stopped = false := by rw [hab.1.2.2.1, hb]
    have hFq := fp_loop_sub K c (m0StepsK_fps h)
    simp only [runK, hb, ha, Bool.false_eq_true, if_false] at hrun ⊢
    exact loopK_noLaterK c g _ _ _ _
      (fun g' hg' a' b' hab' h' =>
        ih g' (hg'.trans (Finset.union_subset_union hg (Finset.Subset.refl _))) a' b' hab' h')
      (fun a' b' h' => (stall_mono C _ c.bits (Finset.Subset.refl g) 1 h').trans
        (stall_sub_le C _ _ c.bits g 1 b' hFq))
      (fun _ => rfl) K true a b hab hrun
  | @case E blk blk' G cs1 v cs2 d h ih =>
    intro g hg a b hab hrun
    rw [runKB_single] at hrun
    rw [runKB_single, runKB_single]
    have hb := runK_runningK hrun
    have ha : a.st.stopped = false := by rw [hab.1.2.2.1, hb]
    have hn : C.dec G.card (cs1 ++ (v, blk') :: cs2).length
          (armIdx G a.st.vals (cs1 ++ (v, blk') :: cs2)) =
        C.dec G.card (cs1 ++ (v, blk) :: cs2).length
          (armIdx G b.st.vals (cs1 ++ (v, blk) :: cs2)) := by
      rw [armIdx_case G a.st.vals v blk blk' cs2 cs1, hab.1.1]
      simp
    simp only [runK, hb, ha, Bool.false_eq_true, if_false] at hrun ⊢
    rw [hn]
    exact runKCases_caseK C R G d _ v blk blk' cs2
      (ih _ (Finset.union_subset_union hg (Finset.Subset.refl _))) cs1 _ _
      ((stall_mono C _ G (Finset.Subset.refl g) _ hab).trans
        (stall_sub_le C _ _ G g _ b (fp_switch_sub_case G cs1 v cs2 d (m0StepsK_fps h)))) hrun
  | @dflt E d d' G cs h ih =>
    intro g hg a b hab hrun
    rw [runKB_single] at hrun
    rw [runKB_single, runKB_single]
    have hb := runK_runningK hrun
    have ha : a.st.stopped = false := by rw [hab.1.2.2.1, hb]
    simp only [runK, hb, ha, Bool.false_eq_true, if_false] at hrun ⊢
    rw [hab.1.1]
    exact runKCases_dfltK C R G d d' _
      (ih _ (Finset.union_subset_union hg (Finset.Subset.refl _))) cs _ _
      ((stall_mono C _ G (Finset.Subset.refl g) _ hab).trans
        (stall_sub_le C _ _ G g _ b (fp_switch_sub_dflt G cs (m0StepsK_fps h)))) hrun
  | refl E P => exact fun g _ a b hab _ => runKB_mono C R P g g (Finset.Subset.refl _) a b hab
  | trans _ _ ih1 ih2 =>
    intro g hg a b hab hrun
    have h1 := ih1 g hg b b (BState.Le.refl b) hrun
    have h2 := ih2 g hg a b hab (by rw [h1.1.2.2.1]; exact hrun)
    exact h2.trans h1

end Qlin
