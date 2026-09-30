import Mathlib

/-!
# qlin IR (the classical-control skeleton)

A Lean copy of the control structure of `src/ir.rs`. Leaves are opaque:
a leaf is an id plus the footprint it declares. The semantics of a leaf
comes from an `Interp` (see `Qlin/Sem.lean`).
-/

namespace Qlin

abbrev Bit := ℕ
abbrev Qubit := ℕ
/-- A value for every classical bit. -/
abbrev Assign := Bit → Bool

/-- Qubits and bits an op touches (`Footprint` in `src/ir.rs`). -/
structure Footprint where
  qubits : Finset Qubit
  reads : Finset Bit
  writes : Finset Bit

instance : Union Footprint :=
  ⟨fun f g => ⟨f.qubits ∪ g.qubits, f.reads ∪ g.reads, f.writes ∪ g.writes⟩⟩

/-- The empty footprint. -/
def Footprint.empty : Footprint := ⟨∅, ∅, ∅⟩

/-- No shared qubit and no bit conflict (write/write, write/read,
read/write). Copied from `Footprint::disjoint` in `src/ir.rs`. -/
def Footprint.Disj (f g : Footprint) : Prop :=
  Disjoint f.qubits g.qubits ∧ Disjoint f.writes g.writes ∧
    Disjoint f.writes g.reads ∧ Disjoint f.reads g.writes

/-- A condition: a Boolean function of the bits in `bits` only. -/
structure Cond where
  eval : Assign → Bool
  bits : Finset Bit
  dep : ∀ β β' : Assign, (∀ b ∈ bits, β b = β' b) → eval β = eval β'

/-- The negated condition. -/
def Cond.not (c : Cond) : Cond :=
  ⟨fun β => !c.eval β, c.bits, fun β β' h => by simp [c.dep β β' h]⟩

/-- `β` agrees with `v` on every bit of `G`. -/
def Cond.matches (G : Finset Bit) (v : Assign) : Cond :=
  ⟨fun β => decide (∀ b ∈ G, β b = v b), G, fun β β' h => by
    simp only [decide_eq_decide]
    exact ⟨fun h' b hb => (h b hb).symm.trans (h' b hb),
      fun h' b hb => (h b hb).trans (h' b hb)⟩⟩

/-- Ops. `ite` is `If`, `loop` is `Loop` (body, exit condition, at most
`K` iterations), `switch G cases dflt` runs the first case whose value
agrees with the bits in `G`, else `dflt` (`Op::Switch`). -/
inductive Op where
  | leaf (id : ℕ) (fp : Footprint)
  | ite (c : Cond) (A B : List Op)
  | loop (K : ℕ) (body : List Op) (c : Cond)
  | switch (G : Finset Bit) (cases : List (Assign × List Op)) (dflt : List Op)

mutual
/-- The footprint of an op, as `Op::footprint` in `src/ir.rs`. -/
def Op.fp : Op → Footprint
  | .leaf _ f => f
  | .ite c A B => ⟨∅, c.bits, ∅⟩ ∪ Op.fps A ∪ Op.fps B
  | .loop _ body c => ⟨∅, c.bits, ∅⟩ ∪ Op.fps body
  | .switch G cases dflt => ⟨∅, G, ∅⟩ ∪ Op.fpsCases cases ∪ Op.fps dflt

/-- The union of the footprints of a block. -/
def Op.fps : List Op → Footprint
  | [] => Footprint.empty
  | o :: os => Op.fp o ∪ Op.fps os

/-- The union of the footprints of the case blocks. -/
def Op.fpsCases : List (Assign × List Op) → Footprint
  | [] => Footprint.empty
  | (_, blk) :: cs => Op.fps blk ∪ Op.fpsCases cs
end

end Qlin
