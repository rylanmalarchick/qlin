"""Compare a sampled distribution with an exact one.

Two tests, both needed:
  total variation distance <= 2 x its expected sampling value + 0.02, where
    E|p_hat - p| is sqrt(2 p (1 - p) / (pi N)) per outcome (normal
    approximation), and TV is half the sum over outcomes;
  support: no outcome with exact probability 0 is seen 3 or more times.
A per-outcome absolute tolerance is not enough: on a broad distribution
(p about 0.004 over 256 outcomes) it accepts a disjoint one.
"""

from __future__ import annotations

import math


def compare(exact: dict[str, float], counts: dict[str, int]) -> str | None:
    """None if the samples fit `exact`, else the reason."""
    n = sum(counts.values())
    got = {k: v / n for k, v in counts.items()}
    tv = 0.5 * sum(abs(exact.get(k, 0.0) - got.get(k, 0.0)) for k in set(exact) | set(got))
    expected = 0.5 * sum(math.sqrt(2 * p * (1 - p) / (math.pi * n)) for p in exact.values())
    bound = 2 * expected + 0.02
    if tv > bound:
        return f"total variation {tv:.3f} > {bound:.3f}"
    impossible = [k for k, v in counts.items() if exact.get(k, 0.0) == 0.0 and v >= 3]
    if impossible:
        return f"outcome {impossible[0]} has probability 0 but was seen {counts[impossible[0]]} times"
    return None
