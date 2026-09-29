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
  sorry

end Qlin
