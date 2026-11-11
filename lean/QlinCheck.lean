import Qlin.Check
import Qlin.CheckLatency

/-!
# qlincheck: run the translation-validation checkers on exported jobs

Run: `lake env lean --run QlinCheck.lean JOBS.json` (from `lean/`).
`--leaf-moves JOBS.json` reports which M0 jobs `checkLatLeaf` accepts
(block-model latency, `checkLatLeaf_soundK`).

`JOBS.json` comes from `qlin tv-export`. Each job names a source and a
target program. Kind `m0` runs `checkBlock` (semantics) and `checkLat`
(latency, with no enclosing gate bits) from the all-zero bits, and passes
only if both accept. Kind `m0-semantics` runs `checkBlock` alone (for
the planted jobs of bench/tv_planted.json). Kind `fp` runs `checkFP`. A `true` answer is covered
by `checkBlock_sound` and `checkLat_sound`, or by `checkFP_sound`. Parsing is outside the proofs: the trusted part is that
this file reads the JSON into the same programs the Rust code wrote.

JSON: an op is `{"leaf": [kind, qubits, writes, params]}`,
`{"ite": [cond, then, else]}`, `{"loop": [max_iters, body, until]}`, or
`{"switch": [bits, [[values, block], ...], default]}`. A condition is
`{"c": bool}`, `{"v": bit}`, `{"not": e}`, or `{"and"|"or"|"xor": [a, b]}`.
-/

open Lean Qlin Qlin.TV

def natArr (j : Json) : Except String (List ℕ) := do
  let a ← j.getArr?
  a.toList.mapM fun x => x.getNat?

partial def parseExpr (j : Json) : Except String SExpr := do
  if let .ok v := j.getObjValAs? Bool "c" then return .const v
  if let .ok b := j.getObjValAs? Nat "v" then return .var b
  if let .ok e := j.getObjVal? "not" then return .not (← parseExpr e)
  for (k, mk) in [("and", SExpr.and), ("or", SExpr.or), ("xor", SExpr.xor)] do
    if let .ok ab := j.getObjVal? k then
      let a ← ab.getArrVal? 0
      let b ← ab.getArrVal? 1
      return mk (← parseExpr a) (← parseExpr b)
  throw s!"bad condition {j.compress}"

mutual
partial def parseOp (j : Json) : Except String SOp := do
  if let .ok l := j.getObjVal? "leaf" then
    return .leaf ⟨← (← l.getArrVal? 0).getNat?, ← natArr (← l.getArrVal? 1),
      ← natArr (← l.getArrVal? 2), ← natArr (← l.getArrVal? 3)⟩
  if let .ok x := j.getObjVal? "ite" then
    return .ite (← parseExpr (← x.getArrVal? 0)) (← parseBlock (← x.getArrVal? 1))
      (← parseBlock (← x.getArrVal? 2))
  if let .ok x := j.getObjVal? "loop" then
    return .loop (← (← x.getArrVal? 0).getNat?) (← parseBlock (← x.getArrVal? 1))
      (← parseExpr (← x.getArrVal? 2))
  if let .ok x := j.getObjVal? "switch" then
    let cs ← (← x.getArrVal? 1).getArr?
    let cases ← cs.toList.mapM fun c => do
      let vs ← (← c.getArrVal? 0).getArr?
      let vals ← vs.toList.mapM fun v => v.getBool?
      return (vals, ← parseBlock (← c.getArrVal? 1))
    return .switch (← natArr (← x.getArrVal? 0)) cases (← parseBlock (← x.getArrVal? 2))
  throw s!"bad op {j.compress}"

partial def parseBlock (j : Json) : Except String (List SOp) := do
  let a ← j.getArr?
  a.toList.mapM parseOp
end

/-- Recursion bound for the checkers: far above any benchmark's needs. -/
def FUEL : ℕ := 1000000

def runJob (j : Json) : Except String (String × Bool) := do
  let name ← j.getObjValAs? String "name"
  let kind ← j.getObjValAs? String "kind"
  let bits ← j.getObjValAs? Nat "bits"
  let src ← parseBlock (← j.getObjVal? "src")
  let tgt ← parseBlock (← j.getObjVal? "tgt")
  match kind with
  | "m0" =>
    let W := (List.range bits).toFinset
    if !checkBlock FUEL W src tgt then return (name, false)
    if !checkLat FUEL W ∅ src tgt then return (name, false)
    return (name, true)
  | "m0-semantics" => return (name, checkBlock FUEL ((List.range bits).toFinset) src tgt)
  | "fp" => return (name, checkFP FUEL src tgt)
  | k => throw s!"unknown kind {k}"

/-- `--leaf-moves`: for each M0 job, does `checkLatLeaf` accept it (leaf
moves only)? `checkLatLeaf_soundK` covers an accepted job in the block
model. A report, not a pass or fail gate. -/
def leafMoves (path : String) : IO UInt32 := do
  let text ← IO.FS.readFile path
  let json ← IO.ofExcept (Json.parse text)
  let jobs ← IO.ofExcept (json.getArr?)
  let mut m0 := 0
  let mut leaf := 0
  for j in jobs do
    let r : Except String (Option (String × Bool)) := do
      let kind ← j.getObjValAs? String "kind"
      if kind != "m0" then return none
      let name ← j.getObjValAs? String "name"
      let bits ← j.getObjValAs? Nat "bits"
      let src ← parseBlock (← j.getObjVal? "src")
      let tgt ← parseBlock (← j.getObjVal? "tgt")
      return some (name, checkLatLeaf FUEL ((List.range bits).toFinset) ∅ src tgt)
    match r with
    | .ok none => pure ()
    | .ok (some (name, ok)) =>
      m0 := m0 + 1
      if ok then leaf := leaf + 1 else IO.println s!"branch move: {name}"
    | .error e => IO.println s!"ERR  {e}"
  IO.println s!"{leaf} of {m0} M0 jobs move leaves only"
  return 0

def main (args : List String) : IO UInt32 := do
  if let ["--leaf-moves", path] := args then return ← leafMoves path
  let [path] := args | IO.eprintln "usage: qlincheck [--leaf-moves] JOBS.json"; return 2
  let text ← IO.FS.readFile path
  let json ← IO.ofExcept (Json.parse text)
  let jobs ← IO.ofExcept (json.getArr?)
  let mut failed := 0
  for j in jobs do
    match runJob j with
    | .ok (name, ok) =>
      IO.println s!"{if ok then "ok  " else "FAIL"} {name}"
      if !ok then failed := failed + 1
    | .error e =>
      IO.println s!"ERR  {e}"
      failed := failed + 1
  IO.println s!"{jobs.size - failed} of {jobs.size} jobs checked"
  return if failed == 0 then 0 else 1
