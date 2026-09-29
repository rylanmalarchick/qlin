"""Generate a Guppy program from a qlin program, and run it on Selene.

Gates without a Guppy op are decomposed, exact up to a global phase:
  p(t) = rz(t), cp(t) = rz(t/2) on the control then crz(t),
  sx = rx(pi/2), u(t, f, l) = rz(l) ry(t) rz(f), swap = 3 cx.
A measure is `project_z(q).read()`, so it blocks until the result exists.
All qubits are allocated at the start and discarded at the end. Every bit
is output as `c<i>`.

A qlin loop that hits `max_iters` stops the program. The generated loop
stops the loop and continues. Programs with loops can differ on those
(rare) outcomes, so callers exclude them from exact checks.
"""

from __future__ import annotations

import importlib.util
import json
import math
import tempfile
from pathlib import Path

from qlin_qiskit import qlin

HEADER = """\
from guppylang import guppy
from guppylang.std.angles import angle
from guppylang.std.builtins import result
from guppylang.std.quantum import (
    ch, crz, cx, cy, cz, discard, h, project_z, qubit, rx, ry, rz, s, sdg, t,
    tdg, toffoli, x, y, z, reset,
)
"""

SIMPLE = {"h", "x", "y", "z", "s", "sdg", "t", "tdg", "cx", "cy", "cz", "ch"}


def _ang(theta: float) -> str:
    return f"angle({theta / math.pi!r})"


def _cond(e: dict) -> str:
    (kind, arg), = e.items()
    if kind == "Const":
        return "True" if arg else "False"
    if kind == "Bit":
        return f"c{arg}"
    if kind == "Not":
        return f"(not {_cond(arg)})"
    a, b = (_cond(x) for x in arg)
    return {"And": f"({a} and {b})", "Or": f"({a} or {b})", "Xor": f"({a} != {b})"}[kind]


def _gate(g: str, qs: list[int], ps: list[float], pad: str) -> list[str]:
    q = [f"q{i}" for i in qs]
    if g in SIMPLE:
        return [f"{pad}{g}({', '.join(q)})"]
    if g in ("rx", "ry", "rz"):
        return [f"{pad}{g}({q[0]}, {_ang(ps[0])})"]
    if g == "p":
        return [f"{pad}rz({q[0]}, {_ang(ps[0])})"]
    if g == "sx":
        return [f"{pad}rx({q[0]}, {_ang(math.pi / 2)})"]
    if g == "u":
        th, ph, la = ps
        return [f"{pad}rz({q[0]}, {_ang(la)})", f"{pad}ry({q[0]}, {_ang(th)})",
                f"{pad}rz({q[0]}, {_ang(ph)})"]
    if g == "crz":
        return [f"{pad}crz({q[0]}, {q[1]}, {_ang(ps[0])})"]
    if g == "cp":
        return [f"{pad}rz({q[0]}, {_ang(ps[0] / 2)})", f"{pad}crz({q[0]}, {q[1]}, {_ang(ps[0])})"]
    if g == "ccx":
        return [f"{pad}toffoli({', '.join(q)})"]
    if g == "swap":
        a, b = q
        return [f"{pad}cx({a}, {b})", f"{pad}cx({b}, {a})", f"{pad}cx({a}, {b})"]
    raise ValueError(f"no Guppy form for gate {g}")


class _Gen:
    def __init__(self) -> None:
        self.loops = 0

    def block(self, ops: list, depth: int) -> list[str]:
        pad = "    " * depth
        out: list[str] = []
        for op in ops:
            (kind, a), = op.items()
            if kind == "Gate":
                out += _gate(a["gate"], a["qubits"], a["params"], pad)
            elif kind == "Measure":
                out.append(f"{pad}c{a['b']} = project_z(q{a['q']}).read()")
            elif kind == "Reset":
                out.append(f"{pad}reset(q{a['q']})")
            elif kind == "If":
                out.append(f"{pad}if {_cond(a['cond'])}:")
                out += self.block(a["then_"], depth + 1) or [f"{pad}    pass"]
                if a["else_"]:
                    out.append(f"{pad}else:")
                    out += self.block(a["else_"], depth + 1)
            elif kind == "Switch":
                first = True
                for values, body in a["cases"]:
                    test = " and ".join(f"c{b}" if v else f"(not c{b})"
                                        for b, v in zip(a["bits"], values))
                    out.append(f"{pad}{'if' if first else 'elif'} {test}:")
                    out += self.block(body, depth + 1) or [f"{pad}    pass"]
                    first = False
                if a["default"]:
                    out.append(f"{pad}else:")
                    out += self.block(a["default"], depth + 1)
            elif kind == "Loop":
                k = self.loops
                self.loops += 1
                out += [f"{pad}done{k} = False", f"{pad}it{k} = 0",
                        f"{pad}while not done{k} and it{k} < {a['max_iters']}:"]
                out += self.block(a["body"], depth + 1)
                out += [f"{pad}    done{k} = {_cond(a['until'])}", f"{pad}    it{k} += 1"]
            else:
                raise ValueError(f"no Guppy form for op {kind}")
        return out


def guppy_source(prog: dict) -> str:
    """Guppy module source with one entry function `main`."""
    n, m = prog["n_qubits"], prog["n_bits"]
    body = [f"    q{i} = qubit()" for i in range(n)]
    body += [f"    c{i} = False" for i in range(m)]
    body += _Gen().block(prog["body"], 1)
    body += [f"    result(\"c{i}\", c{i})" for i in range(m)]
    body += [f"    discard(q{i})" for i in range(n)]
    return HEADER + "\n\n@guppy\ndef main() -> None:\n" + "\n".join(body) + "\n"


def load_main(source: str):
    """Imports generated source from a temporary file and returns `main`."""
    d = Path(tempfile.mkdtemp(prefix="qlin_guppy_"))
    path = d / "prog.py"
    path.write_text(source)
    spec = importlib.util.spec_from_file_location(f"qlin_guppy_{d.name}", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.main


def from_file(path: Path):
    """The Guppy `main` for a .qlin file."""
    return load_main(guppy_source(json.loads(qlin("json", str(path)))))
