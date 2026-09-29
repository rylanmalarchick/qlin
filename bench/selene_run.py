"""Run a Guppy program on Selene and return per-shot bits and timelines."""

from __future__ import annotations

from selene_sim import CircuitExtractor, Quest, SimpleRuntime, build
from selene_sim.event_hooks.instruction_log import BatchStart


def run(main, n_qubits: int, n_bits: int, shots: int, runtime: SimpleRuntime | None = None,
        seed: int = 1, timeline: bool = False):
    """Returns one (bits, span_ns) per shot. `bits` is a tuple of the
    output bits c0.. in order. `span_ns` is the time from the shot's first
    batch start to its last batch end (None unless `timeline`)."""
    inst = build(main.compile())
    hook = CircuitExtractor() if timeline else None
    kwargs = {"event_hook": hook} if hook else {}
    # Each shot's results must be consumed while the shot runs.
    raw = [dict(s) for s in inst.run_shots(Quest(), n_qubits=max(n_qubits, 1), n_shots=shots,
                                           runtime=runtime or SimpleRuntime(),
                                           random_seed=seed, **kwargs)]
    out = []
    for k, res in enumerate(raw):
        bits = tuple(bool(res[f"c{i}"]) for i in range(n_bits))
        span = None
        if timeline:
            starts = [(i.operation.start_time_ns, i.operation.duration_ns)
                      for i in hook.shots[k] if isinstance(i.operation, BatchStart)]
            span = max(s + d for s, d in starts) - min(s for s, _ in starts) if starts else 0
        out.append((bits, span))
    return out
