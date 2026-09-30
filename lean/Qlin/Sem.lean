import Qlin.IR

/-!
# Semantics over an abstract cq-state

A state gives each bit assignment an element of `D`. For a cq channel,
`D` is the cone of unnormalized density operators and `s β` is the
quantum part on the branch where the bits equal `β`. Here `D` is any
additive commutative monoid.

An `Interp` gives each leaf an additive map with two axioms:
- A1 (`local_`): a leaf commutes with `restrict c` when `c` reads no bit
  the leaf writes.
- A2 (`comm`): leaves with disjoint footprints commute.

These two axioms are true for cq channels (hand-checked, not in Lean).
The fact that unwritten bits keep their value (A3 in the plan) follows
from A1 (`Structure.lean`).
-/

namespace Qlin

/-- A cq-state: the quantum part for each bit assignment. -/
abbrev State (D : Type*) := Assign → D

variable {D : Type*} [AddCommMonoid D]

/-- Keep the branches where `c` holds, zero the rest. -/
def restrict (c : Cond) (s : State D) : State D :=
  fun β => if c.eval β then s β else 0

/-- Leaf semantics and the two axioms. -/
structure Interp (D : Type*) [AddCommMonoid D] where
  leaf : ℕ → Footprint → State D →+ State D
  /-- A1: a leaf commutes with a condition on bits it does not write. -/
  local_ : ∀ i f (c : Cond), Disjoint c.bits f.writes →
    ∀ s, leaf i f (restrict c s) = restrict c (leaf i f s)
  /-- A2: leaves with disjoint footprints commute. -/
  comm : ∀ i f j g, Footprint.Disj f g →
    ∀ s, leaf i f (leaf j g s) = leaf j g (leaf i f s)

/-- At most `K` iterations of `f`, exiting when `c` holds after an
iteration. Branches still running after `K` iterations stop there
(the truncated traces of `src/trace.rs`). -/
def loopIter (f : State D → State D) (c : Cond) : ℕ → State D → State D
  | 0, s => s
  | K + 1, s => restrict c (f s) + loopIter f c K (restrict c.not (f s))

mutual
/-- The denotation of an op. -/
def den (I : Interp D) : Op → State D → State D
  | .leaf i f, s => I.leaf i f s
  | .ite c A B, s => denB I A (restrict c s) + denB I B (restrict c.not s)
  | .loop K body c, s => loopIter (fun t => denB I body t) c K s
  | .switch G cases dflt, s => denCases I G cases dflt s
  termination_by o => sizeOf o

/-- The denotation of a block: ops left to right. -/
def denB (I : Interp D) : List Op → State D → State D
  | [], s => s
  | o :: os, s => denB I os (den I o s)
  termination_by l => sizeOf l

/-- A switch: the first case whose value agrees on `G`, else `dflt`. -/
def denCases (I : Interp D) (G : Finset Bit) :
    List (Assign × List Op) → List Op → State D → State D
  | [], dflt, s => denB I dflt s
  | (v, blk) :: cs, dflt, s =>
      denB I blk (restrict (Cond.matches G v) s) +
        denCases I G cs dflt (restrict (Cond.matches G v).not s)
  termination_by cs dflt => sizeOf cs + sizeOf dflt
end

end Qlin
