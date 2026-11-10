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
  grow : ∀ g0, g0 ⊆ g → gateTime C a g0 ≤ gateTime C b g0

theorem Frm.refl (C : Cost) (F : Footprint) (g : Finset Bit) (a : TState) : Frm C F g a a :=
  ⟨fun _ _ => rfl, fun _ _ => rfl, fun _ _ => le_rfl⟩

theorem Frm.trans {C : Cost} {F : Footprint} {g : Finset Bit} {a b c : TState}
    (h1 : Frm C F g a b) (h2 : Frm C F g b c) : Frm C F g a c :=
  ⟨fun q hq => (h2.ready q hq).trans (h1.ready q hq),
    fun z hz => (h2.meas z hz).trans (h1.meas z hz),
    fun g0 hg0 => (h1.grow g0 hg0).trans (h2.grow g0 hg0)⟩

theorem Frm.mono {C : Cost} {F F' : Footprint} {g g' : Finset Bit} {a b : TState}
    (h : Frm C F g a b) (hq : F.qubits ⊆ F'.qubits) (hw : F.writes ⊆ F'.writes) (hg : g' ⊆ g) :
    Frm C F' g' a b :=
  ⟨fun q hq' => h.ready q fun h' => hq' (hq h'), fun z hz => h.meas z fun h' => hz (hw h'),
    fun g0 hg0 => h.grow g0 (hg0.trans hg)⟩

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
    refine ⟨fun q hq => by simp [put, hq], fun z hz => by simp [put, hz], fun g0 hg0 => ?_⟩
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
  ⟨fun q hq => by simp [stall, hq], fun _ _ => rfl,
    fun g0 _ => le_of_eq (gateTime_congr C.base _ _ g0 fun _ _ => rfl).symm⟩

theorem loopK_frm (C : Cost) (F : Footprint) (c : Cond) (g : Finset Bit)
    (body : Finset Bit → BState → BState) (stl : BState → BState)
    (hbody : ∀ g' s, g ⊆ g' → Frm C F g s.st (body g' s).st)
    (hstl : ∀ s, Frm C F g s.st (stl s).st) :
    ∀ (k : ℕ) (first : Bool) (s : BState), Frm C F g s.st (loopK body stl c g k first s).st
  | 0, _, s => by
    simp only [loopK]
    exact ⟨fun _ _ => rfl, fun _ _ => rfl,
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

end Qlin
