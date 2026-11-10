import Qlin.Check
import Qlin.Latency

/-!
# Translation validation of latency: a checker for the M0 pass

`checkBlock` (Check.lean) validates that an M0 output has the semantics of
its input. `checkLat` validates the timing claim C1 for the same output.
It accepts the derivations that `checkBlock` accepts, with one more
argument `E`, an upper bound of the enclosing gate bits, and two more
side conditions, those of `hoist_latency` and `merge_latency`:
- a hoisted op writes no bit of `E`;
- the ops that a merged op moves past write no bit of `E`.

`checkLat_sound`: a `true` answer implies that the replay of the target
is pointwise no later than the replay of the source (ideal model), from
any no-later start state whose bits of `W` are 0, under any gate bits
inside `E`, on every record on which the source does not stop.
-/

namespace Qlin.TV

open Qlin

/-- `Q` is no later than `P` under the gate bits `g`, from start states
whose bits of `W` are 0, when the run of `P` does not stop. -/
def NoLaterW (C : Cost) (R : Record) (W g : Finset Bit) (P Q : List Op) : Prop :=
  ∀ a b : TState, a.Le b → (∀ z ∈ W, b.vals z = false) → (runB C R P g b).stopped = false →
    (runB C R Q g a).Le (runB C R P g b)

theorem noLaterW_empty {C : Cost} {R : Record} {g : Finset Bit} {P Q : List Op}
    (h : NoLaterW C R ∅ g P Q) : NoLaterAt C R g P Q :=
  fun a b hab hrun => h a b hab (fun z hz => absurd hz (Finset.notMem_empty z)) hrun

/-! ## Hoist and merge with the enclosing-bit conditions -/

/-- `hoistAll`, and each hoisted op writes no bit of `E`. -/
def hoistAllT (E : Finset Bit) (c : SExpr) :
    List SOp → List SOp → List SOp → Option (List SOp × List SOp)
  | [], A, B => some (A, B)
  | h :: H, A, B =>
    if Disjoint c.bits (writesO h) ∧ Disjoint E (writesO h) then
      match takeOut h A, takeOut h B with
      | some (pA, A1), some (pB, B1) => hoistAllT E c H (pA ++ A1) (pB ++ B1)
      | _, _ => none
    else none

private theorem toOps_disj (x : SOp) (p : List SOp)
    (hp : ∀ y ∈ p, (Op.fp (SOp.toOp x)).Disj (Op.fp (SOp.toOp y))) :
    ∀ y ∈ SOp.toOps p, (Op.fp (SOp.toOp x)).Disj (Op.fp y) := by
  intro y hy
  rw [SOp.toOps_eq_map, List.mem_map] at hy
  obtain ⟨z, hz, rfl⟩ := hy
  exact hp z hz

private theorem toOps_enc (E : Finset Bit) (p : List SOp)
    (hp : ∀ y ∈ p, Disjoint E (writesO y)) :
    ∀ y ∈ SOp.toOps p, Disjoint E (Op.fp y).writes := by
  intro y hy
  rw [SOp.toOps_eq_map, List.mem_map] at hy
  obtain ⟨z, hz, rfl⟩ := hy
  exact hp z hz

theorem hoistAllT_steps (E : Finset Bit) (c : SExpr) : ∀ (H A B A' B' : List SOp),
    hoistAllT E c H A B = some (A', B') →
    M0Steps E [.ite c.toCond (SOp.toOps A) (SOp.toOps B)]
      (SOp.toOps H ++ [.ite c.toCond (SOp.toOps A') (SOp.toOps B')]) := by
  intro H
  induction H with
  | nil =>
    intro A B A' B' h
    simp only [hoistAllT, Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    simpa [SOp.toOps] using M0Steps.refl E [.ite c.toCond (SOp.toOps A) (SOp.toOps B)]
  | cons x H ih =>
    intro A B A' B' h
    unfold hoistAllT at h
    split_ifs at h with hc
    split at h
    · rename_i pA A1 pB B1 hA hB
      obtain ⟨rfl, hdA⟩ := takeOut_spec x _ _ _ hA
      obtain ⟨rfl, hdB⟩ := takeOut_spec x _ _ _ hB
      have step := M0Steps.hoist E c.toCond (SOp.toOp x) (SOp.toOps pA) (SOp.toOps A1)
        (SOp.toOps pB) (SOp.toOps B1) (toOps_disj x pA hdA) (toOps_disj x pB hdB) hc.1 hc.2
      have rest := M0Steps.frame [SOp.toOp x] [] (ih _ _ _ _ h)
      simp only [SOp.toOps_append, SOp.toOps, List.append_nil, List.cons_append,
        List.nil_append] at step rest ⊢
      exact step.trans rest
    · simp at h

/-- `mergeRev`, and the ops that each merged op moves past write no bit
of `E`. -/
def mergeRevT (E : Finset Bit) (c : SExpr) :
    List SOp → List SOp → List SOp → Option (List SOp × List SOp)
  | [], A, B => some (A, B)
  | m :: R, A, B =>
    match takeOutLast m A, takeOutLast m B with
    | some (A1, sA), some (B1, sB) =>
      if (∀ y ∈ sA, Disjoint E (writesO y)) ∧ (∀ y ∈ sB, Disjoint E (writesO y)) then
        mergeRevT E c R (A1 ++ sA) (B1 ++ sB)
      else none
    | _, _ => none

theorem mergeRevT_steps (E : Finset Bit) (c : SExpr) : ∀ (R A B A' B' : List SOp),
    mergeRevT E c R A B = some (A', B') →
    M0Steps E [.ite c.toCond (SOp.toOps A) (SOp.toOps B)]
      (.ite c.toCond (SOp.toOps A') (SOp.toOps B') :: SOp.toOps R.reverse) := by
  intro R
  induction R with
  | nil =>
    intro A B A' B' h
    simp only [mergeRevT, Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    simpa [SOp.toOps] using M0Steps.refl E [.ite c.toCond (SOp.toOps A) (SOp.toOps B)]
  | cons x R ih =>
    intro A B A' B' h
    unfold mergeRevT at h
    split at h
    · rename_i A1 sA B1 sB hA hB
      split_ifs at h with henc
      obtain ⟨rfl, hdA⟩ := takeOutLast_spec x _ _ _ hA
      obtain ⟨rfl, hdB⟩ := takeOutLast_spec x _ _ _ hB
      have step := M0Steps.merge E c.toCond (SOp.toOp x) (SOp.toOps A1) (SOp.toOps sA)
        (SOp.toOps B1) (SOp.toOps sB) (toOps_disj x sA hdA) (toOps_disj x sB hdB)
        (toOps_enc E sA henc.1) (toOps_enc E sB henc.2)
      have rest := M0Steps.frame [] [SOp.toOp x] (ih _ _ _ _ h)
      simp only [SOp.toOps_append, SOp.toOps, List.reverse_cons, List.cons_append,
        List.nil_append] at step rest ⊢
      exact step.trans rest
    · simp at h

/-! ## The latency checker -/

/-- Does `tgt` follow from `src` by M0 steps that satisfy the latency side
conditions? `W`: bits known to be 0. `E`: an upper bound of the enclosing
gate bits. `fuel` bounds the recursion. -/
def checkLat : ℕ → Finset Bit → Finset Bit → List SOp → List SOp → Bool
  | 0, _, _, _, _ => false
  | _ + 1, _, _, [], tgt => tgt.isEmpty
  | f + 1, W, E, o :: rest, tgt =>
    match o with
    | .ite c A B =>
      (foldsTo W c true && checkLat f W E (A ++ rest) tgt) ||
      (foldsTo W c false && checkLat f W E (B ++ rest) tgt) ||
      (List.range tgt.length).any fun j =>
        match tgt[j]? with
        | some (.ite c' A' B') =>
          decide (c = c') &&
          match hoistAllT E c (tgt.take j) A B with
          | none => false
          | some (A1, B1) =>
            (List.range (tgt.length - j)).any fun m =>
              match mergeRevT E c ((tgt.drop (j + 1)).take m).reverse A1 B1 with
              | none => false
              | some (A2, B2) =>
                checkLat f (W \ writesL (tgt.take j)) (E ∪ c.bits) A2 A' &&
                checkLat f (W \ writesL (tgt.take j)) (E ∪ c.bits) B2 B' &&
                checkLat f (W \ writesO (.ite c A B)) E rest ((tgt.drop (j + 1)).drop m)
        | _ => false
    | .leaf l =>
      match tgt with
      | .leaf l' :: tgt' => decide (l = l') && checkLat f (W \ writesO (.leaf l)) E rest tgt'
      | _ => false
    | .loop K body c =>
      match tgt with
      | .loop K' body' c' :: tgt' =>
        decide (K = K') && decide (c = c') && checkLat f ∅ (E ∪ c.bits) body body' &&
          checkLat f (W \ writesO (.loop K body c)) E rest tgt'
      | _ => false
    | .switch G cs d =>
      match tgt with
      | .switch G' cs' d' :: tgt' =>
        decide (G = G') && decide (cs.map Prod.fst = cs'.map Prod.fst) &&
          ((cs.zip cs').all fun p => checkLat f ∅ (E ∪ G.toFinset) p.1.2 p.2.2) &&
          checkLat f ∅ (E ∪ G.toFinset) d d' &&
          checkLat f (W \ writesO (.switch G cs d)) E rest tgt'
      | _ => false

/-! ## Soundness -/

theorem cons_noLaterW (C : Cost) (R : Record) {W g : Finset Bit} {o o' : Op}
    {rest rest' : List Op}
    (hhead : ∀ a b : TState, a.Le b → (run C R o g b).stopped = false →
      (run C R o' g a).Le (run C R o g b))
    (htail : NoLaterW C R (W \ (Op.fp o).writes) g rest rest') :
    NoLaterW C R W g (o :: rest) (o' :: rest') := by
  intro a b hab hW hrun
  simp only [runB] at hrun ⊢
  have h1 := hhead a b hab (runB_running hrun)
  refine htail _ _ h1 (fun z hz => ?_) hrun
  rw [Finset.mem_sdiff] at hz
  rw [run_vals C R o g b z hz.2]
  exact hW z hz.1

theorem cases_noLater (C : Cost) (R : Record) (G : List Bit) (G' gates : Finset Bit)
    {d d' : List Op} (hd : NoLaterAt C R gates d d') :
    ∀ (cs cs' : List (List Bool × List SOp)), cs.map Prod.fst = cs'.map Prod.fst →
      (∀ p ∈ cs.zip cs', NoLaterAt C R gates (SOp.toOps p.1.2) (SOp.toOps p.2.2)) →
      ∀ a b : TState, a.Le b →
        (runCases C R G' (SOp.toCases G cs) d gates b).stopped = false →
        (runCases C R G' (SOp.toCases G cs') d' gates a).Le
          (runCases C R G' (SOp.toCases G cs) d gates b) := by
  intro cs
  induction cs with
  | nil =>
    intro cs' hv _ a b hab h
    cases cs' with
    | nil =>
      simp only [SOp.toCases, runCases] at h ⊢
      exact hd a b hab h
    | cons _ _ => simp at hv
  | cons p cs ih =>
    intro cs' hv hb a b hab h
    cases cs' with
    | nil => simp at hv
    | cons p' cs' =>
      obtain ⟨v, blk⟩ := p
      obtain ⟨v', blk'⟩ := p'
      simp only [List.map_cons, List.cons.injEq] at hv
      obtain ⟨rfl, hv⟩ := hv
      simp only [SOp.toCases, runCases, hab.1] at h ⊢
      by_cases hg : agrees G' b.vals (assignOf G v)
      · rw [if_pos hg] at h
        rw [if_pos hg, if_pos hg]
        exact hb ((v, blk), (v, blk')) (by simp) a b hab h
      · rw [if_neg hg] at h
        rw [if_neg hg, if_neg hg]
        exact ih cs' hv (fun q hq => hb q (by simp [hq])) a b hab h

theorem fold_noLater (C : Cost) (R : Record) {W g : Finset Bit} {c : SExpr}
    {A B rest : List SOp} {tgt : List Op} (v : Bool) (hf : foldsTo W c v = true)
    (h : NoLaterW C R W g (SOp.toOps ((if v then A else B) ++ rest)) tgt) :
    NoLaterW C R W g (SOp.toOp (.ite c A B) :: SOp.toOps rest) tgt := by
  intro a b hab hW hrun
  have hc : c.toCond.eval b.vals = v := foldsTo_sound hf b.vals hW
  simp only [runB] at hrun ⊢
  have hb : b.stopped = false := run_running (runB_running hrun)
  have e : run C R (SOp.toOp (.ite c A B)) g b =
      runB C R (SOp.toOps (if v then A else B)) (g ∪ c.toCond.bits) b := by
    cases v <;> simp [SOp.toOp, run, hb, hc]
  rw [e] at hrun ⊢
  have hs : (runB C R (SOp.toOps (if v then A else B)) g b).Le
      (runB C R (SOp.toOps (if v then A else B)) (g ∪ c.toCond.bits) b) :=
    runB_mono C R _ _ _ Finset.subset_union_left b b (TState.Le.refl b)
  have hr := runB_mono C R (SOp.toOps rest) g g (Finset.Subset.refl _) _ _ hs
  have hrun' : (runB C R (SOp.toOps ((if v then A else B) ++ rest)) g b).stopped = false := by
    rw [SOp.toOps_append, runB_append, hr.2.2.1]
    exact hrun
  have key := h a b hab hW hrun'
  rw [SOp.toOps_append, runB_append] at key
  exact key.trans hr

/-- One hoist-and-merge step of the checker, as a latency bound. -/
theorem ite_stepT (C : Cost) (R : Record) {W E : Finset Bit} {c : SExpr}
    {A B rest H A' B' M T' A1 B1 A2 B2 : List SOp}
    (hH : hoistAllT E c H A B = some (A1, B1))
    (hM : mergeRevT E c M.reverse A1 B1 = some (A2, B2))
    (hA : ∀ g, g ⊆ E ∪ c.bits → NoLaterW C R (W \ writesL H) g (SOp.toOps A2) (SOp.toOps A'))
    (hB : ∀ g, g ⊆ E ∪ c.bits → NoLaterW C R (W \ writesL H) g (SOp.toOps B2) (SOp.toOps B'))
    (hR : ∀ g, g ⊆ E → NoLaterW C R (W \ writesO (.ite c A B)) g (SOp.toOps rest)
      (SOp.toOps T')) :
    ∀ g, g ⊆ E → NoLaterW C R W g (SOp.toOps (.ite c A B :: rest))
      (SOp.toOps (H ++ .ite c A' B' :: (M ++ T'))) := by
  intro g hg a b hab hW hrun
  -- the source: the `if`, then the rest
  have e_src : runB C R (SOp.toOps (.ite c A B :: rest)) g b =
      runB C R (SOp.toOps rest) g (run C R (SOp.toOp (.ite c A B)) g b) := by
    simp only [SOp.toOps, runB]
  rw [e_src] at hrun ⊢
  have hs : (runB C R [SOp.toOp (.ite c A B)] g b).stopped = false := by
    simp only [runB]; exact runB_running hrun
  -- hoists and merges: an M0Steps chain to the middle program
  have h1 := hoistAllT_steps E c H A B A1 B1 hH
  have h2 := M0Steps.frame (SOp.toOps H) [] (mergeRevT_steps E c M.reverse A1 B1 A2 B2 hM)
  rw [List.reverse_reverse] at h2
  simp only [List.append_nil] at h2
  have chain : M0Steps E [SOp.toOp (.ite c A B)]
      (SOp.toOps H ++ (.ite c.toCond (SOp.toOps A2) (SOp.toOps B2) :: SOp.toOps M)) := by
    simp only [SOp.toOp]
    exact h1.trans h2
  have hmid := m0Steps_latency C R chain g hg b b (TState.Le.refl b) hs
  simp only [runB] at hs
  rw [runB_append] at hmid
  simp only [runB] at hmid
  -- the arms: congruence under the `if`
  have hH1 := runB_mono C R (SOp.toOps H) g g (Finset.Subset.refl _) a b hab
  have hW1 : ∀ z ∈ W \ writesL H, (runB C R (SOp.toOps H) g b).vals z = false := by
    intro z hz
    rw [Finset.mem_sdiff] at hz
    rw [runB_vals C R _ g b z hz.2]
    exact hW z hz.1
  have hmid_run : (runB C R (SOp.toOps M) g (run C R (.ite c.toCond (SOp.toOps A2)
      (SOp.toOps B2)) g (runB C R (SOp.toOps H) g b))).stopped = false := by
    rw [hmid.2.2.1]; exact hs
  have hite_run := runB_running hmid_run
  have hb1 : (runB C R (SOp.toOps H) g b).stopped = false := run_running hite_run
  have ha1 : (runB C R (SOp.toOps H) g a).stopped = false := by rw [hH1.2.2.1, hb1]
  have hgc : g ∪ c.toCond.bits ⊆ E ∪ c.bits :=
    Finset.union_subset_union hg (Finset.Subset.refl _)
  have harms : (run C R (.ite c.toCond (SOp.toOps A') (SOp.toOps B')) g
      (runB C R (SOp.toOps H) g a)).Le
      (run C R (.ite c.toCond (SOp.toOps A2) (SOp.toOps B2)) g
        (runB C R (SOp.toOps H) g b)) := by
    simp only [run, hb1, ha1, hH1.1, Bool.false_eq_true, if_false] at hite_run ⊢
    by_cases hce : c.toCond.eval (runB C R (SOp.toOps H) g b).vals = true
    · rw [if_pos hce] at hite_run
      rw [if_pos hce, if_pos hce]
      exact hA _ hgc _ _ hH1 hW1 hite_run
    · rw [if_neg hce] at hite_run
      rw [if_neg hce, if_neg hce]
      exact hB _ hgc _ _ hH1 hW1 hite_run
  have hM1 := runB_mono C R (SOp.toOps M) g g (Finset.Subset.refl _) _ _ harms
  have hhead := hM1.trans hmid
  -- the rest
  have hW2 : ∀ z ∈ W \ writesO (.ite c A B),
      (run C R (SOp.toOp (.ite c A B)) g b).vals z = false := by
    intro z hz
    rw [Finset.mem_sdiff] at hz
    rw [run_vals C R _ g b z hz.2]
    exact hW z hz.1
  have key := hR g hg _ _ hhead hW2 hrun
  have e_tgt : runB C R (SOp.toOps (H ++ .ite c A' B' :: (M ++ T'))) g a =
      runB C R (SOp.toOps T') g (runB C R (SOp.toOps M) g
        (run C R (.ite c.toCond (SOp.toOps A') (SOp.toOps B')) g
          (runB C R (SOp.toOps H) g a))) := by
    simp only [SOp.toOps_append, SOp.toOps, SOp.toOp, runB_append, runB]
  rw [e_tgt]
  exact key

/-- A `true` answer of the latency checker implies that the target is no
later than the source in the replay model. -/
theorem checkLat_sound : ∀ (f : ℕ) (W E : Finset Bit) (src tgt : List SOp),
    checkLat f W E src tgt = true →
    ∀ (C : Cost) (R : Record) (g : Finset Bit), g ⊆ E →
      NoLaterW C R W g (SOp.toOps src) (SOp.toOps tgt) := by
  intro f
  induction f with
  | zero => intro W E src tgt h; simp [checkLat] at h
  | succ f ih =>
    intro W E src tgt h C R g hg
    cases src with
    | nil =>
      simp only [checkLat, List.isEmpty_iff] at h
      subst h
      intro a b hab _ _
      simp only [SOp.toOps, runB]
      exact hab
    | cons o rest =>
      cases o with
      | leaf l =>
        simp only [checkLat] at h
        split at h
        · rename_i l' tgt'
          simp only [Bool.and_eq_true, decide_eq_true_eq] at h
          obtain ⟨rfl, ht⟩ := h
          simp only [SOp.toOps]
          exact cons_noLaterW C R
            (fun a b hab _ => run_mono C R _ g g (Finset.Subset.refl _) a b hab)
            (ih _ _ _ _ ht C R g hg)
        · simp at h
      | loop K body c =>
        simp only [checkLat] at h
        split at h
        · rename_i K' body' c' tgt'
          simp only [Bool.and_eq_true, decide_eq_true_eq] at h
          obtain ⟨⟨⟨rfl, rfl⟩, hb⟩, ht⟩ := h
          simp only [SOp.toOps, SOp.toOp]
          refine cons_noLaterW C R (fun a b hab hrun => ?_) (ih _ _ _ _ ht C R g hg)
          have hbs := run_running hrun
          have has : a.stopped = false := by rw [hab.2.2.1, hbs]
          simp only [run, hbs, has, Bool.false_eq_true, if_false] at hrun ⊢
          exact loopT_noLater c.toCond g _ _
            (fun g' hg' a' b' hab' h' =>
              noLaterW_empty (ih _ _ _ _ hb C R g'
                (hg'.trans (Finset.union_subset_union hg (Finset.Subset.refl _)))) a' b' hab' h')
            K true a b hab hrun
        · simp at h
      | switch G cs d =>
        simp only [checkLat] at h
        split at h
        · rename_i G' cs' d' tgt'
          simp only [Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at h
          obtain ⟨⟨⟨⟨rfl, hv⟩, hcs⟩, hd⟩, ht⟩ := h
          simp only [SOp.toOps, SOp.toOp]
          refine cons_noLaterW C R (fun a b hab hrun => ?_) (ih _ _ _ _ ht C R g hg)
          have hbs := run_running hrun
          have has : a.stopped = false := by rw [hab.2.2.1, hbs]
          have hgG : g ∪ G.toFinset ⊆ E ∪ G.toFinset :=
            Finset.union_subset_union hg (Finset.Subset.refl _)
          simp only [run, hbs, has, Bool.false_eq_true, if_false] at hrun ⊢
          exact cases_noLater C R G _ _ (noLaterW_empty (ih _ _ _ _ hd C R _ hgG)) cs cs' hv
            (fun p hp => noLaterW_empty (ih _ _ _ _ (hcs p hp) C R _ hgG)) a b hab hrun
        · simp at h
      | ite c A B =>
        simp only [checkLat, Bool.or_eq_true, Bool.and_eq_true] at h
        rcases h with (⟨hf, hr⟩ | ⟨hf, hr⟩) | hany
        · simp only [SOp.toOps]
          exact fold_noLater C R true hf (by simpa using ih _ _ _ _ hr C R g hg)
        · simp only [SOp.toOps]
          exact fold_noLater C R false hf (by simpa using ih _ _ _ _ hr C R g hg)
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
                exact ite_stepT C R hH hM (fun g' hg' => ih _ _ _ _ hA C R g' hg')
                  (fun g' hg' => ih _ _ _ _ hB C R g' hg')
                  (fun g' hg' => ih _ _ _ _ hR C R g' hg') g hg
          · simp at hm

/-! ## Leaf moves only

In the block model a hoisted or merged branch can add latency
(`hoist_block_can_delay` in Block.lean). `checkLatLeaf` is `checkLat` with
one more condition: every hoisted or merged op is a leaf. It has no
soundness theorem for the block model yet. A `true` answer says that the
M0 derivation of this output moves leaves only. -/

def isLeaf : SOp → Bool
  | .leaf _ => true
  | _ => false

/-- `hoistAllT` for leaves only. -/
def hoistAllL (E : Finset Bit) (c : SExpr) :
    List SOp → List SOp → List SOp → Option (List SOp × List SOp)
  | [], A, B => some (A, B)
  | h :: H, A, B =>
    if isLeaf h ∧ Disjoint c.bits (writesO h) ∧ Disjoint E (writesO h) then
      match takeOut h A, takeOut h B with
      | some (pA, A1), some (pB, B1) => hoistAllL E c H (pA ++ A1) (pB ++ B1)
      | _, _ => none
    else none

/-- `mergeRevT` for leaves only. -/
def mergeRevL (E : Finset Bit) (c : SExpr) :
    List SOp → List SOp → List SOp → Option (List SOp × List SOp)
  | [], A, B => some (A, B)
  | m :: R, A, B =>
    match takeOutLast m A, takeOutLast m B with
    | some (A1, sA), some (B1, sB) =>
      if isLeaf m ∧ (∀ y ∈ sA, Disjoint E (writesO y)) ∧ (∀ y ∈ sB, Disjoint E (writesO y)) then
        mergeRevL E c R (A1 ++ sA) (B1 ++ sB)
      else none
    | _, _ => none

/-- `checkLat` with leaf moves only. -/
def checkLatLeaf : ℕ → Finset Bit → Finset Bit → List SOp → List SOp → Bool
  | 0, _, _, _, _ => false
  | _ + 1, _, _, [], tgt => tgt.isEmpty
  | f + 1, W, E, o :: rest, tgt =>
    match o with
    | .ite c A B =>
      (foldsTo W c true && checkLatLeaf f W E (A ++ rest) tgt) ||
      (foldsTo W c false && checkLatLeaf f W E (B ++ rest) tgt) ||
      (List.range tgt.length).any fun j =>
        match tgt[j]? with
        | some (.ite c' A' B') =>
          decide (c = c') &&
          match hoistAllL E c (tgt.take j) A B with
          | none => false
          | some (A1, B1) =>
            (List.range (tgt.length - j)).any fun m =>
              match mergeRevL E c ((tgt.drop (j + 1)).take m).reverse A1 B1 with
              | none => false
              | some (A2, B2) =>
                checkLatLeaf f (W \ writesL (tgt.take j)) (E ∪ c.bits) A2 A' &&
                checkLatLeaf f (W \ writesL (tgt.take j)) (E ∪ c.bits) B2 B' &&
                checkLatLeaf f (W \ writesO (.ite c A B)) E rest ((tgt.drop (j + 1)).drop m)
        | _ => false
    | .leaf l =>
      match tgt with
      | .leaf l' :: tgt' => decide (l = l') && checkLatLeaf f (W \ writesO (.leaf l)) E rest tgt'
      | _ => false
    | .loop K body c =>
      match tgt with
      | .loop K' body' c' :: tgt' =>
        decide (K = K') && decide (c = c') && checkLatLeaf f ∅ (E ∪ c.bits) body body' &&
          checkLatLeaf f (W \ writesO (.loop K body c)) E rest tgt'
      | _ => false
    | .switch G cs d =>
      match tgt with
      | .switch G' cs' d' :: tgt' =>
        decide (G = G') && decide (cs.map Prod.fst = cs'.map Prod.fst) &&
          ((cs.zip cs').all fun p => checkLatLeaf f ∅ (E ∪ G.toFinset) p.1.2 p.2.2) &&
          checkLatLeaf f ∅ (E ∪ G.toFinset) d d' &&
          checkLatLeaf f (W \ writesO (.switch G cs d)) E rest tgt'
      | _ => false

end Qlin.TV
