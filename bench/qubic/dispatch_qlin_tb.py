"""cocotb testbench (not a pytest file): controller cycles of qlin dispatch programs on the QubiC
distributed processor (one core, RTL simulation, no qubits).

Reads programs from $QLIN_DISPATCH_IN (written by bench/run_qubic.py, in the
instruction list of bench/qubic_dispatch.py) and, for every syndrome value,
counts clock cycles from fproc_ready (the syndrome arrives in register 0) to
the first cycle the instruction pointer reaches `done`. Writes the counts to
$QLIN_DISPATCH_OUT.
"""

import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

import distproc.command_gen as cg

FUNC_ID = 0
READY_AT = 20
MAX_CYCLES = 20000


def encode(ins):
    op = ins[0]
    if op == "read":
        return cg.read_fproc(FUNC_ID, 0)
    if op in ("eq", "le"):
        return cg.alu_cmd("jump_cond", "i", ins[1], op, alu_in1=0, jump_cmd_ptr=ins[2])
    if op == "jump":
        return cg.jump_i(ins[1])
    if op == "mark":
        return cg.alu_cmd("reg_alu", "i", 1, "id0", write_reg_addr=1)
    if op == "done":
        return cg.done_cmd()
    raise ValueError(op)


async def cycles_to_done(dut, words, done_addr, s):
    for addr, w in enumerate(words):
        dut.cmd_write.value = w
        dut.cmd_write_addr.value = addr
        dut.cmd_write_enable.value = 1
        await RisingEdge(dut.clk)
    dut.cmd_write_enable.value = 0
    dut.fproc_ready.value = 0
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    for _ in range(READY_AT):
        await RisingEdge(dut.clk)
    dut.fproc_ready.value = 1
    dut.fproc_data.value = s
    for cyc in range(MAX_CYCLES):
        await RisingEdge(dut.clk)
        if cyc == 0:
            dut.fproc_ready.value = 0
        if int(dut.memif.instr_ptr.value) == done_addr:
            return cyc + 1
    raise AssertionError(f"s = {s}: pointer never reached done at {done_addr}")


@cocotb.test()
async def dispatch(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    progs = json.loads(open(os.environ["QLIN_DISPATCH_IN"]).read())
    out = []
    for p in progs:
        code = [tuple(i) for i in p["code"]]
        words = [encode(i) for i in code]
        done_addr = next(a for a, i in enumerate(code) if i[0] == "done")
        for s in p["values"]:
            c = await cycles_to_done(dut, words, done_addr, s)
            out.append({"key": p["key"], "s": s, "cycles": c})
    open(os.environ["QLIN_DISPATCH_OUT"], "w").write(json.dumps(out))
