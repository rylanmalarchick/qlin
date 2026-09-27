"""Spike: how does Selene's SimpleRuntime time a dynamic program?

Run: uv run --project bench python bench/spike_selene.py

Prints, for a few shots of teleportation, every instruction that reaches
the simulator (with its duration) and every runtime batch start time.
The questions (see notes/selene-timing.txt):
  (i)  does it charge any latency between a measurement and a branch?
  (ii) when does it sync (flush a batch)?
  (iii) how does it lower cx and cz to native rxy, rz, rzz?
"""

from guppylang import guppy
from guppylang.std.builtins import result
from guppylang.std.quantum import cx, discard, h, measure, qubit, x, z
from selene_sim import CircuitExtractor, Quest, SimpleRuntime, build
from selene_sim.event_hooks.instruction_log import BatchStart, Source

# HERON_KINGSTON durations (notes/cost-sources.txt). Selene has no rz
# time of its own. rz is virtual on IBM, so 0.
RUNTIME = SimpleRuntime(
    duration_ns_rxy=32,
    duration_ns_rzz=68,
    duration_ns_rz=0,
    duration_ns_measure=1760,
    duration_ns_reset=2312,
)


@guppy
def teleport() -> None:
    q0 = qubit()
    q1 = qubit()
    q2 = qubit()
    h(q1)
    cx(q1, q2)
    cx(q0, q1)
    h(q0)
    m0 = measure(q0)
    m1 = measure(q1)
    b1 = m1.read()
    if b1:
        x(q2)
    b0 = m0.read()
    if b0:
        z(q2)
    result("c0", b0)
    result("c1", b1)
    discard(q2)


def main() -> None:
    inst = build(teleport.compile())
    hook = CircuitExtractor()
    # Each shot's results must be consumed while the shot runs.
    shots = [list(s) for s in inst.run_shots(Quest(), n_qubits=3, n_shots=4, runtime=RUNTIME,
                                             event_hook=hook, random_seed=5)]
    for k, (res, log) in enumerate(zip(shots, hook.shots)):
        print(f"== shot {k}: {res}")
        for ins in log:
            if ins.source == Source.SIMULATOR or isinstance(ins.operation, BatchStart):
                print(f"  {ins.source.name:9} {ins.duration_ns!s:>6}  {ins.operation.to_dict()}")


if __name__ == "__main__":
    main()
