"""The generated lookup tables equal dynamarq's for d = 3 and 5."""

from dynamarq.benchmarks.eccs.RepetitionCode import RepetitionCode

from gen_repetition import corrections


def test_tables_match_dynamarq():
    rc = RepetitionCode(3)
    assert sorted(rc.corrections_3) == corrections(3)
    assert sorted(rc.corrections_5) == corrections(5)
