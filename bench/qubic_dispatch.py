"""Dispatch programs for the QubiC distributed processor, from qlin output.

The first `switch` of a qlin fast path dispatches a group of `if`s on the
group bits G. This module builds three programs for that group, in a small
instruction list that bench/qubic/test_dispatch_qlin.py turns into QubiC
machine code (distproc.command_gen):

  source  the group as compiled ifs: each `if` compares the syndrome with
          the values that take it and jumps over its arm otherwise
  chain   the switch as a compare chain: one EQ per case, then the default
  tree    the switch as a binary search on the value: LE (strictly less),
          then EQ at the leaves, then the default

The syndrome s is the integer of the group bits, bit i of s being G[i]. It
arrives in register 0 by `read` (the function-processor interface). The
default of a switch is the source group, the exit edge of the fast path.
Arms emit one `mark` per op. Every program ends at `done`.

Instructions: ("read",), ("eq", v, target), ("le", v, target) jumps when
v < s, ("jump", target), ("mark", tag), ("done",).
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class Group:
    bits: list[int]                 # G, in switch order
    ifs: list[tuple[dict, list, list]]  # (cond, then_, else_) of each If
    cases: list[int]                # switch case values (ints over G)


def eval_cond(cond: dict, val: dict[int, bool]) -> bool:
    """qlin BitExpr (JSON form of `qlin json`) under bit values `val`."""
    (kind, arg), = cond.items()
    if kind == "Bit":
        return val[arg]
    if kind == "Const":
        return bool(arg)
    if kind == "Not":
        return not eval_cond(arg, val)
    if kind in ("And", "Or", "Xor"):
        a, b = (eval_cond(x, val) for x in arg)
        return {"And": a and b, "Or": a or b, "Xor": a != b}[kind]
    raise ValueError(f"unknown condition {kind}")


def cond_bits(cond: dict) -> set[int]:
    (kind, arg), = cond.items()
    if kind == "Bit":
        return {arg}
    if kind == "Const":
        return set()
    if kind == "Not":
        return cond_bits(arg)
    return set().union(*(cond_bits(x) for x in arg))


def values(bits: list[int], s: int) -> dict[int, bool]:
    return {b: bool(s >> i & 1) for i, b in enumerate(bits)}


def group_of(fast: dict) -> Group:
    """The first top-level switch of a fast-path program (`qlin json`) and
    the If group at the head of its default."""
    sw = next(op["Switch"] for op in fast["body"] if "Switch" in op)
    bits = list(sw["bits"])
    ifs = []
    for op in sw["default"]:
        if "If" not in op or not cond_bits(op["If"]["cond"]) <= set(bits):
            break
        ifs.append((op["If"]["cond"], op["If"]["then_"], op["If"]["else_"]))
    cases = [sum(int(b) << i for i, b in enumerate(vals)) for vals, _ in sw["cases"]]
    return Group(bits, ifs, cases)


def selected(g: Group, s: int) -> list[str]:
    """Tags of the arm ops that syndrome s runs, in program order."""
    val = values(g.bits, s)
    out = []
    for k, (cond, then_, else_) in enumerate(g.ifs):
        arm, side = (then_, "t") if eval_cond(cond, val) else (else_, "e")
        out += [f"if{k}{side}{j}" for j in range(len(arm))]
    return out


class Asm:
    """Labels resolve to addresses at the end."""

    def __init__(self):
        self.code: list[tuple] = []
        self.labels: dict[str, int] = {}

    def label(self, name: str) -> None:
        self.labels[name] = len(self.code)

    def emit(self, *ins) -> None:
        self.code.append(ins)

    def done(self) -> list[tuple]:
        return [tuple(self.labels[x] if isinstance(x, str) and x.startswith("@") else x
                      for x in ins) for ins in self.code]


def emit_ifs(a: Asm, g: Group, prefix: str) -> None:
    """The source group: for each if, EQ jumps on its true values, else
    falls through to the else arm (or skips the then arm)."""
    n = 1 << len(g.bits)
    for k, (cond, then_, else_) in enumerate(g.ifs):
        true_vals = [s for s in range(n) if eval_cond(cond, values(g.bits, s))]
        then_l, next_l = f"@{prefix}then{k}", f"@{prefix}next{k}"
        for v in true_vals:
            a.emit("eq", v, then_l)
        for j in range(len(else_)):
            a.emit("mark", f"if{k}e{j}")
        a.emit("jump", next_l)
        a.label(then_l)
        for j in range(len(then_)):
            a.emit("mark", f"if{k}t{j}")
        a.label(next_l)


def emit_case_bodies(a: Asm, g: Group) -> None:
    for v in g.cases:
        a.label(f"@case{v}")
        for tag in selected(g, v):
            a.emit("mark", tag)
        a.emit("jump", "@end")


def emit_tree(a: Asm, vals: list[int], depth: int = 0, path: str = "") -> None:
    if len(vals) <= 2:
        for v in vals:
            a.emit("eq", v, f"@case{v}")
        a.emit("jump", "@default")
        return
    mid = len(vals) // 2
    right = f"@r{path}"
    a.emit("le", vals[mid - 1], right)   # jump right when vals[mid-1] < s
    emit_tree(a, vals[:mid], depth + 1, path + "l")
    a.label(right)
    emit_tree(a, vals[mid:], depth + 1, path + "r")


def program(g: Group, variant: str) -> list[tuple]:
    a = Asm()
    a.emit("read",)
    if variant == "source":
        emit_ifs(a, g, "s")
    else:
        cases = sorted(g.cases)
        if variant == "chain":
            for v in g.cases:
                a.emit("eq", v, f"@case{v}")
            a.emit("jump", "@default")
        elif variant == "tree":
            emit_tree(a, cases)
        else:
            raise ValueError(variant)
        emit_case_bodies(a, g)
        a.label("@default")
        emit_ifs(a, g, "d")
    a.label("@end")
    a.emit("done",)
    return a.done()


def run(code: list[tuple], s: int, max_steps: int = 10_000) -> tuple[list[str], int]:
    """Reference interpreter: the marks executed for syndrome s, and the
    number of conditional jumps evaluated."""
    marks, counts = trace(code, s, max_steps)
    return marks, counts["cond_taken"] + counts["cond_not"]


def trace(code: list[tuple], s: int, max_steps: int = 10_000) -> tuple[list[str], dict[str, int]]:
    """The marks executed for syndrome s, and how many instructions of each
    kind ran: cond_taken, cond_not (eq, le), jump, mark."""
    pc, marks = 0, []
    counts = {"cond_taken": 0, "cond_not": 0, "jump": 0, "mark": 0}
    for _ in range(max_steps):
        ins = code[pc]
        op = ins[0]
        if op == "done":
            return marks, counts
        if op in ("eq", "le"):
            taken = ins[1] == s if op == "eq" else ins[1] < s
            counts["cond_taken" if taken else "cond_not"] += 1
            pc = ins[2] if taken else pc + 1
        elif op == "jump":
            counts["jump"] += 1
            pc = ins[1]
        elif op == "mark":
            counts["mark"] += 1
            marks.append(ins[1])
            pc += 1
        else:   # read
            pc += 1
    raise RuntimeError("program did not reach done")
