import Qlin.Structure

/-!
# R4: the M0 moves never increase replay latency (claim C1)

A timing semantics copied from `Replay` in `src/latency.rs`, Ideal
model, no noise qubits, no relaxed Ifs:
- A leaf starts when its qubits are free and each enclosing condition
  bit's latest measurement has ended plus `t_ff` (`gate_time`). A leaf
  that writes a bit is a measurement. It records the end time and the
  next outcome of that bit from the record.
- An If runs its taken arm, gated also on its condition bits.
- A loop runs at most `K` iterations. Iterations after the first are
  gated on the exit bits. A loop that never exits stops the run (the
  `stopped` flag): every later op is skipped.
- A Switch runs its first matching case, gated on its bits.

Theorems:
- `run_mono`: the schedule is monotone in the start state and in the
  gate bits.
- `hoist_latency` and `merge_latency`: one hoist or merge step gives a
  state that is no later, pointwise, than the original. The side
  conditions are those of `match_arms` in `src/analysis/core.rs`,
  including the enclosing condition bits (`gates`): see
  notes/c1-counterexample. The run must not stop (no truncated loop on
  this record).
-/

namespace Qlin

open scoped NNReal

/-- Durations and feedforward latency (ns). -/
structure Cost where
  dur : ℕ → Footprint → ℝ≥0
  tff : ℝ≥0

/-- The replay state. -/
structure TState where
  ready : Qubit → ℝ≥0
  measEnd : Bit → Option ℝ≥0
  vals : Assign
  cursor : Bit → ℕ
  stopped : Bool

/-- The outcome of the `k`-th measurement of each bit. -/
abbrev Record := Bit → ℕ → Bool

/-- The earliest start allowed by the gate bits (`gate_time`). -/
def gateTime (C : Cost) (st : TState) (gates : Finset Bit) : ℝ≥0 :=
  gates.sup fun b => match st.measEnd b with
    | some t => t + C.tff
    | none => 0

/-- One leaf (`run_leaf`, and `next_outcome` for a measurement). -/
def leafT (C : Cost) (R : Record) (i : ℕ) (f : Footprint) (gates : Finset Bit)
    (st : TState) : TState :=
  if st.stopped then st else
    let fin := max (gateTime C st gates) (f.qubits.sup st.ready) + C.dur i f
    { ready := fun q => if q ∈ f.qubits then fin else st.ready q
      measEnd := fun b => if b ∈ f.writes then some fin else st.measEnd b
      vals := fun b => if b ∈ f.writes then R b (st.cursor b) else st.vals b
      cursor := fun b => if b ∈ f.writes then st.cursor b + 1 else st.cursor b
      stopped := false }

/-- A loop: at most `k` more iterations of `body`. `first` marks the first
iteration, which is not gated on the exit bits. -/
def loopT (body : Finset Bit → TState → TState) (c : Cond) (gates : Finset Bit) :
    ℕ → Bool → TState → TState
  | 0, _, st => { st with stopped := true }
  | k + 1, first, st =>
      let st' := body (if first then gates else gates ∪ c.bits) st
      if st'.stopped || c.eval st'.vals then st' else loopT body c gates k false st'

/-- `β` agrees with `v` on `G`. -/
def agrees (G : Finset Bit) (β v : Assign) : Prop := ∀ b ∈ G, β b = v b

instance (G : Finset Bit) (β v : Assign) : Decidable (agrees G β v) := by
  unfold agrees; infer_instance

mutual
/-- Replay one op with the enclosing gate bits `gates`. -/
def run (C : Cost) (R : Record) : Op → Finset Bit → TState → TState
  | .leaf i f, gates, st => leafT C R i f gates st
  | .ite c A B, gates, st =>
      if st.stopped then st
      else if c.eval st.vals then runB C R A (gates ∪ c.bits) st
      else runB C R B (gates ∪ c.bits) st
  | .loop K body c, gates, st =>
      if st.stopped then st
      else loopT (fun g t => runB C R body g t) c gates K true st
  | .switch G cases dflt, gates, st =>
      if st.stopped then st else runCases C R G cases dflt (gates ∪ G) st
  termination_by o => sizeOf o

/-- Replay a block. -/
def runB (C : Cost) (R : Record) : List Op → Finset Bit → TState → TState
  | [], _, st => st
  | o :: os, gates, st => runB C R os gates (run C R o gates st)
  termination_by l => sizeOf l

/-- The first case whose value agrees on `G`, else `dflt`. -/
def runCases (C : Cost) (R : Record) (G : Finset Bit) :
    List (Assign × List Op) → List Op → Finset Bit → TState → TState
  | [], dflt, gates, st => runB C R dflt gates st
  | (v, blk) :: cs, dflt, gates, st =>
      if agrees G st.vals v then runB C R blk gates st
      else runCases C R G cs dflt gates st
  termination_by cs dflt => sizeOf cs + sizeOf dflt
end

/-- `none ≤ none` and `some a ≤ some b` when `a ≤ b`. -/
def OptLe : Option ℝ≥0 → Option ℝ≥0 → Prop
  | none, none => True
  | some a, some b => a ≤ b
  | _, _ => False

/-- `a` is no later than `b`, with the same classical state. -/
def TState.Le (a b : TState) : Prop :=
  a.vals = b.vals ∧ a.cursor = b.cursor ∧ a.stopped = b.stopped ∧
    (∀ q, a.ready q ≤ b.ready q) ∧ (∀ x, OptLe (a.measEnd x) (b.measEnd x))

/-- The makespan over the qubits `Q` (`replay` returns it). -/
def makespan (Q : Finset Qubit) (st : TState) : ℝ≥0 := Q.sup st.ready

/-! ### Proof helpers -/

private def gv (C : Cost) : Option ℝ≥0 → ℝ≥0
  | some t => t + C.tff
  | none => 0

private theorem gateTime_eq (C : Cost) (st : TState) (gates : Finset Bit) :
    gateTime C st gates = gates.sup fun b => gv C (st.measEnd b) := by
  unfold gateTime
  congr 1

private theorem optLe_refl (x : Option ℝ≥0) : OptLe x x := by
  cases x <;> simp [OptLe]

private theorem optLe_trans {x y z : Option ℝ≥0} (h1 : OptLe x y) (h2 : OptLe y z) :
    OptLe x z := by
  cases x <;> cases y <;> cases z <;> simp only [OptLe] at *
  exact le_trans h1 h2

private theorem gv_mono (C : Cost) {x y : Option ℝ≥0} (h : OptLe x y) : gv C x ≤ gv C y := by
  cases x <;> cases y <;> simp_all [OptLe, gv]

/-- Relation between two states on a region: qubits `Q`, bits `V` (values,
cursors, end times) and bits `G` (gate times only). -/
private structure LeOn (C : Cost) (Q : Set Qubit) (V G : Set Bit) (a b : TState) : Prop where
  stop : a.stopped = b.stopped
  ready : ∀ q ∈ Q, a.ready q ≤ b.ready q
  vals : ∀ z ∈ V, a.vals z = b.vals z
  cursor : ∀ z ∈ V, a.cursor z = b.cursor z
  meas : ∀ z ∈ V, OptLe (a.measEnd z) (b.measEnd z)
  gate : ∀ z ∈ G, gv C (a.measEnd z) ≤ gv C (b.measEnd z)

/-- A footprint lies in a region. -/
private def Fits (f : Footprint) (Q : Set Qubit) (V G : Set Bit) : Prop :=
  (∀ q ∈ f.qubits, q ∈ Q) ∧ (∀ z ∈ f.reads, z ∈ V ∧ z ∈ G) ∧ (∀ z ∈ f.writes, z ∈ V)

private theorem fits_union {f f' : Footprint} {Q : Set Qubit} {V G : Set Bit}
    (h : Fits (f ∪ f') Q V G) : Fits f Q V G ∧ Fits f' Q V G := by
  obtain ⟨h1, h2, h3⟩ := h
  refine ⟨⟨fun q hq => h1 q ?_, fun z hz => h2 z ?_, fun z hz => h3 z ?_⟩,
    ⟨fun q hq => h1 q ?_, fun z hz => h2 z ?_, fun z hz => h3 z ?_⟩⟩ <;>
    first
    | exact Finset.mem_union_left _ hz
    | exact Finset.mem_union_left _ hq
    | exact Finset.mem_union_right _ hz
    | exact Finset.mem_union_right _ hq

private theorem leafT_leOn (C : Cost) (R : Record) (i : ℕ) (f : Footprint)
    (g1 g2 : Finset Bit) (Q : Set Qubit) (V G : Set Bit) (a b : TState)
    (hg : g1 ⊆ g2) (hfit : Fits f Q V G) (hgG : ∀ z ∈ g1, z ∈ G) (hab : LeOn C Q V G a b) :
    LeOn C Q V G (leafT C R i f g1 a) (leafT C R i f g2 b) := by
  obtain ⟨hq, -, hw⟩ := hfit
  unfold leafT
  cases hs : a.stopped
  · have hs' : b.stopped = false := hab.stop ▸ hs
    simp only [hs', Bool.false_eq_true, if_false]
    have hfin : max (gateTime C a g1) (f.qubits.sup a.ready) + C.dur i f ≤
        max (gateTime C b g2) (f.qubits.sup b.ready) + C.dur i f := by
      have e1 : gateTime C a g1 ≤ gateTime C b g2 := by
        rw [gateTime_eq, gateTime_eq]
        exact le_trans (Finset.sup_mono_fun fun z hz => hab.gate z (hgG z hz))
          (Finset.sup_mono hg)
      have e2 : f.qubits.sup a.ready ≤ f.qubits.sup b.ready :=
        Finset.sup_mono_fun fun q hq' => hab.ready q (hq q hq')
      exact add_le_add (max_le_max e1 e2) le_rfl
    refine ⟨rfl, ?_, ?_, ?_, ?_, ?_⟩
    · intro q hqQ
      dsimp only
      split_ifs
      · exact hfin
      · exact hab.ready q hqQ
    · intro z hz
      dsimp only
      split_ifs
      · rw [hab.cursor z hz]
      · exact hab.vals z hz
    · intro z hz
      dsimp only
      split_ifs
      · rw [hab.cursor z hz]
      · exact hab.cursor z hz
    · intro z hz
      dsimp only
      split_ifs
      · exact hfin
      · exact hab.meas z hz
    · intro z hz
      dsimp only
      split_ifs
      · simp only [gv]; gcongr
      · exact hab.gate z hz
  · have hs' : b.stopped = true := hab.stop ▸ hs
    simp only [hs', if_true]
    exact hab

private theorem loopT_leOn (C : Cost) (body : Finset Bit → TState → TState) (c : Cond)
    (gates1 gates2 : Finset Bit) (Q : Set Qubit) (V G : Set Bit)
    (hc : ∀ z ∈ c.bits, z ∈ V ∧ z ∈ G) (hg : gates1 ⊆ gates2) (hgG : ∀ z ∈ gates1, z ∈ G)
    (hbody : ∀ g1 g2 a b, g1 ⊆ g2 → (∀ z ∈ g1, z ∈ G) → LeOn C Q V G a b →
      LeOn C Q V G (body g1 a) (body g2 b)) :
    ∀ k first a b, LeOn C Q V G a b →
      LeOn C Q V G (loopT body c gates1 k first a) (loopT body c gates2 k first b) := by
  intro k
  induction k with
  | zero =>
    intro first a b hab
    simp only [loopT]
    exact ⟨rfl, hab.ready, hab.vals, hab.cursor, hab.meas, hab.gate⟩
  | succ k ih =>
    intro first a b hab
    simp only [loopT]
    have h1 : LeOn C Q V G (body (if first then gates1 else gates1 ∪ c.bits) a)
        (body (if first then gates2 else gates2 ∪ c.bits) b) := by
      apply hbody
      · split_ifs
        · exact hg
        · exact Finset.union_subset_union hg (Finset.Subset.refl _)
      · intro z hz
        split_ifs at hz
        · exact hgG z hz
        · rcases Finset.mem_union.1 hz with hz | hz
          · exact hgG z hz
          · exact (hc z hz).2
      · exact hab
    have hcond : c.eval (body (if first then gates1 else gates1 ∪ c.bits) a).vals =
        c.eval (body (if first then gates2 else gates2 ∪ c.bits) b).vals :=
      c.dep _ _ fun z hz => h1.vals z (hc z hz).1
    rw [h1.stop, hcond]
    generalize body (if first then gates1 else gates1 ∪ c.bits) a = x at h1 hcond ⊢
    generalize body (if first then gates2 else gates2 ∪ c.bits) b = y at h1 hcond ⊢
    split_ifs
    · exact h1
    · exact ih false _ _ h1

private theorem agrees_iff (G : Finset Bit) (β β' v : Assign) (h : ∀ z ∈ G, β z = β' z) :
    agrees G β v ↔ agrees G β' v := by
  unfold agrees
  exact ⟨fun h' z hz => (h z hz).symm.trans (h' z hz), fun h' z hz => (h z hz).trans (h' z hz)⟩

mutual
private theorem run_leOn (C : Cost) (R : Record) : ∀ (o : Op) (g1 g2 : Finset Bit)
    (Q : Set Qubit) (V G : Set Bit) (a b : TState), g1 ⊆ g2 → Fits (Op.fp o) Q V G →
    (∀ z ∈ g1, z ∈ G) → LeOn C Q V G a b → LeOn C Q V G (run C R o g1 a) (run C R o g2 b)
  | .leaf i f, g1, g2, Q, V, G, a, b, hg, hfit, hgG, hab => by
    simp only [run]
    exact leafT_leOn C R i f g1 g2 Q V G a b hg hfit hgG hab
  | .ite c A B, g1, g2, Q, V, G, a, b, hg, hfit, hgG, hab => by
    simp only [Op.fp] at hfit
    obtain ⟨h1, hB⟩ := fits_union hfit
    obtain ⟨hc, hA⟩ := fits_union h1
    have hc' : ∀ z ∈ c.bits, z ∈ V ∧ z ∈ G := hc.2.1
    have hg' : g1 ∪ c.bits ⊆ g2 ∪ c.bits := Finset.union_subset_union hg (Finset.Subset.refl _)
    have hgG' : ∀ z ∈ g1 ∪ c.bits, z ∈ G := fun z hz => by
      rcases Finset.mem_union.1 hz with hz | hz
      · exact hgG z hz
      · exact (hc' z hz).2
    have hcond : c.eval a.vals = c.eval b.vals := c.dep _ _ fun z hz => hab.vals z (hc' z hz).1
    simp only [run]
    rw [hab.stop, hcond]
    split_ifs
    · exact hab
    · exact runB_leOn C R A _ _ Q V G a b hg' hA hgG' hab
    · exact runB_leOn C R B _ _ Q V G a b hg' hB hgG' hab
  | .loop K body c, g1, g2, Q, V, G, a, b, hg, hfit, hgG, hab => by
    simp only [Op.fp] at hfit
    obtain ⟨hc, hb⟩ := fits_union hfit
    simp only [run]
    rw [hab.stop]
    split_ifs
    · exact hab
    · exact loopT_leOn C _ c g1 g2 Q V G hc.2.1 hg hgG
        (fun g1' g2' a' b' h1 h2 h3 => runB_leOn C R body g1' g2' Q V G a' b' h1 hb h2 h3)
        K true a b hab
  | .switch Gs cs dflt, g1, g2, Q, V, G, a, b, hg, hfit, hgG, hab => by
    simp only [Op.fp] at hfit
    obtain ⟨h1, hd⟩ := fits_union hfit
    obtain ⟨hG, hcs⟩ := fits_union h1
    have hG' : ∀ z ∈ Gs, z ∈ V ∧ z ∈ G := hG.2.1
    have hg' : g1 ∪ Gs ⊆ g2 ∪ Gs := Finset.union_subset_union hg (Finset.Subset.refl _)
    have hgG' : ∀ z ∈ g1 ∪ Gs, z ∈ G := fun z hz => by
      rcases Finset.mem_union.1 hz with hz | hz
      · exact hgG z hz
      · exact (hG' z hz).2
    simp only [run]
    rw [hab.stop]
    split_ifs
    · exact hab
    · exact runCases_leOn C R Gs cs dflt _ _ Q V G hg' hcs hgG' (fun z hz => (hG' z hz).1)
        (fun a' b' h => runB_leOn C R dflt _ _ Q V G a' b' hg' hd hgG' h) a b hab
private theorem runB_leOn (C : Cost) (R : Record) : ∀ (l : List Op) (g1 g2 : Finset Bit)
    (Q : Set Qubit) (V G : Set Bit) (a b : TState), g1 ⊆ g2 → Fits (Op.fps l) Q V G →
    (∀ z ∈ g1, z ∈ G) → LeOn C Q V G a b → LeOn C Q V G (runB C R l g1 a) (runB C R l g2 b)
  | [], _, _, _, _, _, a, b, _, _, _, hab => by simp only [runB]; exact hab
  | o :: os, g1, g2, Q, V, G, a, b, hg, hfit, hgG, hab => by
    simp only [Op.fps] at hfit
    obtain ⟨ho, hos⟩ := fits_union hfit
    simp only [runB]
    exact runB_leOn C R os g1 g2 Q V G _ _ hg hos hgG
      (run_leOn C R o g1 g2 Q V G a b hg ho hgG hab)
private theorem runCases_leOn (C : Cost) (R : Record) (Gs : Finset Bit) :
    ∀ (cs : List (Assign × List Op)) (dflt : List Op) (g1 g2 : Finset Bit)
    (Q : Set Qubit) (V G : Set Bit), g1 ⊆ g2 → Fits (Op.fpsCases cs) Q V G →
    (∀ z ∈ g1, z ∈ G) → (∀ z ∈ Gs, z ∈ V) →
    (∀ a b, LeOn C Q V G a b → LeOn C Q V G (runB C R dflt g1 a) (runB C R dflt g2 b)) →
    ∀ a b, LeOn C Q V G a b →
      LeOn C Q V G (runCases C R Gs cs dflt g1 a) (runCases C R Gs cs dflt g2 b)
  | [], dflt, g1, g2, Q, V, G, _, _, _, _, hd, a, b, hab => by
    simp only [runCases]; exact hd a b hab
  | (v, blk) :: cs, dflt, g1, g2, Q, V, G, hg, hfit, hgG, hGs, hd, a, b, hab => by
    simp only [Op.fpsCases] at hfit
    obtain ⟨hb, hcs⟩ := fits_union hfit
    have hag := agrees_iff Gs a.vals b.vals v fun z hz => hab.vals z (hGs z hz)
    simp only [runCases]
    by_cases h : agrees Gs a.vals v
    · rw [if_pos h, if_pos (hag.1 h)]
      exact runB_leOn C R blk g1 g2 Q V G a b hg hb hgG hab
    · rw [if_neg h, if_neg (fun h' => h (hag.2 h'))]
      exact runCases_leOn C R Gs cs dflt g1 g2 Q V G hg hcs hgG hGs hd a b hab
end

private theorem le_to_leOn (C : Cost) {a b : TState} (h : a.Le b) :
    LeOn C Set.univ Set.univ Set.univ a b :=
  ⟨h.2.2.1, fun q _ => h.2.2.2.1 q, fun z _ => congrFun h.1 z, fun z _ => congrFun h.2.1 z,
    fun z _ => h.2.2.2.2 z, fun z _ => gv_mono C (h.2.2.2.2 z)⟩

private theorem leOn_to_le {C : Cost} {a b : TState}
    (h : LeOn C Set.univ Set.univ Set.univ a b) : a.Le b :=
  ⟨funext fun z => h.vals z trivial, funext fun z => h.cursor z trivial, h.stop,
    fun q => h.ready q trivial, fun z => h.meas z trivial⟩

private theorem fits_univ (f : Footprint) : Fits f Set.univ Set.univ Set.univ :=
  ⟨fun _ _ => trivial, fun _ _ => ⟨trivial, trivial⟩, fun _ _ => trivial⟩

/-- The schedule is monotone in the start state and the gate bits. -/
theorem run_mono (C : Cost) (R : Record) (o : Op) (g1 g2 : Finset Bit) (h : g1 ⊆ g2)
    (a b : TState) (hab : a.Le b) : (run C R o g1 a).Le (run C R o g2 b) := by
  exact leOn_to_le (run_leOn C R o g1 g2 _ _ _ a b h (fits_univ _) (fun _ _ => trivial)
    (le_to_leOn C hab))

theorem runB_mono (C : Cost) (R : Record) (l : List Op) (g1 g2 : Finset Bit)
    (h : g1 ⊆ g2) (a b : TState) (hab : a.Le b) :
    (runB C R l g1 a).Le (runB C R l g2 b) := by
  exact leOn_to_le (runB_leOn C R l g1 g2 _ _ _ a b h (fits_univ _) (fun _ _ => trivial)
    (le_to_leOn C hab))

private theorem fpu_qubits (f g : Footprint) : (f ∪ g).qubits = f.qubits ∪ g.qubits := rfl
private theorem fpu_reads (f g : Footprint) : (f ∪ g).reads = f.reads ∪ g.reads := rfl
private theorem fpu_writes (f g : Footprint) : (f ∪ g).writes = f.writes ∪ g.writes := rfl

/-- What a run leaves alone (outside the footprint), and gate times on the
gate bits only grow. -/
private structure Ev (C : Cost) (f : Footprint) (g : Finset Bit) (a b : TState) : Prop where
  ready : ∀ q, q ∉ f.qubits → b.ready q = a.ready q
  vals : ∀ z, z ∉ f.writes → b.vals z = a.vals z
  cursor : ∀ z, z ∉ f.writes → b.cursor z = a.cursor z
  meas : ∀ z, z ∉ f.writes → b.measEnd z = a.measEnd z
  grow : ∀ z ∈ g, gv C (a.measEnd z) ≤ gv C (b.measEnd z)

private theorem ev_refl (C : Cost) (f : Footprint) (g : Finset Bit) (a : TState) :
    Ev C f g a a :=
  ⟨fun _ _ => rfl, fun _ _ => rfl, fun _ _ => rfl, fun _ _ => rfl, fun _ _ => le_rfl⟩

private theorem ev_trans {C : Cost} {f : Footprint} {g : Finset Bit} {a b c : TState}
    (h1 : Ev C f g a b) (h2 : Ev C f g b c) : Ev C f g a c :=
  ⟨fun q hq => (h2.ready q hq).trans (h1.ready q hq),
    fun z hz => (h2.vals z hz).trans (h1.vals z hz),
    fun z hz => (h2.cursor z hz).trans (h1.cursor z hz),
    fun z hz => (h2.meas z hz).trans (h1.meas z hz),
    fun z hz => (h1.grow z hz).trans (h2.grow z hz)⟩

private theorem ev_mono {C : Cost} {f f' : Footprint} {g g' : Finset Bit} {a b : TState}
    (h : Ev C f g a b) (hq : f.qubits ⊆ f'.qubits) (hw : f.writes ⊆ f'.writes) (hg : g' ⊆ g) :
    Ev C f' g' a b :=
  ⟨fun q hq' => h.ready q fun h' => hq' (hq h'),
    fun z hz => h.vals z fun h' => hz (hw h'),
    fun z hz => h.cursor z fun h' => hz (hw h'),
    fun z hz => h.meas z fun h' => hz (hw h'),
    fun z hz => h.grow z (hg hz)⟩

private theorem leafT_ev (C : Cost) (R : Record) (i : ℕ) (f : Footprint) (g : Finset Bit)
    (a : TState) : Ev C f g a (leafT C R i f g a) := by
  unfold leafT
  cases hs : a.stopped
  · simp only [Bool.false_eq_true, if_false]
    refine ⟨fun q hq => if_neg hq, fun z hz => if_neg hz, fun z hz => if_neg hz,
      fun z hz => if_neg hz, fun z hz => ?_⟩
    dsimp only
    split_ifs
    · have h1 : gv C (a.measEnd z) ≤ gateTime C a g := by
        rw [gateTime_eq]
        exact Finset.le_sup (f := fun b => gv C (a.measEnd b)) hz
      simp only [gv]
      calc gv C (a.measEnd z) ≤ gateTime C a g := h1
        _ ≤ max (gateTime C a g) (f.qubits.sup a.ready) := le_max_left _ _
        _ ≤ max (gateTime C a g) (f.qubits.sup a.ready) + C.dur i f := le_self_add
        _ ≤ max (gateTime C a g) (f.qubits.sup a.ready) + C.dur i f + C.tff := le_self_add
    · exact le_rfl
  · simp only [if_true]
    exact ev_refl C f g a

private theorem loopT_ev (C : Cost) (body : Finset Bit → TState → TState) (c : Cond)
    (gates : Finset Bit) (f : Footprint)
    (hbody : ∀ g', gates ⊆ g' → ∀ a, Ev C f g' a (body g' a)) :
    ∀ k first a, Ev C f gates a (loopT body c gates k first a) := by
  intro k
  induction k with
  | zero =>
    intro first a
    simp only [loopT]
    exact ⟨fun _ _ => rfl, fun _ _ => rfl, fun _ _ => rfl, fun _ _ => rfl, fun _ _ => le_rfl⟩
  | succ k ih =>
    intro first a
    simp only [loopT]
    have h1 : Ev C f gates a (body (if first then gates else gates ∪ c.bits) a) := by
      refine ev_mono (hbody _ ?_ a) (Finset.Subset.refl _) (Finset.Subset.refl _) ?_
      · split_ifs
        · exact Finset.Subset.refl _
        · exact Finset.subset_union_left
      · split_ifs
        · exact Finset.Subset.refl _
        · exact Finset.subset_union_left
    generalize body (if first then gates else gates ∪ c.bits) a = x at h1 ⊢
    split_ifs
    · exact h1
    · exact ev_trans h1 (ih false x)

mutual
private theorem run_ev (C : Cost) (R : Record) :
    ∀ (o : Op) (g : Finset Bit) (a : TState), Ev C (Op.fp o) g a (run C R o g a)
  | .leaf i f, g, a => by
    simp only [run, Op.fp]
    exact leafT_ev C R i f g a
  | .ite c A B, g, a => by
    simp only [run]
    split_ifs
    · exact ev_refl C _ g a
    · refine ev_mono (runB_ev C R A (g ∪ c.bits) a) ?_ ?_ Finset.subset_union_left
      · simp only [Op.fp, fpu_qubits]
        exact Finset.subset_union_right.trans Finset.subset_union_left
      · simp only [Op.fp, fpu_writes]
        exact Finset.subset_union_right.trans Finset.subset_union_left
    · refine ev_mono (runB_ev C R B (g ∪ c.bits) a) ?_ ?_ Finset.subset_union_left
      · simp only [Op.fp, fpu_qubits]
        exact Finset.subset_union_right
      · simp only [Op.fp, fpu_writes]
        exact Finset.subset_union_right
  | .loop K body c, g, a => by
    simp only [run]
    split_ifs
    · exact ev_refl C _ g a
    · refine loopT_ev C _ c g _ (fun g' _ a' => ?_) K true a
      refine ev_mono (runB_ev C R body g' a') ?_ ?_ (Finset.Subset.refl _)
      · simp only [Op.fp, fpu_qubits]
        exact Finset.subset_union_right
      · simp only [Op.fp, fpu_writes]
        exact Finset.subset_union_right
  | .switch Gs cs dflt, g, a => by
    simp only [run]
    split_ifs
    · exact ev_refl C _ g a
    · refine ev_mono (runCases_ev C R Gs cs dflt (g ∪ Gs)
        (fun a' => runB_ev C R dflt (g ∪ Gs) a') a) ?_ ?_ Finset.subset_union_left
      · simp only [Op.fp, fpu_qubits]
        exact Finset.union_subset_union Finset.subset_union_right (Finset.Subset.refl _)
      · simp only [Op.fp, fpu_writes]
        exact Finset.union_subset_union Finset.subset_union_right (Finset.Subset.refl _)
private theorem runB_ev (C : Cost) (R : Record) :
    ∀ (l : List Op) (g : Finset Bit) (a : TState), Ev C (Op.fps l) g a (runB C R l g a)
  | [], g, a => by simp only [runB]; exact ev_refl C _ g a
  | o :: os, g, a => by
    simp only [runB]
    refine ev_trans (ev_mono (run_ev C R o g a) ?_ ?_ (Finset.Subset.refl _))
      (ev_mono (runB_ev C R os g _) ?_ ?_ (Finset.Subset.refl _))
    · simp only [Op.fps, fpu_qubits]; exact Finset.subset_union_left
    · simp only [Op.fps, fpu_writes]; exact Finset.subset_union_left
    · simp only [Op.fps, fpu_qubits]; exact Finset.subset_union_right
    · simp only [Op.fps, fpu_writes]; exact Finset.subset_union_right
/-- `runCases` stays in the footprint of the cases and the default. -/
private theorem runCases_ev (C : Cost) (R : Record) (Gs : Finset Bit) :
    ∀ (cs : List (Assign × List Op)) (dflt : List Op) (g : Finset Bit),
    (∀ a, Ev C (Op.fps dflt) g a (runB C R dflt g a)) →
    ∀ a, Ev C (Op.fpsCases cs ∪ Op.fps dflt) g a (runCases C R Gs cs dflt g a)
  | [], dflt, g, hd, a => by
    simp only [runCases]
    refine ev_mono (hd a) ?_ ?_ (Finset.Subset.refl _)
    · simp only [fpu_qubits]; exact Finset.subset_union_right
    · simp only [fpu_writes]; exact Finset.subset_union_right
  | (v, blk) :: cs, dflt, g, hd, a => by
    simp only [runCases]
    split_ifs
    · refine ev_mono (runB_ev C R blk g a) ?_ ?_ (Finset.Subset.refl _)
      · simp only [Op.fpsCases, fpu_qubits]
        exact Finset.subset_union_left.trans Finset.subset_union_left
      · simp only [Op.fpsCases, fpu_writes]
        exact Finset.subset_union_left.trans Finset.subset_union_left
    · refine ev_mono (runCases_ev C R Gs cs dflt g hd a) ?_ ?_ (Finset.Subset.refl _)
      · simp only [Op.fpsCases, fpu_qubits]
        exact Finset.union_subset_union Finset.subset_union_right (Finset.Subset.refl _)
      · simp only [Op.fpsCases, fpu_writes]
        exact Finset.union_subset_union Finset.subset_union_right (Finset.Subset.refl _)
end

/-- Stopped stays true: every op skips a stopped state. -/
private theorem run_stopped (C : Cost) (R : Record) (o : Op) (g : Finset Bit) (st : TState)
    (h : st.stopped = true) : run C R o g st = st := by
  cases o <;> simp [run, leafT, h]

private theorem runB_stopped (C : Cost) (R : Record) (l : List Op) (g : Finset Bit)
    (st : TState) (h : st.stopped = true) : runB C R l g st = st := by
  induction l with
  | nil => simp only [runB]
  | cons o os ih => simp only [runB, run_stopped C R o g st h, ih]

private theorem runB_not_stopped {C : Cost} {R : Record} {l : List Op} {g : Finset Bit}
    {st : TState} (h : (runB C R l g st).stopped = false) : st.stopped = false := by
  cases hs : st.stopped
  · rfl
  · rw [runB_stopped C R l g st hs, hs] at h
    exact h

private theorem runB_append' (C : Cost) (R : Record) (l1 l2 : List Op) (g : Finset Bit)
    (st : TState) : runB C R (l1 ++ l2) g st = runB C R l2 g (runB C R l1 g st) := by
  induction l1 generalizing st with
  | nil => simp only [List.nil_append, runB]
  | cons o os ih => simp only [List.cons_append, runB, ih]

private theorem runB_single (C : Cost) (R : Record) (x : Op) (g : Finset Bit) (st : TState) :
    runB C R [x] g st = run C R x g st := by
  simp only [runB]

private theorem disj_empty_left (g : Footprint) : Footprint.empty.Disj g := by
  simp [Footprint.Disj, Footprint.empty]

private theorem disj_union_left' {f f' g : Footprint} (h : f.Disj g) (h' : f'.Disj g) :
    (f ∪ f').Disj g := by
  obtain ⟨h1, h2, h3, h4⟩ := h
  obtain ⟨h1', h2', h3', h4'⟩ := h'
  refine ⟨?_, ?_, ?_, ?_⟩
  · rw [fpu_qubits]; exact Finset.disjoint_union_left.2 ⟨h1, h1'⟩
  · rw [fpu_writes]; exact Finset.disjoint_union_left.2 ⟨h2, h2'⟩
  · rw [fpu_writes]; exact Finset.disjoint_union_left.2 ⟨h3, h3'⟩
  · rw [fpu_reads]; exact Finset.disjoint_union_left.2 ⟨h4, h4'⟩

private theorem disj_fps_right (f : Footprint) (l : List Op)
    (h : ∀ y ∈ l, f.Disj (Op.fp y)) : f.Disj (Op.fps l) := by
  induction l with
  | nil => simp only [Op.fps]; exact (disj_empty_left f).symm
  | cons y l ih =>
    simp only [Op.fps]
    exact (disj_union_left' (h y List.mem_cons_self).symm
      (ih fun y' hy' => h y' (List.mem_cons_of_mem _ hy')).symm).symm

private theorem fps_single (x : Op) : Op.fps [x] = Op.fp x ∪ Footprint.empty := by
  simp only [Op.fps]

private theorem disj_single_left (x : Op) (g : Footprint) (h : (Op.fp x).Disj g) :
    (Op.fps [x]).Disj g := by
  rw [fps_single]
  exact disj_union_left' h (disj_empty_left g)

private theorem disjoint_fps_writes (g : Finset Bit) (l : List Op)
    (h : ∀ y ∈ l, Disjoint g (Op.fp y).writes) : Disjoint g (Op.fps l).writes := by
  induction l with
  | nil => simp [Op.fps, Footprint.empty]
  | cons y l ih =>
    simp only [Op.fps, fpu_writes]
    exact Finset.disjoint_union_right.2
      ⟨h y List.mem_cons_self, ih fun y' hy' => h y' (List.mem_cons_of_mem _ hy')⟩

/-- Two blocks with disjoint footprints: running `P` first is no later than
running `Qs` first, when `P` writes no gate bit of `Qs` and the gate bits of
`P` are gate bits of `Qs` in the second order. -/
private theorem swap_blocks (C : Cost) (R : Record) (P Qs : List Op)
    (gP1 gP2 gQ1 gQ2 : Finset Bit) (s : TState)
    (hd : (Op.fps P).Disj (Op.fps Qs)) (hw : Disjoint gQ1 (Op.fps P).writes)
    (hP : gP1 ⊆ gP2) (hQ : gQ1 ⊆ gQ2) (hPQ : gP1 ⊆ gQ2)
    (hstop : (runB C R P gP2 (runB C R Qs gQ2 s)).stopped = false) :
    (runB C R Qs gQ1 (runB C R P gP1 s)).Le (runB C R P gP2 (runB C R Qs gQ2 s)) := by
  obtain ⟨dq, dww, dwr, drw⟩ := hd
  have hb's : (runB C R Qs gQ2 s).stopped = false := runB_not_stopped hstop
  have hs : s.stopped = false := runB_not_stopped hb's
  have e1 := runB_ev C R P gP1 s
  have e2 := runB_ev C R Qs gQ2 s
  have e3 := runB_ev C R Qs gQ1 (runB C R P gP1 s)
  have e4 := runB_ev C R P gP2 (runB C R Qs gQ2 s)
  set a' := runB C R P gP1 s with ha'
  set b' := runB C R Qs gQ2 s with hb'
  have s1 : LeOn C {q | q ∈ (Op.fps P).qubits} {z | z ∈ (Op.fps P).reads ∨ z ∈ (Op.fps P).writes}
      {z | z ∈ gP1 ∨ z ∈ (Op.fps P).reads} s b' := by
    refine ⟨hs.trans hb's.symm, ?_, ?_, ?_, ?_, ?_⟩
    · intro q hq
      rw [e2.ready q (Finset.disjoint_left.1 dq hq)]
    · intro z hz
      have : z ∉ (Op.fps Qs).writes := by
        rcases hz with hz | hz
        · exact Finset.disjoint_left.1 drw hz
        · exact Finset.disjoint_left.1 dww hz
      rw [e2.vals z this]
    · intro z hz
      have : z ∉ (Op.fps Qs).writes := by
        rcases hz with hz | hz
        · exact Finset.disjoint_left.1 drw hz
        · exact Finset.disjoint_left.1 dww hz
      rw [e2.cursor z this]
    · intro z hz
      have : z ∉ (Op.fps Qs).writes := by
        rcases hz with hz | hz
        · exact Finset.disjoint_left.1 drw hz
        · exact Finset.disjoint_left.1 dww hz
      rw [e2.meas z this]
      exact optLe_refl _
    · intro z hz
      rcases hz with hz | hz
      · exact e2.grow z (hPQ hz)
      · rw [e2.meas z (Finset.disjoint_left.1 drw hz)]
  have r1 := runB_leOn C R P gP1 gP2 _ _ _ s b' hP
    ⟨fun q hq => hq, fun z hz => ⟨Or.inl hz, Or.inr hz⟩, fun z hz => Or.inr hz⟩
    (fun z hz => Or.inl hz) s1
  have s2 : LeOn C {q | q ∈ (Op.fps Qs).qubits}
      {z | z ∈ (Op.fps Qs).reads ∨ z ∈ (Op.fps Qs).writes}
      {z | z ∈ gQ1 ∨ z ∈ (Op.fps Qs).reads} a' s := by
    refine ⟨r1.stop.trans (hstop.trans hs.symm), ?_, ?_, ?_, ?_, ?_⟩
    · intro q hq
      rw [e1.ready q (Finset.disjoint_right.1 dq hq)]
    · intro z hz
      have : z ∉ (Op.fps P).writes := by
        rcases hz with hz | hz
        · exact Finset.disjoint_right.1 dwr hz
        · exact Finset.disjoint_right.1 dww hz
      rw [e1.vals z this]
    · intro z hz
      have : z ∉ (Op.fps P).writes := by
        rcases hz with hz | hz
        · exact Finset.disjoint_right.1 dwr hz
        · exact Finset.disjoint_right.1 dww hz
      rw [e1.cursor z this]
    · intro z hz
      have : z ∉ (Op.fps P).writes := by
        rcases hz with hz | hz
        · exact Finset.disjoint_right.1 dwr hz
        · exact Finset.disjoint_right.1 dww hz
      rw [e1.meas z this]
      exact optLe_refl _
    · intro z hz
      have : z ∉ (Op.fps P).writes := by
        rcases hz with hz | hz
        · exact Finset.disjoint_left.1 hw hz
        · exact Finset.disjoint_right.1 dwr hz
      rw [e1.meas z this]
  have r2 := runB_leOn C R Qs gQ1 gQ2 _ _ _ a' s hQ
    ⟨fun q hq => hq, fun z hz => ⟨Or.inl hz, Or.inr hz⟩, fun z hz => Or.inr hz⟩
    (fun z hz => Or.inl hz) s2
  refine ⟨funext fun z => ?_, funext fun z => ?_, r2.stop.trans (hb's.trans hstop.symm),
    fun q => ?_, fun z => ?_⟩
  · by_cases hzP : z ∈ (Op.fps P).writes
    · rw [e3.vals z (Finset.disjoint_left.1 dww hzP)]
      exact r1.vals z (Or.inr hzP)
    · by_cases hzQ : z ∈ (Op.fps Qs).writes
      · rw [e4.vals z hzP]
        exact r2.vals z (Or.inr hzQ)
      · rw [e3.vals z hzQ, e4.vals z hzP, e1.vals z hzP, e2.vals z hzQ]
  · by_cases hzP : z ∈ (Op.fps P).writes
    · rw [e3.cursor z (Finset.disjoint_left.1 dww hzP)]
      exact r1.cursor z (Or.inr hzP)
    · by_cases hzQ : z ∈ (Op.fps Qs).writes
      · rw [e4.cursor z hzP]
        exact r2.cursor z (Or.inr hzQ)
      · rw [e3.cursor z hzQ, e4.cursor z hzP, e1.cursor z hzP, e2.cursor z hzQ]
  · by_cases hqP : q ∈ (Op.fps P).qubits
    · rw [e3.ready q (Finset.disjoint_left.1 dq hqP)]
      exact r1.ready q hqP
    · by_cases hqQ : q ∈ (Op.fps Qs).qubits
      · rw [e4.ready q hqP]
        exact r2.ready q hqQ
      · rw [e3.ready q hqQ, e4.ready q hqP, e1.ready q hqP, e2.ready q hqQ]
  · by_cases hzP : z ∈ (Op.fps P).writes
    · rw [e3.meas z (Finset.disjoint_left.1 dww hzP)]
      exact r1.meas z (Or.inr hzP)
    · by_cases hzQ : z ∈ (Op.fps Qs).writes
      · rw [e4.meas z hzP]
        exact r2.meas z (Or.inr hzQ)
      · rw [e3.meas z hzQ, e4.meas z hzP, e1.meas z hzP, e2.meas z hzQ]
        exact optLe_refl _

private theorem hoist_branch (C : Cost) (R : Record) (x : Op) (p Z : List Op)
    (gates g' : Finset Bit) (st : TState)
    (hp : ∀ y ∈ p, (Op.fp x).Disj (Op.fp y)) (hsub : gates ⊆ g')
    (hw : Disjoint g' (Op.fp x).writes)
    (hrun : (runB C R (p ++ x :: Z) g' st).stopped = false) :
    (run C R x gates st).stopped = false ∧
      (runB C R (p ++ Z) g' (run C R x gates st)).Le (runB C R (p ++ x :: Z) g' st) := by
  rw [runB_append'] at hrun ⊢
  rw [runB_append']
  simp only [runB] at hrun ⊢
  have hd : (Op.fps [x]).Disj (Op.fps p) := disj_single_left x _ (disj_fps_right _ p hp)
  have hw' : Disjoint g' (Op.fps [x]).writes := by
    rw [fps_single, fpu_writes]
    simpa [Footprint.empty] using hw
  have key := swap_blocks C R [x] p gates g' g' g' st hd hw' hsub (Finset.Subset.refl _) hsub
    (by rw [runB_single]; exact runB_not_stopped hrun)
  rw [runB_single, runB_single] at key
  refine ⟨runB_not_stopped (key.2.2.1.trans (runB_not_stopped hrun)), ?_⟩
  exact runB_mono C R Z g' g' (Finset.Subset.refl _) _ _ key

/-- A hoist step does not increase latency: side conditions of
`hoist_sound`, plus `x` writes no enclosing gate bit. -/
theorem hoist_latency (C : Cost) (R : Record) (c : Cond) (x : Op) (pA A pB B : List Op)
    (gates : Finset Bit)
    (hA : ∀ y ∈ pA, (Op.fp x).Disj (Op.fp y))
    (hB : ∀ y ∈ pB, (Op.fp x).Disj (Op.fp y))
    (hc : Disjoint c.bits (Op.fp x).writes)
    (henc : Disjoint gates (Op.fp x).writes)
    (st : TState) (hst : st.stopped = false)
    (hrun : (run C R (.ite c (pA ++ x :: A) (pB ++ x :: B)) gates st).stopped = false) :
    (runB C R [x, .ite c (pA ++ A) (pB ++ B)] gates st).Le
      (run C R (.ite c (pA ++ x :: A) (pB ++ x :: B)) gates st) := by
  have hg : gates ⊆ gates ∪ c.bits := Finset.subset_union_left
  have hw : Disjoint (gates ∪ c.bits) (Op.fp x).writes := Finset.disjoint_union_left.2 ⟨henc, hc⟩
  have hce' : c.eval (run C R x gates st).vals = c.eval st.vals :=
    c.dep _ _ fun z hz => (run_ev C R x gates st).vals z (Finset.disjoint_left.1 hc hz)
  simp only [runB]
  simp only [run, hst, Bool.false_eq_true, if_false] at hrun ⊢
  by_cases hce : c.eval st.vals = true
  · rw [if_pos hce] at hrun ⊢
    obtain ⟨h1, h2⟩ := hoist_branch C R x pA A gates _ st hA hg hw hrun
    rw [h1, hce', if_pos hce]
    exact h2
  · rw [if_neg hce] at hrun ⊢
    obtain ⟨h1, h2⟩ := hoist_branch C R x pB B gates _ st hB hg hw hrun
    rw [h1, hce', if_neg hce]
    exact h2

/-- A merge step does not increase latency: side conditions of
`merge_sound`, plus the ops `x` moves past write no enclosing gate bit. -/
theorem merge_latency (C : Cost) (R : Record) (c : Cond) (x : Op) (A sA B sB : List Op)
    (gates : Finset Bit)
    (hA : ∀ y ∈ sA, (Op.fp x).Disj (Op.fp y))
    (hB : ∀ y ∈ sB, (Op.fp x).Disj (Op.fp y))
    (hencA : ∀ y ∈ sA, Disjoint gates (Op.fp y).writes)
    (hencB : ∀ y ∈ sB, Disjoint gates (Op.fp y).writes)
    (st : TState) (hst : st.stopped = false)
    (hrun : (run C R (.ite c (A ++ x :: sA) (B ++ x :: sB)) gates st).stopped = false) :
    (runB C R [.ite c (A ++ sA) (B ++ sB), x] gates st).Le
      (run C R (.ite c (A ++ x :: sA) (B ++ x :: sB)) gates st) := by
  have hg : gates ⊆ gates ∪ c.bits := Finset.subset_union_left
  simp only [runB]
  simp only [run, hst, Bool.false_eq_true, if_false] at hrun ⊢
  by_cases hce : c.eval st.vals = true
  · simp only [if_pos hce] at hrun ⊢
    rw [runB_append'] at hrun ⊢
    rw [runB_append']
    simp only [runB] at hrun ⊢
    have key := swap_blocks C R sA [x] (gates ∪ c.bits) (gates ∪ c.bits) gates (gates ∪ c.bits)
      (runB C R A (gates ∪ c.bits) st) (disj_single_left x _ (disj_fps_right _ sA hA)).symm
      (disjoint_fps_writes gates sA hencA) (Finset.Subset.refl _) hg (Finset.Subset.refl _)
      (by rw [runB_single]; exact hrun)
    rw [runB_single, runB_single] at key
    exact key
  · simp only [if_neg hce] at hrun ⊢
    rw [runB_append'] at hrun ⊢
    rw [runB_append']
    simp only [runB] at hrun ⊢
    have key := swap_blocks C R sB [x] (gates ∪ c.bits) (gates ∪ c.bits) gates (gates ∪ c.bits)
      (runB C R B (gates ∪ c.bits) st) (disj_single_left x _ (disj_fps_right _ sB hB)).symm
      (disjoint_fps_writes gates sB hencB) (Finset.Subset.refl _) hg (Finset.Subset.refl _)
      (by rw [runB_single]; exact hrun)
    rw [runB_single, runB_single] at key
    exact key

/-- No later, pointwise, gives no larger makespan. -/
theorem makespan_le (Q : Finset Qubit) (a b : TState) (h : a.Le b) :
    makespan Q a ≤ makespan Q b := by
  exact Finset.sup_mono_fun fun q _ => h.2.2.2.1 q

end Qlin
