"""Tests for AlarmClaim + tally_alarms (the voting layer)."""

import pytest

from crisis_agents.agent import MockAgent, MockByzantineAgent
from crisis_agents.alarm import LocalAlarm
from crisis_agents.claim import Claim
from crisis_agents.mothership import Mothership
from crisis_agents.vote import (
    AlarmClaim,
    RatifiedAlarm,
    collect_alarm_claims,
    quorum_for,
    tally_alarms,
)


def _claim(sid: str, verdict: str = "true", evidence: str = "ok") -> Claim:
    return Claim(statement_id=sid, verdict=verdict, confidence=0.9,  # type: ignore[arg-type]
                 evidence=evidence, timestamp_logical=0)


def _intro(name: str = "delta") -> Claim:
    return Claim(statement_id=f"intro:{name}", verdict="unknown", confidence=1.0,
                 evidence=f"{name} joining the team", timestamp_logical=0)


def _full_run() -> Mothership:
    """3 honest + 1 byzantine; equivocation; gossip; alarms emitted;
    final gossip propagates the AlarmClaims to every agent."""
    m = Mothership()
    m.add_agent(MockAgent("a", [[]]))
    m.add_agent(MockAgent("b", [[]]))
    m.add_agent(MockAgent("c", [[]]))
    byz = MockByzantineAgent(
        "d", _intro(),
        scripted_pairs=[(
            _claim("s03", verdict="true", evidence="to_ac"),
            _claim("s03", verdict="false", evidence="to_b"),
        )],
        split_a={"a", "c"},
        split_b={"b"},
    )
    m.open_boundary(byz)
    m.run_crisis_phase(num_turns=2, gossip_rounds_per_turn=1)
    # Honest agents emit AlarmClaims based on what they observed.
    m.emit_alarms_from_detectors()
    # One more gossip round so every honest agent sees all AlarmClaims.
    m.run_gossip_round()
    return m


class TestQuorumThreshold:

    def test_quorum_formulas(self):
        # ceil(2N/3) — the classic BFT threshold
        assert quorum_for(1) == 1
        assert quorum_for(2) == 2
        assert quorum_for(3) == 2
        assert quorum_for(4) == 3
        assert quorum_for(7) == 5
        assert quorum_for(10) == 7


class TestAlarmClaimRoundtrip:

    def test_serialize_deserialize(self):
        ac = AlarmClaim(
            accused_process_id_hex="76468f93",
            statement_id="s03",
            witness_digests=("aaaa", "bbbb"),
            detected_at_turn=1,
        )
        roundtrip = AlarmClaim.from_payload(ac.to_payload())
        assert roundtrip == ac

    def test_from_local_alarm(self):
        la = LocalAlarm(
            detector_name="a",
            detector_process_id_hex="11",
            accused_process_id_hex="22",
            statement_id="s03",
            witness_digests=("aa", "bb"),
        )
        ac = AlarmClaim.from_local_alarm(la, detected_at_turn=5)
        assert ac.accused_process_id_hex == "22"
        assert ac.statement_id == "s03"
        assert ac.witness_digests == ("aa", "bb")
        assert ac.detected_at_turn == 5

    def test_rejects_non_alarm_payload(self):
        regular_claim = Claim(
            statement_id="s01", verdict="true", confidence=0.9,
            evidence="ok", timestamp_logical=0,
        )
        with pytest.raises(ValueError, match="not an AlarmClaim"):
            AlarmClaim.from_payload(regular_claim.to_payload())


class TestTallyAlarms:

    def test_collect_alarm_claims_finds_only_alarms(self):
        """Mixed-payload graphs: alarm claims are picked, regular claims skipped."""
        m = _full_run()
        for name in ("a", "b", "c"):
            collected = collect_alarm_claims(m.agents[name].graph)
            signers = {signer for signer, _ in collected}
            # The 3 honest agents have each emitted exactly one AlarmClaim
            assert len(signers) == 3

    def test_tally_meets_quorum(self):
        """3 honest detectors + threshold of 3 (ceil(2*4/3)) ⇒ ratified."""
        m = _full_run()
        # boundary size = 4 (3 honest + 1 byzantine joined)
        threshold = quorum_for(m.boundary.size())
        for name in ("a", "b", "c"):
            ratified = tally_alarms(m.agents[name].graph,
                                    quorum_threshold=threshold)
            assert len(ratified) == 1
            r = ratified[0]
            assert isinstance(r, RatifiedAlarm)
            assert r.statement_id == "s03"
            assert r.signer_count >= threshold
            assert r.quorum_threshold == threshold

    def test_tally_blocks_single_signer(self):
        """A single AlarmClaim cannot ratify on its own."""
        m = _full_run()
        # Force a high quorum (4 of 4): nothing should ratify.
        ratified = tally_alarms(m.agents["a"].graph, quorum_threshold=4)
        assert ratified == []

    def test_mothership_ratified_alarms_from_helper(self):
        """The convenience method on the mothership produces the same set
        as direct tallying."""
        m = _full_run()
        threshold = quorum_for(m.boundary.size())
        ratified_via_helper = m.ratified_alarms_from("a")
        ratified_direct = tally_alarms(m.agents["a"].graph,
                                       quorum_threshold=threshold)
        assert ratified_via_helper == ratified_direct
