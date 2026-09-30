import Qlin.Structure

/-!
# R3a: the fast-path dispatch is sound

`src/transform/fastpath.rs` replaces a dispatch group (a run of Ifs
whose condition bits `G` are written before the run and not inside it)
and the rest of the program by one Switch over `G`:
- case `v` runs the arms that `v` selects, then a fast path of the rest,
- the default runs the group and the rest unchanged (the exit edge).

`fastpath_step` shows this Switch equals the group followed by the rest,
for any case set, as long as every case body equals "selected arms, then
rest". Induction over the groups gives the whole construction: the case
body of the next group is again such a Switch.
-/

namespace Qlin

variable {D : Type*} [AddCommMonoid D]

/-- The arm of an If that the bit values `v` select. Other ops stay. -/
def sel (v : Assign) : Op → List Op
  | .ite c A B => if c.eval v then A else B
  | o => [o]

/-- The block that assignment `v` runs in place of the group. -/
def selected (v : Assign) (grp : List Op) : List Op :=
  (grp.map (sel v)).flatten


private theorem restrict_restrict_matches (c : Cond) (G : Finset Bit) (v : Assign)
    (hc : c.bits ⊆ G) (t : State D) :
    restrict c (restrict (Cond.matches G v) t) =
      if c.eval v then restrict (Cond.matches G v) t else 0 := by
  funext β
  unfold restrict
  by_cases hm : (Cond.matches G v).eval β
  · have hagree : c.eval β = c.eval v := by
      apply c.dep
      intro b hb
      simp only [Cond.matches, decide_eq_true_eq] at hm
      exact hm b (hc hb)
    by_cases hv : c.eval v <;> simp [hm, hagree, hv]
  · by_cases hv : c.eval v <;> simp [hm, hv]

private theorem denB_sel (I : Interp D) (G : Finset Bit) (v : Assign) (o : Op)
    (hbits : ∀ c A B, o = Op.ite c A B → c.bits ⊆ G) (t : State D) :
    denB I (sel v o) (restrict (Cond.matches G v) t) =
      den I o (restrict (Cond.matches G v) t) := by
  cases o with
  | ite c A B =>
    have hc := hbits c A B rfl
    have hnc : c.not.bits ⊆ G := hc
    have hnot : c.not.eval v = !c.eval v := rfl
    simp only [sel, den]
    rw [restrict_restrict_matches c G v hc, restrict_restrict_matches c.not G v hnc, hnot]
    by_cases hv : c.eval v <;> simp [hv, denB_zero]
  | leaf i f => simp [sel, denB]
  | loop K body c => simp [sel, denB]
  | switch G' cs dflt => simp [sel, denB]

private theorem denB_selected (I : Interp D) (G : Finset Bit) (v : Assign) :
    ∀ (grp : List Op), (∀ o ∈ grp, ∀ c A B, o = Op.ite c A B → c.bits ⊆ G) →
    Disjoint G (Op.fps grp).writes → ∀ t : State D,
    denB I (selected v grp) (restrict (Cond.matches G v) t) =
      denB I grp (restrict (Cond.matches G v) t)
  | [], _, _, t => by simp [selected, denB]
  | o :: os, hbits, hw, t => by
    rw [Op.fps] at hw
    have hw' : Disjoint G ((Op.fp o).writes ∪ (Op.fps os).writes) := hw
    rw [Finset.disjoint_union_right] at hw'
    have hsel : selected v (o :: os) = sel v o ++ selected v os := by
      simp [selected]
    rw [hsel, denB_append, denB, denB_sel I G v o (hbits o List.mem_cons_self),
      den_restrict I o _ hw'.1]
    exact denB_selected I G v os (fun o' ho' => hbits o' (List.mem_cons_of_mem _ ho'))
      hw'.2 (den I o t)

/-- Fast-path step: a Switch over `G` whose case bodies equal "selected
arms, then rest" and whose default is "group, then rest" equals "group,
then rest". The Ifs read only bits of `G`, and the group writes no bit
of `G`. -/
theorem fastpath_step (I : Interp D) (G : Finset Bit) (grp rest : List Op)
    (cases : List (Assign × List Op))
    (hbits : ∀ o ∈ grp, ∀ c A B, o = Op.ite c A B → c.bits ⊆ G)
    (hw : Disjoint G (Op.fps grp).writes)
    (hcase : ∀ p ∈ cases, ∀ s, denB I p.2 s = denB I (selected p.1 grp ++ rest) s)
    (s : State D) :
    den I (.switch G cases (grp ++ rest)) s = denB I (grp ++ rest) s := by
  simp only [den]
  induction cases generalizing s with
  | nil => simp only [denCases]
  | cons p cs ih =>
    obtain ⟨v, blk⟩ := p
    simp only [denCases]
    rw [ih (fun p hp => hcase p (List.mem_cons_of_mem _ hp)),
      hcase (v, blk) List.mem_cons_self, denB_append I (selected v grp) rest,
      denB_selected I G v grp hbits hw, ← denB_append, ← denB_add, restrict_split]

end Qlin
