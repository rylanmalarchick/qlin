import Qlin.Check
import Qlin.Latency
import Qlin.BlockLeaf

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
two more conditions: every hoisted or merged op is a leaf, and a merged
leaf writes no enclosing gate bit and no condition bit (the side condition
of `merge_block_leaf`). `checkLatLeaf_soundK` below: a `true` answer
implies that the target is no later than the source in the block model. -/

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
      if isLeaf m ∧ Disjoint (E ∪ c.bits) (writesO m) ∧ (∀ y ∈ sA, Disjoint E (writesO y)) ∧
          (∀ y ∈ sB, Disjoint E (writesO y)) then
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

/-! ## Soundness of the leaf checker in the block model -/

/-- `Q` is no later than `P` in the block model under the gate bits `g`,
from start states whose bits of `W` are 0, when the run of `P` does not
stop. -/
def NoLaterWK (C : BCost) (R : Record) (W g : Finset Bit) (P Q : List Op) : Prop :=
  ∀ a b : BState, a.Le b → (∀ z ∈ W, b.st.vals z = false) →
    (runKB C R P g b).st.stopped = false → (runKB C R Q g a).Le (runKB C R P g b)

theorem noLaterWK_empty {C : BCost} {R : Record} {g : Finset Bit} {P Q : List Op}
    (h : NoLaterWK C R ∅ g P Q) : NoLaterAtK C R g P Q :=
  fun a b hab hrun => h a b hab (fun z hz => absurd hz (Finset.notMem_empty z)) hrun

theorem isLeaf_eq {h : SOp} (hl : isLeaf h = true) : ∃ l, h = .leaf l := by
  cases h with
  | leaf l => exact ⟨l, rfl⟩
  | _ => simp [isLeaf] at hl

theorem hoistAllL_steps (E : Finset Bit) (c : SExpr) : ∀ (H A B A' B' : List SOp),
    hoistAllL E c H A B = some (A', B') →
    M0StepsK E [.ite c.toCond (SOp.toOps A) (SOp.toOps B)]
      (SOp.toOps H ++ [.ite c.toCond (SOp.toOps A') (SOp.toOps B')]) := by
  intro H
  induction H with
  | nil =>
    intro A B A' B' h
    simp only [hoistAllL, Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    simpa [SOp.toOps] using M0StepsK.refl E [.ite c.toCond (SOp.toOps A) (SOp.toOps B)]
  | cons x H ih =>
    intro A B A' B' h
    unfold hoistAllL at h
    split_ifs at h with hc
    split at h
    · rename_i pA A1 pB B1 hA hB
      obtain ⟨rfl, hdA⟩ := takeOut_spec x _ _ _ hA
      obtain ⟨rfl, hdB⟩ := takeOut_spec x _ _ _ hB
      obtain ⟨l, rfl⟩ := isLeaf_eq hc.1
      have step := M0StepsK.hoist E c.toCond l.code l.fp (SOp.toOps pA) (SOp.toOps A1)
        (SOp.toOps pB) (SOp.toOps B1) (toOps_disj (.leaf l) pA hdA)
        (toOps_disj (.leaf l) pB hdB) hc.2.1 hc.2.2
      have rest := M0StepsK.frame [SOp.toOp (.leaf l)] [] (ih _ _ _ _ h)
      simp only [SOp.toOps_append, SOp.toOps, SOp.toOp, List.append_nil, List.cons_append,
        List.nil_append] at step rest ⊢
      exact step.trans rest
    · simp at h

theorem mergeRevL_steps (E : Finset Bit) (c : SExpr) : ∀ (R A B A' B' : List SOp),
    mergeRevL E c R A B = some (A', B') →
    M0StepsK E [.ite c.toCond (SOp.toOps A) (SOp.toOps B)]
      (.ite c.toCond (SOp.toOps A') (SOp.toOps B') :: SOp.toOps R.reverse) := by
  intro R
  induction R with
  | nil =>
    intro A B A' B' h
    simp only [mergeRevL, Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    simpa [SOp.toOps] using M0StepsK.refl E [.ite c.toCond (SOp.toOps A) (SOp.toOps B)]
  | cons x R ih =>
    intro A B A' B' h
    unfold mergeRevL at h
    split at h
    · rename_i A1 sA B1 sB hA hB
      split_ifs at h with henc
      obtain ⟨rfl, hdA⟩ := takeOutLast_spec x _ _ _ hA
      obtain ⟨rfl, hdB⟩ := takeOutLast_spec x _ _ _ hB
      obtain ⟨l, rfl⟩ := isLeaf_eq henc.1
      have step := M0StepsK.merge E c.toCond l.code l.fp (SOp.toOps A1) (SOp.toOps sA)
        (SOp.toOps B1) (SOp.toOps sB) (toOps_disj (.leaf l) sA hdA)
        (toOps_disj (.leaf l) sB hdB) (toOps_enc E sA henc.2.2.1)
        (toOps_enc E sB henc.2.2.2) henc.2.1
      have rest := M0StepsK.frame [] [SOp.toOp (.leaf l)] (ih _ _ _ _ h)
      simp only [SOp.toOps_append, SOp.toOps, SOp.toOp, List.reverse_cons, List.cons_append,
        List.nil_append] at step rest ⊢
      exact step.trans rest
    · simp at h

/-- The M0 steps of one hoist-and-merge step of the leaf checker. -/
theorem ite_chainK {E : Finset Bit} {c : SExpr} {A B H M A1 B1 A2 B2 : List SOp}
    (hH : hoistAllL E c H A B = some (A1, B1))
    (hM : mergeRevL E c M.reverse A1 B1 = some (A2, B2)) :
    M0StepsK E [SOp.toOp (.ite c A B)]
      (SOp.toOps H ++ (.ite c.toCond (SOp.toOps A2) (SOp.toOps B2) :: SOp.toOps M)) := by
  have h1 := hoistAllL_steps E c H A B A1 B1 hH
  have h2 := M0StepsK.frame (SOp.toOps H) [] (mergeRevL_steps E c M.reverse A1 B1 A2 B2 hM)
  rw [List.reverse_reverse] at h2
  simp only [List.append_nil] at h2
  simp only [SOp.toOp]
  exact h1.trans h2

theorem fps_cons_mono {o o' : Op} {P Q : List Op} (h1 : (Op.fp o').qubits ⊆ (Op.fp o).qubits)
    (h2 : (Op.fps Q).qubits ⊆ (Op.fps P).qubits) :
    (Op.fps (o' :: Q)).qubits ⊆ (Op.fps (o :: P)).qubits := by
  simp only [Op.fps, Footprint.union_qubits]
  exact Finset.union_subset_union h1 h2

theorem fold_fps (c : SExpr) (A B rest : List SOp) (v : Bool) :
    (Op.fps (SOp.toOps ((if v then A else B) ++ rest))).qubits ⊆
      (Op.fps (SOp.toOps (.ite c A B :: rest))).qubits := by
  intro q hq
  cases v <;>
  · simp only [SOp.toOps_append, fps_append_qubits, SOp.toOps, SOp.toOp, Op.fps, Op.fp,
      Footprint.union_qubits, Finset.mem_union, if_true, if_false, Bool.false_eq_true]
      at hq ⊢
    tauto

theorem toCases_length (G : List Bit) : ∀ cs : List (List Bool × List SOp),
    (SOp.toCases G cs).length = cs.length
  | [] => by simp [SOp.toCases]
  | (v, blk) :: cs => by simp [SOp.toCases, toCases_length G cs]

theorem armIdx_toCases (G : List Bit) (G' : Finset Bit) (vals : Assign) :
    ∀ (cs cs' : List (List Bool × List SOp)), cs.map Prod.fst = cs'.map Prod.fst →
      armIdx G' vals (SOp.toCases G cs') = armIdx G' vals (SOp.toCases G cs)
  | [], [], _ => rfl
  | [], _ :: _, h => by simp at h
  | _ :: _, [], h => by simp at h
  | (v, blk) :: cs, (v', blk') :: cs', h => by
    simp only [List.map_cons, List.cons.injEq] at h
    obtain ⟨rfl, h⟩ := h
    simp only [SOp.toCases, armIdx, armIdx_toCases G G' vals cs cs' h]

theorem cases_fps_sub (G : List Bit) : ∀ (cs cs' : List (List Bool × List SOp)),
    cs.map Prod.fst = cs'.map Prod.fst →
    (∀ p ∈ cs.zip cs', (Op.fps (SOp.toOps p.2.2)).qubits ⊆ (Op.fps (SOp.toOps p.1.2)).qubits) →
    (Op.fpsCases (SOp.toCases G cs')).qubits ⊆ (Op.fpsCases (SOp.toCases G cs)).qubits
  | [], [], _, _ => Finset.Subset.refl _
  | [], _ :: _, h, _ => by simp at h
  | _ :: _, [], h, _ => by simp at h
  | (v, blk) :: cs, (v', blk') :: cs', h, hb => by
    simp only [List.map_cons, List.cons.injEq] at h
    have h1 := hb ((v, blk), (v', blk')) (by simp)
    have h2 := cases_fps_sub G cs cs' h.2 (fun p hp => hb p (by simp [hp]))
    intro q hq
    have i1 : q ∈ (Op.fps (SOp.toOps blk')).qubits → q ∈ (Op.fps (SOp.toOps blk)).qubits :=
      fun h' => h1 h'
    have i2 : q ∈ (Op.fpsCases (SOp.toCases G cs')).qubits →
        q ∈ (Op.fpsCases (SOp.toCases G cs)).qubits := fun h' => h2 h'
    simp only [SOp.toCases, Op.fpsCases, Footprint.union_qubits, Finset.mem_union] at hq ⊢
    tauto

theorem cases_noLaterK (C : BCost) (R : Record) (G : List Bit) (G' gates : Finset Bit)
    {d d' : List Op} (hd : NoLaterAtK C R gates d d') :
    ∀ (cs cs' : List (List Bool × List SOp)), cs.map Prod.fst = cs'.map Prod.fst →
      (∀ p ∈ cs.zip cs', NoLaterAtK C R gates (SOp.toOps p.1.2) (SOp.toOps p.2.2)) →
      ∀ a b : BState, a.Le b →
        (runKCases C R G' (SOp.toCases G cs) d gates b).st.stopped = false →
        (runKCases C R G' (SOp.toCases G cs') d' gates a).Le
          (runKCases C R G' (SOp.toCases G cs) d gates b) := by
  intro cs
  induction cs with
  | nil =>
    intro cs' hv _ a b hab h
    cases cs' with
    | nil =>
      simp only [SOp.toCases, runKCases] at h ⊢
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
      simp only [SOp.toCases, runKCases, hab.1.1] at h ⊢
      by_cases hg : agrees G' b.st.vals (assignOf G v)
      · rw [if_pos hg] at h
        rw [if_pos hg, if_pos hg]
        exact hb ((v, blk), (v, blk')) (by simp) a b hab h
      · rw [if_neg hg] at h
        rw [if_neg hg, if_neg hg]
        exact ih cs' hv (fun q hq => hb q (by simp [hq])) a b hab h

theorem cons_noLaterWK (C : BCost) (R : Record) {W g : Finset Bit} {o o' : Op}
    {rest rest' : List Op}
    (hhead : ∀ a b : BState, a.Le b → (runK C R o g b).st.stopped = false →
      (runK C R o' g a).Le (runK C R o g b))
    (htail : NoLaterWK C R (W \ (Op.fp o).writes) g rest rest') :
    NoLaterWK C R W g (o :: rest) (o' :: rest') := by
  intro a b hab hW hrun
  rw [runKB_cons] at hrun ⊢
  rw [runKB_cons]
  have h1 := hhead a b hab (runKB_runningK hrun)
  refine htail _ _ h1 (fun z hz => ?_) hrun
  rw [Finset.mem_sdiff] at hz
  rw [(runK_frm C R o g b).vals z hz.2]
  exact hW z hz.1

theorem le_stall (C : BCost) (F : Footprint) (bits g : Finset Bit) (n : ℕ) (s : BState) :
    s.Le (stall C F bits g n s) := by
  refine ⟨⟨rfl, rfl, rfl, fun q => ?_, fun z => optLe_refl' _⟩, ?_⟩
  · show s.st.ready q ≤ (if q ∈ F.qubits then max (s.st.ready q) _ else s.st.ready q)
    split_ifs
    · exact le_max_left _ _
    · exact le_rfl
  · show s.free ≤ max (max (gateTime C.base s.st bits) (gateTime C.base s.st g)) s.free + C.tb * n
    exact (le_max_right _ _).trans le_self_add

theorem fold_noLaterK (C : BCost) (R : Record) {W g : Finset Bit} {c : SExpr}
    {A B rest : List SOp} {tgt : List Op} (v : Bool) (hf : foldsTo W c v = true)
    (h : NoLaterWK C R W g (SOp.toOps ((if v then A else B) ++ rest)) tgt) :
    NoLaterWK C R W g (SOp.toOp (.ite c A B) :: SOp.toOps rest) tgt := by
  intro a b hab hW hrun
  have hc : c.toCond.eval b.st.vals = v := foldsTo_sound hf b.st.vals hW
  rw [runKB_cons] at hrun ⊢
  have hb : b.st.stopped = false := runK_runningK (runKB_runningK hrun)
  have e : runK C R (SOp.toOp (.ite c A B)) g b =
      runKB C R (SOp.toOps (if v then A else B)) (g ∪ c.toCond.bits)
        (stall C (Op.fp (SOp.toOp (.ite c A B))) c.toCond.bits g 1 b) := by
    simp only [SOp.toOp]
    rw [runK_ite C R _ _ _ g b hb, hc]
    cases v <;> simp
  rw [e] at hrun ⊢
  have hs : (runKB C R (SOp.toOps (if v then A else B)) g b).Le
      (runKB C R (SOp.toOps (if v then A else B)) (g ∪ c.toCond.bits)
        (stall C (Op.fp (SOp.toOp (.ite c A B))) c.toCond.bits g 1 b)) :=
    runKB_mono C R _ _ _ Finset.subset_union_left b _ (le_stall C _ _ g 1 b)
  have hr := runKB_mono C R (SOp.toOps rest) g g (Finset.Subset.refl _) _ _ hs
  have hrun' : (runKB C R (SOp.toOps ((if v then A else B) ++ rest)) g b).st.stopped = false := by
    rw [SOp.toOps_append, runKB_appendK, hr.1.2.2.1]
    exact hrun
  have key := h a b hab hW hrun'
  rw [SOp.toOps_append, runKB_appendK] at key
  exact key.trans hr

theorem ite_step_fps {E : Finset Bit} {c : SExpr}
    {A B rest H A' B' M T' A1 B1 A2 B2 : List SOp}
    (hH : hoistAllL E c H A B = some (A1, B1))
    (hM : mergeRevL E c M.reverse A1 B1 = some (A2, B2))
    (hAq : (Op.fps (SOp.toOps A')).qubits ⊆ (Op.fps (SOp.toOps A2)).qubits)
    (hBq : (Op.fps (SOp.toOps B')).qubits ⊆ (Op.fps (SOp.toOps B2)).qubits)
    (hRq : (Op.fps (SOp.toOps T')).qubits ⊆ (Op.fps (SOp.toOps rest)).qubits) :
    (Op.fps (SOp.toOps (H ++ .ite c A' B' :: (M ++ T')))).qubits ⊆
      (Op.fps (SOp.toOps (.ite c A B :: rest))).qubits := by
  have hch := m0StepsK_fps (ite_chainK hH hM)
  have hFq := (fp_ite_sub_left c.toCond (SOp.toOps B') hAq).trans
    (fp_ite_sub_right c.toCond (SOp.toOps A2) hBq)
  intro q hq
  have i1 : q ∈ (Op.fps (SOp.toOps H ++ (.ite c.toCond (SOp.toOps A2) (SOp.toOps B2) ::
      SOp.toOps M))).qubits → q ∈ (Op.fps [SOp.toOp (.ite c A B)]).qubits := fun h' => hch h'
  have i2 : q ∈ (Op.fp (.ite c.toCond (SOp.toOps A') (SOp.toOps B'))).qubits →
      q ∈ (Op.fp (.ite c.toCond (SOp.toOps A2) (SOp.toOps B2))).qubits := fun h' => hFq h'
  have i3 : q ∈ (Op.fps (SOp.toOps T')).qubits → q ∈ (Op.fps (SOp.toOps rest)).qubits :=
    fun h' => hRq h'
  simp only [SOp.toOps_append, SOp.toOps, SOp.toOp, fps_append_qubits, Op.fps,
    Footprint.union_qubits, Finset.mem_union, Footprint.empty, Finset.notMem_empty, or_false]
    at hq i1 ⊢
  tauto

/-- One hoist-and-merge step of the leaf checker, in the block model. -/
theorem ite_stepK (C : BCost) (R : Record) {W E : Finset Bit} {c : SExpr}
    {A B rest H A' B' M T' A1 B1 A2 B2 : List SOp}
    (hH : hoistAllL E c H A B = some (A1, B1))
    (hM : mergeRevL E c M.reverse A1 B1 = some (A2, B2))
    (hA : ∀ g, g ⊆ E ∪ c.bits → NoLaterWK C R (W \ writesL H) g (SOp.toOps A2) (SOp.toOps A'))
    (hB : ∀ g, g ⊆ E ∪ c.bits → NoLaterWK C R (W \ writesL H) g (SOp.toOps B2) (SOp.toOps B'))
    (hAq : (Op.fps (SOp.toOps A')).qubits ⊆ (Op.fps (SOp.toOps A2)).qubits)
    (hBq : (Op.fps (SOp.toOps B')).qubits ⊆ (Op.fps (SOp.toOps B2)).qubits)
    (hR : ∀ g, g ⊆ E → NoLaterWK C R (W \ writesO (.ite c A B)) g (SOp.toOps rest)
      (SOp.toOps T')) :
    ∀ g, g ⊆ E → NoLaterWK C R W g (SOp.toOps (.ite c A B :: rest))
      (SOp.toOps (H ++ .ite c A' B' :: (M ++ T'))) := by
  intro g hg a b hab hW hrun
  have e_src : runKB C R (SOp.toOps (.ite c A B :: rest)) g b =
      runKB C R (SOp.toOps rest) g (runK C R (SOp.toOp (.ite c A B)) g b) := by
    simp only [SOp.toOps, runKB_cons]
  rw [e_src] at hrun ⊢
  have hs : (runKB C R [SOp.toOp (.ite c A B)] g b).st.stopped = false := by
    rw [runKB_single]; exact runKB_runningK hrun
  have hmid := m0StepsK_latency C R (ite_chainK hH hM) g hg b b (BState.Le.refl b) hs
  rw [runKB_single] at hs
  rw [runKB_single, runKB_appendK, runKB_cons] at hmid
  have hH1 := runKB_mono C R (SOp.toOps H) g g (Finset.Subset.refl _) a b hab
  have hW1 : ∀ z ∈ W \ writesL H, (runKB C R (SOp.toOps H) g b).st.vals z = false := by
    intro z hz
    rw [Finset.mem_sdiff] at hz
    rw [(runKB_frm C R _ g b).vals z hz.2]
    exact hW z hz.1
  have hmid_run : (runKB C R (SOp.toOps M) g (runK C R (.ite c.toCond (SOp.toOps A2)
      (SOp.toOps B2)) g (runKB C R (SOp.toOps H) g b))).st.stopped = false := by
    rw [hmid.1.2.2.1]; exact hs
  have hite_run := runKB_runningK hmid_run
  have hb1 : (runKB C R (SOp.toOps H) g b).st.stopped = false := runK_runningK hite_run
  have ha1 : (runKB C R (SOp.toOps H) g a).st.stopped = false := by rw [hH1.1.2.2.1, hb1]
  have hgc : g ∪ c.toCond.bits ⊆ E ∪ c.bits :=
    Finset.union_subset_union hg (Finset.Subset.refl _)
  have hFq := (fp_ite_sub_left c.toCond (SOp.toOps B') hAq).trans
    (fp_ite_sub_right c.toCond (SOp.toOps A2) hBq)
  have hst := (stall_mono C (Op.fp (.ite c.toCond (SOp.toOps A') (SOp.toOps B'))) c.toCond.bits
    (Finset.Subset.refl g) 1 hH1).trans (stall_sub_le C _ _ c.toCond.bits g 1 _ hFq)
  have harms : (runK C R (.ite c.toCond (SOp.toOps A') (SOp.toOps B')) g
      (runKB C R (SOp.toOps H) g a)).Le
      (runK C R (.ite c.toCond (SOp.toOps A2) (SOp.toOps B2)) g
        (runKB C R (SOp.toOps H) g b)) := by
    rw [runK_ite C R _ (SOp.toOps A2) (SOp.toOps B2) g _ hb1] at hite_run ⊢
    rw [runK_ite C R _ (SOp.toOps A') (SOp.toOps B') g _ ha1, hH1.1.1]
    by_cases hce : c.toCond.eval (runKB C R (SOp.toOps H) g b).st.vals = true
    · simp only [if_pos hce] at hite_run ⊢
      exact hA _ hgc _ _ hst hW1 hite_run
    · simp only [if_neg hce] at hite_run ⊢
      exact hB _ hgc _ _ hst hW1 hite_run
  have hhead := (runKB_mono C R (SOp.toOps M) g g (Finset.Subset.refl _) _ _ harms).trans hmid
  have hW2 : ∀ z ∈ W \ writesO (.ite c A B),
      (runK C R (SOp.toOp (.ite c A B)) g b).st.vals z = false := by
    intro z hz
    rw [Finset.mem_sdiff] at hz
    rw [(runK_frm C R _ g b).vals z hz.2]
    exact hW z hz.1
  have key := hR g hg _ _ hhead hW2 hrun
  have e_tgt : runKB C R (SOp.toOps (H ++ .ite c A' B' :: (M ++ T'))) g a =
      runKB C R (SOp.toOps T') g (runKB C R (SOp.toOps M) g
        (runK C R (.ite c.toCond (SOp.toOps A') (SOp.toOps B')) g
          (runKB C R (SOp.toOps H) g a))) := by
    simp only [SOp.toOps_append, SOp.toOps, SOp.toOp, runKB_appendK, runKB_cons]
  rw [e_tgt]
  exact key

/-- A `true` answer of the leaf checker implies that the target is no later
than the source in the block model, and that it uses no more qubits. -/
theorem checkLatLeaf_soundK : ∀ (f : ℕ) (W E : Finset Bit) (src tgt : List SOp),
    checkLatLeaf f W E src tgt = true →
    (Op.fps (SOp.toOps tgt)).qubits ⊆ (Op.fps (SOp.toOps src)).qubits ∧
    ∀ (C : BCost) (R : Record) (g : Finset Bit), g ⊆ E →
      NoLaterWK C R W g (SOp.toOps src) (SOp.toOps tgt) := by
  intro f
  induction f with
  | zero => intro W E src tgt h; simp [checkLatLeaf] at h
  | succ f ih =>
    intro W E src tgt h
    cases src with
    | nil =>
      simp only [checkLatLeaf, List.isEmpty_iff] at h
      subst h
      refine ⟨Finset.Subset.refl _, fun C R g _ a b hab _ _ => ?_⟩
      simp only [SOp.toOps, runKB]
      exact hab
    | cons o rest =>
      cases o with
      | leaf l =>
        simp only [checkLatLeaf] at h
        split at h
        · rename_i l' tgt'
          simp only [Bool.and_eq_true, decide_eq_true_eq] at h
          obtain ⟨rfl, ht⟩ := h
          obtain ⟨htq, htK⟩ := ih _ _ _ _ ht
          refine ⟨?_, fun C R g hg => ?_⟩
          · simp only [SOp.toOps]
            exact fps_cons_mono (Finset.Subset.refl _) htq
          · simp only [SOp.toOps]
            exact cons_noLaterWK C R
              (fun a b hab _ => runK_mono C R _ g g (Finset.Subset.refl _) a b hab)
              (htK C R g hg)
        · simp at h
      | loop K body c =>
        simp only [checkLatLeaf] at h
        split at h
        · rename_i K' body' c' tgt'
          simp only [Bool.and_eq_true, decide_eq_true_eq] at h
          obtain ⟨⟨⟨rfl, rfl⟩, hb⟩, ht⟩ := h
          obtain ⟨hbq, hbK⟩ := ih _ _ _ _ hb
          obtain ⟨htq, htK⟩ := ih _ _ _ _ ht
          have hFq := fp_loop_sub K c.toCond hbq
          refine ⟨?_, fun C R g hg => ?_⟩
          · simp only [SOp.toOps, SOp.toOp]
            exact fps_cons_mono hFq htq
          · simp only [SOp.toOps, SOp.toOp]
            refine cons_noLaterWK C R (fun a b hab hrun => ?_) (htK C R g hg)
            have hbs := runK_runningK hrun
            have has : a.st.stopped = false := by rw [hab.1.2.2.1, hbs]
            simp only [runK, hbs, has, Bool.false_eq_true, if_false] at hrun ⊢
            exact loopK_noLaterK c.toCond g _ _ _ _
              (fun g' hg' a' b' hab' h' => noLaterWK_empty (hbK C R g'
                (hg'.trans (Finset.union_subset_union hg (Finset.Subset.refl _)))) a' b' hab' h')
              (fun a' b' h' => (stall_mono C _ c.toCond.bits (Finset.Subset.refl g) 1 h').trans
                (stall_sub_le C _ _ c.toCond.bits g 1 b' hFq))
              (fun _ => rfl) K true a b hab hrun
        · simp at h
      | switch G cs d =>
        simp only [checkLatLeaf] at h
        split at h
        · rename_i G' cs' d' tgt'
          simp only [Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at h
          obtain ⟨⟨⟨⟨rfl, hv⟩, hcs⟩, hd⟩, ht⟩ := h
          obtain ⟨hdq, hdK⟩ := ih _ _ _ _ hd
          obtain ⟨htq, htK⟩ := ih _ _ _ _ ht
          have hcq := cases_fps_sub G cs cs' hv (fun p hp => (ih _ _ _ _ (hcs p hp)).1)
          have hFq : (Op.fp (.switch G.toFinset (SOp.toCases G cs') (SOp.toOps d'))).qubits ⊆
              (Op.fp (.switch G.toFinset (SOp.toCases G cs) (SOp.toOps d))).qubits := by
            intro q hq
            have i1 : q ∈ (Op.fpsCases (SOp.toCases G cs')).qubits →
                q ∈ (Op.fpsCases (SOp.toCases G cs)).qubits := fun h' => hcq h'
            have i2 : q ∈ (Op.fps (SOp.toOps d')).qubits → q ∈ (Op.fps (SOp.toOps d)).qubits :=
              fun h' => hdq h'
            simp only [Op.fp, Footprint.union_qubits, Finset.mem_union] at hq ⊢
            tauto
          have hlen : cs'.length = cs.length := by simpa using (congrArg List.length hv).symm
          refine ⟨?_, fun C R g hg => ?_⟩
          · simp only [SOp.toOps, SOp.toOp]
            exact fps_cons_mono hFq htq
          · simp only [SOp.toOps, SOp.toOp]
            refine cons_noLaterWK C R (fun a b hab hrun => ?_) (htK C R g hg)
            have hbs := runK_runningK hrun
            have has : a.st.stopped = false := by rw [hab.1.2.2.1, hbs]
            have hgG : g ∪ G.toFinset ⊆ E ∪ G.toFinset :=
              Finset.union_subset_union hg (Finset.Subset.refl _)
            have hn : C.dec G.toFinset.card (SOp.toCases G cs').length
                  (armIdx G.toFinset a.st.vals (SOp.toCases G cs')) =
                C.dec G.toFinset.card (SOp.toCases G cs).length
                  (armIdx G.toFinset b.st.vals (SOp.toCases G cs)) := by
              rw [armIdx_toCases G G.toFinset a.st.vals cs cs' hv, hab.1.1, toCases_length,
                toCases_length, hlen]
            simp only [runK, hbs, has, Bool.false_eq_true, if_false] at hrun ⊢
            rw [hn]
            exact cases_noLaterK C R G _ _ (noLaterWK_empty (hdK C R _ hgG)) cs cs' hv
              (fun p hp => noLaterWK_empty ((ih _ _ _ _ (hcs p hp)).2 C R _ hgG)) _ _
              ((stall_mono C _ G.toFinset (Finset.Subset.refl g) _ hab).trans
                (stall_sub_le C _ _ G.toFinset g _ b hFq)) hrun
        · simp at h
      | ite c A B =>
        simp only [checkLatLeaf, Bool.or_eq_true, Bool.and_eq_true] at h
        rcases h with (⟨hf, hr⟩ | ⟨hf, hr⟩) | hany
        · obtain ⟨hq, hK⟩ := ih _ _ _ _ hr
          refine ⟨hq.trans (by simpa using fold_fps c A B rest true), fun C R g hg => ?_⟩
          simp only [SOp.toOps]
          exact fold_noLaterK C R true hf (by simpa using hK C R g hg)
        · obtain ⟨hq, hK⟩ := ih _ _ _ _ hr
          refine ⟨hq.trans (by simpa using fold_fps c A B rest false), fun C R g hg => ?_⟩
          simp only [SOp.toOps]
          exact fold_noLaterK C R false hf (by simpa using hK C R g hg)
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
                obtain ⟨hAq, hAK⟩ := ih _ _ _ _ hA
                obtain ⟨hBq, hBK⟩ := ih _ _ _ _ hB
                obtain ⟨hRq, hRK⟩ := ih _ _ _ _ hR
                exact ⟨ite_step_fps hH hM hAq hBq hRq, fun C R g hg =>
                  ite_stepK C R hH hM (fun g' hg' => hAK C R g' hg')
                    (fun g' hg' => hBK C R g' hg') hAq hBq (fun g' hg' => hRK C R g' hg') g hg⟩
          · simp at hm

end Qlin.TV
