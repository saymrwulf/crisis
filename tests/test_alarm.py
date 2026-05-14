"""Tests for byzantine equivocation detection."""

import pytest

from crisis_agents.agent import MockAgent, MockByzantineAgent
from crisis_agents.alarm import AlarmEvent, scan_for_mutations
from crisis_agents.claim import Claim
from crisis_agents.mothership import Mothership


def _claim(sid: str, verdict: str = "true", evidence: str = "ok") -> Claim:
    return Claim(statement_id=sid, verdict=verdict, confidence=0.9,  # type: ignore[arg-type]
                 evidence=evidence, timestamp_logical=0)


def _equivocating_team() -> Mothership:
    """A 3-honest-1-byzantine team where the byzantine equivocates on s03."""
    m = Mothership()
    m.add_agent(MockAgent("a", [[]]))
    m.add_agent(MockAgent("b", [[]]))
    m.add_agent(MockAgent("c", [[]]))
    m.open_boundary(MockByzantineAgent(
        "d",
        scripted_pairs=[(
            _claim("s03", verdict="true", evidence="to_a"),
            _claim("s03", verdict="false", evidence="to_b"),
        )],
        split_a={"a", "c"},
        split_b={"b"},
    ))
    return m


class TestAlarmDetection:

    def test_no_alarms_in_honest_run(self):
        m = Mothership()
        m.add_agent(MockAgent("a", [[]]))
        m.add_agent(MockAgent("b", [[]]))
        m.open_boundary(MockAgent("d", [[_claim("s01")]]))
        m.run_crisis_phase(num_turns=1)
        alarms = scan_for_mutations(m)
        assert alarms == []

    def test_equivocation_raises_one_alarm(self):
        m = _equivocating_team()
        m.run_crisis_phase(num_turns=1)
        alarms = scan_for_mutations(m)
        assert len(alarms) == 1

        a = alarms[0]
        assert isinstance(a, AlarmEvent)
        assert a.accused_agent == "d"
        assert a.statement_id == "s03"
        assert a.turn == 0
        assert len(a.witnesses) == 2

    def test_witness_digests_are_distinct(self):
        m = _equivocating_team()
        m.run_crisis_phase(num_turns=1)
        a = scan_for_mutations(m)[0]
        d1 = a.witnesses[0].message_digest_hex
        d2 = a.witnesses[1].message_digest_hex
        assert d1 != d2

    def test_delivery_sets_are_disjoint(self):
        m = _equivocating_team()
        m.run_crisis_phase(num_turns=1)
        a = scan_for_mutations(m)[0]
        s1 = set(a.witnesses[0].delivered_to)
        s2 = set(a.witnesses[1].delivered_to)
        assert s1 & s2 == set()

    def test_spacelike_verified_is_true(self):
        """The Crisis layer should confirm the witness vertices are causally
        incomparable in at least one honest graph."""
        m = _equivocating_team()
        m.run_crisis_phase(num_turns=1)
        a = scan_for_mutations(m)[0]
        assert a.spacelike_verified is True

    def test_duplicate_broadcast_is_not_equivocation(self):
        """If a byzantine emits the SAME payload to two disjoint subsets,
        the message digests are identical and it's not equivocation."""
        same = _claim("s03", verdict="true", evidence="same evidence")
        m = Mothership()
        m.add_agent(MockAgent("a", [[]]))
        m.add_agent(MockAgent("b", [[]]))
        m.open_boundary(MockByzantineAgent(
            "d",
            scripted_pairs=[(same, same)],
            split_a={"a"},
            split_b={"b"},
        ))
        m.run_crisis_phase(num_turns=1)
        alarms = scan_for_mutations(m)
        # Same payload → same nonce-mined message after PoW → same digest →
        # no equivocation. (The byzantine has to actually say different
        # things to be caught.)
        assert alarms == [] or all(
            len({w.message_digest_hex for w in alarm.witnesses}) > 1
            for alarm in alarms
        )
