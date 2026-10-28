"""run_phase4_ibm --submit-ahead against a fake IBM service: submission order,
collection order, re-login on 401, an adopted smoke job, and a failed job."""

import json
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
import qiskit_ibm_runtime
from qiskit_ibm_runtime.exceptions import IBMNotAuthorizedError, RuntimeJobFailureError
from qiskit_ibm_runtime.fake_provider import FakeKingston

import run_phase4_ibm as runner

T0 = datetime(2026, 10, 28, tzinfo=timezone.utc)


class Fake:
    """Shared state of the fake service: submitted jobs and logins."""

    def __init__(self, fail: str | None):
        self.jobs: list[str] = []
        self.logins = 0
        self.expired = True  # the first result call raises 401
        self.fail = fail


def install(monkeypatch, fake: Fake) -> None:
    backend = FakeKingston()

    class Job:
        def __init__(self, jid):
            self.jid = jid

        def job_id(self):
            return self.jid

        def result(self):
            if fake.expired:
                fake.expired = False
                raise IBMNotAuthorizedError("401 token expired")
            if self.jid == fake.fail:
                raise RuntimeJobFailureError("job failed")
            # Per-shot time encodes the submission index: job i takes i us per shot.
            i = int(self.jid.removeprefix("j"))
            span = SimpleNamespace(start=T0, stop=T0 + timedelta(microseconds=i * runner.SHOTS))
            return SimpleNamespace(metadata={"execution": {"execution_spans": [span]}})

    class Service:
        def __init__(self):
            fake.logins += 1

        def active_instance(self):
            return "crn:open"

        def instances(self):
            return [{"crn": "crn:open", "plan": "open"}]

        def usage(self):
            return {"usage_remaining_seconds": 358, "usage_consumed_seconds": 242}

        def backend(self, name):
            return backend

        def job(self, jid):
            return Job(jid)

    class Sampler:
        def __init__(self, mode):
            pass

        def run(self, circs, shots):
            fake.jobs.append(f"j{len(fake.jobs) + 1}")
            return Job(fake.jobs[-1])

    monkeypatch.setattr(qiskit_ibm_runtime, "QiskitRuntimeService", Service)
    monkeypatch.setattr(qiskit_ibm_runtime, "SamplerV2", Sampler)
    monkeypatch.setattr(runner, "RESULTS", runner.RESULTS.parent / "target" / "test_run_ahead")
    monkeypatch.setattr(runner, "REPEATS", 3)
    monkeypatch.setattr(runner, "BUDGET_S", 300)


def run(monkeypatch, fail: str | None = None) -> tuple[Fake, dict]:
    fake = Fake(fail)
    install(monkeypatch, fake)
    runner.main(False, bench="five_qubit_code", only={"source", "best_defer"}, out="t",
                interleave=True, copies=[1, 2], ahead=True, smoke_job="j0")
    rows = {r["variant"]: r for r in json.loads((runner.RESULTS / "t.json").read_text())}
    return fake, rows


def test_rounds_are_submitted_and_collected_in_order(monkeypatch):
    fake, rows = run(monkeypatch)
    # The adopted smoke job j0 is not resubmitted: 3 rounds x 4 circuits.
    assert fake.jobs == [f"j{i}" for i in range(1, 13)]
    order = ["source_x1", "best_defer_x1", "source_x2", "best_defer_x2"]
    for c, v in enumerate(order):
        # Exact up to the float rounding of the span arithmetic.
        assert rows[v]["times"] == pytest.approx([1000.0 * (r * 4 + c + 1) for r in range(3)], rel=1e-12)
        assert rows[v]["why"] is None
    assert rows["source_x1"]["jobs"][0] == "j0"
    # One login at the start, one after the 401, one before the submission.
    assert fake.logins == 3


def test_a_failed_job_ends_its_row_only(monkeypatch):
    _, rows = run(monkeypatch, fail="j6")  # round 2 of best_defer_x1
    assert rows["best_defer_x1"]["times"] == pytest.approx([2000.0], rel=1e-12)
    assert "job failed" in rows["best_defer_x1"]["why"]
    assert rows["source_x2"]["times"] == pytest.approx([3000.0, 7000.0, 11000.0], rel=1e-12)
