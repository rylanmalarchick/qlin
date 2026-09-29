"""Convert between qlin programs and Qiskit circuits.

`to_qiskit` reads the JSON tree from `qlin json`. `from_qiskit` writes
`.qlin` text. Run `qlin fmt` on that text to get the canonical form.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

from qiskit import ClassicalRegister, QuantumCircuit, QuantumRegister
from qiskit.circuit import CASE_DEFAULT, Clbit, IfElseOp, SwitchCaseOp, WhileLoopOp
from qiskit.circuit.classical import expr, types

ROOT = Path(__file__).resolve().parents[1]
QLIN = Path(os.environ.get("QLIN_BIN", ROOT / "target" / "release" / "qlin"))

# Gates with the same name and operand order in qlin and Qiskit.
SHARED_GATES = {
    "h", "x", "y", "z", "s", "sdg", "t", "tdg", "sx", "rx", "ry", "rz", "p",
    "u", "cx", "cy", "cz", "ch", "cp", "crz", "ccx", "swap",
}
# Qiskit ops that carry no semantics for this comparison.
IGNORED = {"barrier", "id", "delay"}


class Unsupported(Exception):
    """The circuit uses something the bridge does not convert."""


def qlin(*args: str) -> str:
    """Runs the qlin CLI and returns its stdout."""
    out = subprocess.run([str(QLIN), *args], capture_output=True, text=True, check=False)
    if out.returncode != 0:
        raise RuntimeError(f"qlin {' '.join(args)}: {out.stderr.strip()}")
    return out.stdout


def qlin_text(text: str, *args: str) -> str:
    """Runs `qlin ARGS FILE` with `text` written to FILE."""
    tmp = ROOT / "target" / "bridge_tmp.qlin"
    tmp.parent.mkdir(exist_ok=True)
    tmp.write_text(text)
    return qlin(*args, str(tmp))


# ---------------------------------------------------------------- to Qiskit


def _cond(e: dict, c: ClassicalRegister) -> expr.Expr:
    (kind, arg), = e.items()
    if kind == "Const":
        return expr.lift(bool(arg))
    if kind == "Bit":
        return expr.lift(c[arg])
    if kind == "Not":
        return expr.logic_not(_cond(arg, c))
    a, b = (_cond(x, c) for x in arg)
    if kind == "And":
        return expr.logic_and(a, b)
    if kind == "Or":
        return expr.logic_or(a, b)
    if kind == "Xor":
        return expr.bit_xor(a, b)
    raise Unsupported(f"bit expression {kind}")


def _literals(e: dict) -> list[tuple[int, int]] | None:
    """Returns [(bit, value)] if `e` is a conjunction of bit literals."""
    (kind, arg), = e.items()
    if kind == "Bit":
        return [(arg, 1)]
    if kind == "Not" and list(arg) == ["Bit"]:
        return [(arg["Bit"], 0)]
    if kind == "And":
        a, b = _literals(arg[0]), _literals(arg[1])
        if a is not None and b is not None:
            return a + b
    return None


def _condition_for(qc: QuantumCircuit, e: dict, c: ClassicalRegister, negate: bool = False):
    """A Qiskit condition for `e` (or its negation).

    A conjunction of literals becomes a `(register, value)` tuple over a
    register made of those bits, which every converter reads. Other
    expressions stay as classical `expr` trees.
    """
    lits = _literals(e)
    if negate and lits is not None and len(lits) == 1:
        lits = [(lits[0][0], 1 - lits[0][1])]
    elif negate:
        lits = None
    if lits is not None and len({b for b, _ in lits}) == len(lits):
        if len(lits) == 1:
            return (c[lits[0][0]], lits[0][1])
        reg = _register_for(qc, [b for b, _ in lits], c, "k")
        pos = {bit: i for i, bit in enumerate(reg)}
        return (reg, sum(v << pos[c[b]] for b, v in lits))
    cond = _cond(e, c)
    return expr.logic_not(cond) if negate else cond


def _register_for(qc: QuantumCircuit, bits: list[int], c, prefix: str) -> ClassicalRegister:
    """A register holding exactly these bits: an existing one if there is one
    (the no-alias layout makes them up front), else a new register that
    aliases bits of `c`."""
    want = {c[b] for b in bits}
    reg = next((r for r in qc.cregs if set(r) == want), None)
    if reg is None:
        reg = ClassicalRegister(name=prefix + "_".join(map(str, bits)), bits=[c[b] for b in bits])
        qc.add_register(reg)
    return reg


def _condition_sets(block: list, out: set) -> None:
    """Bit sets read together by a multi-bit condition or a Switch."""
    for op in block:
        (kind, a), = op.items()
        if kind == "If":
            lits = _literals(a["cond"])
            if lits is not None and len(lits) > 1:
                out.add(tuple(sorted(b for b, _ in lits)))
            _condition_sets(a["then_"], out)
            _condition_sets(a["else_"], out)
        elif kind == "Switch":
            if len(a["bits"]) > 1:
                out.add(tuple(sorted(a["bits"])))
            for _, body in a["cases"]:
                _condition_sets(body, out)
            _condition_sets(a["default"], out)
        elif kind == "Loop":
            _condition_sets(a["body"], out)


def _emit(qc: QuantumCircuit, block: list, q: QuantumRegister, c: ClassicalRegister,
          switch_as_if: bool = False) -> None:
    for op in block:
        (kind, a), = op.items()
        if kind == "Gate":
            if a["gate"] not in SHARED_GATES:
                raise Unsupported(f"gate {a['gate']}")
            getattr(qc, a["gate"])(*a["params"], *(q[i] for i in a["qubits"]))
        elif kind == "Measure":
            qc.measure(q[a["q"]], c[a["b"]])
        elif kind == "Reset":
            qc.reset(q[a["q"]])
        elif kind == "If":
            with qc.if_test(_condition_for(qc, a["cond"], c)) as else_:
                _emit(qc, a["then_"], q, c, switch_as_if)
            if a["else_"]:
                with else_:
                    _emit(qc, a["else_"], q, c, switch_as_if)
        elif kind == "Switch":
            # A register over the switch bits; case value bit i is bits[i].
            bits = a["bits"]
            reg = _register_for(qc, bits, c, "s")
            if list(reg) != [c[b] for b in bits]:
                raise Unsupported("switch bits are not in register order")
            if switch_as_if:
                _if_chain(qc, reg, a["cases"], a["default"], q, c)
            else:
                with qc.switch(reg) as case:
                    for values, body in a["cases"]:
                        with case(sum(int(v) << i for i, v in enumerate(values))):
                            _emit(qc, body, q, c)
                    if a["default"]:
                        with case(case.DEFAULT):
                            _emit(qc, a["default"], q, c)
        elif kind == "Loop":
            # qlin runs the body, then exits when `until` holds. Qiskit's
            # while loop tests first, so the body is written once before it.
            _emit(qc, a["body"], q, c, switch_as_if)
            with qc.while_loop(_condition_for(qc, a["until"], c, negate=True)):
                _emit(qc, a["body"], q, c, switch_as_if)
        else:
            raise Unsupported(f"op {kind}")


def _if_chain(qc, reg, cases, default, q, c) -> None:
    """A Switch as nested if/else on `reg == value`, for backends without
    switch_case."""
    if not cases:
        _emit(qc, default, q, c, True)
        return
    (values, body), rest = cases[0], cases[1:]
    with qc.if_test((reg, sum(int(v) << i for i, v in enumerate(values)))) as else_:
        _emit(qc, body, q, c, True)
    if rest or default:
        with else_:
            _if_chain(qc, reg, rest, default, q, c)


def to_qiskit(prog: dict, switch_as_if: bool = False, no_alias: bool = False) -> QuantumCircuit:
    """Builds a Qiskit circuit from a `qlin json` tree. With
    `switch_as_if`, a Switch becomes a nested if/else chain.

    With `no_alias`, every bit is in exactly one register: each bit set read
    by a multi-bit condition gets its own register, and the other bits go in
    `c`. IBM hardware rejects the default layout, where condition registers
    alias bits of `c`. Clbit order then differs from the qlin bit order, and
    `circuit.metadata["qlin_bits"]` gives the qlin bit of each clbit."""
    q = QuantumRegister(prog["n_qubits"], "q")
    if not no_alias:
        c = ClassicalRegister(max(prog["n_bits"], 1), "c")
        qc = QuantumCircuit(q, c)
        _emit(qc, prog["body"], q, c, switch_as_if)
        return qc
    sets: set = set()
    _condition_sets(prog["body"], sets)
    seen: set = set()
    for group in sorted(sets):
        if seen & set(group):
            raise Unsupported(f"condition bit sets overlap at {sorted(seen & set(group))}")
        seen |= set(group)
    rest = [b for b in range(prog["n_bits"]) if b not in seen]
    regs = ([ClassicalRegister(len(rest), "c")] if rest else []) + [
        ClassicalRegister(len(g), "r" + "_".join(map(str, g))) for g in sorted(sets)]
    qc = QuantumCircuit(q, *regs)
    order = rest + [b for g in sorted(sets) for b in g]
    bitmap: list = [None] * prog["n_bits"]
    for clbit, b in zip(qc.clbits, order):
        bitmap[b] = clbit
    qc.metadata = {"qlin_bits": order}
    _emit(qc, prog["body"], q, bitmap, switch_as_if)
    return qc


def load_qiskit(path: Path) -> tuple[QuantumCircuit, dict]:
    """Reads a .qlin file and returns the circuit and the JSON tree."""
    prog = json.loads(qlin("json", str(path)))
    return to_qiskit(prog), prog


# -------------------------------------------------------------- from Qiskit


def _bexpr(e: expr.Expr, bit_index) -> str:
    if isinstance(e, expr.Value):
        if e.type.kind is types.Bool:
            return "1" if e.value else "0"
        raise Unsupported(f"value {e!r}")
    if isinstance(e, expr.Var):
        if isinstance(e.var, Clbit):
            return f"c{bit_index(e.var)}"
        raise Unsupported(f"variable {e!r}")
    if isinstance(e, expr.Cast):
        return _bexpr(e.operand, bit_index)
    if isinstance(e, expr.Unary):
        if e.op in (expr.Unary.Op.LOGIC_NOT, expr.Unary.Op.BIT_NOT) and e.type.kind is types.Bool:
            return f"!({_bexpr(e.operand, bit_index)})"
        raise Unsupported(f"unary {e.op}")
    if isinstance(e, expr.Binary):
        # A register compared with an integer is a conjunction of literals.
        for reg_side, val_side in ((e.left, e.right), (e.right, e.left)):
            if (
                e.op in (expr.Binary.Op.EQUAL, expr.Binary.Op.NOT_EQUAL)
                and isinstance(reg_side, expr.Var)
                and isinstance(reg_side.var, ClassicalRegister)
                and isinstance(val_side, expr.Value)
            ):
                lits = _register_equals(reg_side.var, int(val_side.value), bit_index)
                return lits if e.op is expr.Binary.Op.EQUAL else f"!({lits})"
        ops = {
            expr.Binary.Op.LOGIC_AND: "&",
            expr.Binary.Op.BIT_AND: "&",
            expr.Binary.Op.LOGIC_OR: "|",
            expr.Binary.Op.BIT_OR: "|",
            expr.Binary.Op.BIT_XOR: "^",
            expr.Binary.Op.NOT_EQUAL: "^",
        }
        a, b = _bexpr(e.left, bit_index), _bexpr(e.right, bit_index)
        if e.op is expr.Binary.Op.EQUAL:
            return f"!(({a}) ^ ({b}))"
        if e.op in ops:
            return f"({a}) {ops[e.op]} ({b})"
        raise Unsupported(f"binary {e.op}")
    raise Unsupported(f"expression {e!r}")


def _register_equals(reg: ClassicalRegister, value: int, bit_index) -> str:
    if value < 0 or value >> len(reg):
        return "0"
    lits = [
        ("" if (value >> i) & 1 else "!") + f"c{bit_index(bit)}"
        for i, bit in enumerate(reg)
    ]
    return " & ".join(lits) if lits else "1"


def _condition(cond, bit_index) -> str:
    if isinstance(cond, expr.Expr):
        return _bexpr(cond, bit_index)
    target, value = cond
    if isinstance(target, Clbit):
        return f"c{bit_index(target)}" if value else f"!c{bit_index(target)}"
    return _register_equals(target, int(value), bit_index)


def _lines(circ: QuantumCircuit, qmap: dict, cmap: dict, loop_max: int, out: list, depth: int) -> None:
    pad = "  " * depth
    bit_index = cmap.__getitem__
    for inst in circ.data:
        op = inst.operation
        qs = [qmap[x] for x in inst.qubits]
        cs = [cmap[x] for x in inst.clbits]
        name = op.name
        if name in IGNORED:
            continue
        if name in SHARED_GATES:
            params = [float(p) for p in op.params]
            ps = f"({', '.join(repr(p) for p in params)})" if params else ""
            out.append(f"{pad}{name}{ps} " + " ".join(f"q{i}" for i in qs))
        elif name == "measure" or name.startswith("measure_"):
            # qiskit_ibm_runtime.MidCircuitMeasure is a measurement too.
            out.append(f"{pad}measure q{qs[0]} -> c{cs[0]}")
        elif name == "reset":
            out.append(f"{pad}reset q{qs[0]}")
        elif isinstance(op, IfElseOp):
            true_body, false_body = op.params[0], op.params[1]
            out.append(f"{pad}if {_condition(op.condition, bit_index)} {{")
            _lines(true_body, _inner(true_body.qubits, qs), _inner(true_body.clbits, cs), loop_max, out, depth + 1)
            if false_body is not None and len(false_body.data) > 0:
                out.append(f"{pad}}} else {{")
                _lines(false_body, _inner(false_body.qubits, qs), _inner(false_body.clbits, cs), loop_max, out, depth + 1)
            out.append(f"{pad}}}")
        elif isinstance(op, SwitchCaseOp):
            target = op.target
            if isinstance(target, Clbit):
                tbits = [bit_index(target)]
            elif isinstance(target, ClassicalRegister):
                tbits = [bit_index(b) for b in target]
            else:
                raise Unsupported(f"switch target {target!r}")
            out.append(f"{pad}switch {' '.join(f'c{b}' for b in tbits)} {{")
            for values, body in op.cases_specifier():
                qm, cm = _inner(body.qubits, qs), _inner(body.clbits, cs)
                for v in values:
                    if v is CASE_DEFAULT:
                        out.append(f"{pad}  default {{")
                    else:
                        bitsv = " ".join("1" if (int(v) >> i) & 1 else "0" for i in range(len(tbits)))
                        out.append(f"{pad}  case {bitsv} {{")
                    _lines(body, qm, cm, loop_max, out, depth + 2)
                    out.append(f"{pad}  }}")
            out.append(f"{pad}}}")
        elif isinstance(op, WhileLoopOp):
            body = op.params[0]
            cond = _condition(op.condition, bit_index)
            qm, cm = _inner(body.qubits, qs), _inner(body.clbits, cs)
            flat: list = []
            _lines(body, qm, cm, loop_max, flat, depth)
            if flat and out[len(out) - len(flat):] == flat:
                # `B; while (c) { B }` is qlin's `loop { B } until !c`.
                del out[len(out) - len(flat):]
                out.append(f"{pad}loop max {loop_max} {{")
                out.extend("  " + line for line in flat)
                out.append(f"{pad}}} until {_negate(cond)}")
            else:
                # `while (c) { B }` is `if c { loop { B } until !c }`.
                out.append(f"{pad}if {cond} {{")
                out.append(f"{pad}  loop max {loop_max} {{")
                out.extend("    " + line for line in flat)
                out.append(f"{pad}  }} until {_negate(cond)}")
                out.append(f"{pad}}}")
        elif op.definition is not None:
            # An opaque wrapper (for example the `If` blocks that
            # tk_to_qiskit emits). Its definition is its semantics.
            d = op.definition
            _lines(d, _inner(d.qubits, qs), _inner(d.clbits, cs), loop_max, out, depth)
        else:
            raise Unsupported(f"instruction {name}")


def _negate(cond: str) -> str:
    """Negates a condition string, removing one outer `!( )` if present."""
    if cond.startswith("!(") and cond.endswith(")"):
        depth = 0
        for i, ch in enumerate(cond[1:], start=1):
            depth += ch == "("
            depth -= ch == ")"
            if depth == 0:
                if i == len(cond) - 1:
                    return cond[2:-1]
                return f"!({cond})"
    return f"!({cond})"


def _inner(inner_bits, outer_indices) -> dict:
    return {b: outer_indices[i] for i, b in enumerate(inner_bits)}


def bit_names(circ: QuantumCircuit) -> tuple[dict, dict]:
    """Maps (register name, index) to bit position, for qubits and clbits."""
    qn = {(r.name, i): circ.find_bit(b).index for r in circ.qregs for i, b in enumerate(r)}
    cn = {(r.name, i): circ.find_bit(b).index for r in circ.cregs for i, b in enumerate(r)}
    return qn, cn


def _index_map(bits, circ: QuantumCircuit, names: dict | None) -> dict:
    """Positions for `bits`. With `names`, a bit keeps the position of the
    source bit with the same (register, index). Other bits get new
    positions after the named ones."""
    if names is None:
        return {b: i for i, b in enumerate(bits)}
    out, fresh = {}, len(set(names.values()))
    for b in bits:
        hits = [names[(r.name, i)] for r, i in circ.find_bit(b).registers if (r.name, i) in names]
        if hits:
            out[b] = hits[0]
        else:
            out[b] = fresh
            fresh += 1
    return out


def from_qiskit(circ: QuantumCircuit, loop_max: int = 8, names: tuple[dict, dict] | None = None) -> str:
    """Writes a Qiskit circuit as .qlin text in canonical form.

    `names` (from `bit_names` on the source circuit) keeps bit positions
    stable when a tool renames or splits registers.
    """
    qmap = _index_map(circ.qubits, circ, names[0] if names else None)
    cmap = _index_map(circ.clbits, circ, names[1] if names else None)
    n_q = max(qmap.values(), default=-1) + 1
    n_c = max(cmap.values(), default=-1) + 1
    out = [f"qubits {n_q}", f"bits {n_c}"]
    _lines(circ, qmap, cmap, loop_max, out, 0)
    return qlin_text("\n".join(out) + "\n", "fmt")
