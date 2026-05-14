"""Tests for decentralized mutation detection.

Each agent's `detect_mutations()` is called on its own graph. There is no
mothership-side scan.
"""

from crisis_agents.agent import MockAgent, MockByzantineAgent
from crisis_agents.alarm import LocalAlarm, detect_mutations_in_graph
from crisis_agents.claim import Claim
from crisis_agents.mothership import Mothership


def _claim(sid: str, verdict: str = "true", evidence: str = "ok") -> Claim:
    return Claim(statement_id=sid, verdict=verdict, confidence=0.9,  # type: ignore[arg-type]
                 evidence=evidence, timestamp_logical=0)


def _intro(name: str = "delta") -> Claim:
    return Claim(statement_id=f"intro:{name}", verdict="unknown", confidence=1.0,
                 evidence=f"{name} joining the team", timestamp_logical=0)


def _post_gossip_team() -> Mothership:
    """3 honest + 1 byzantine; equivocation; one gossip round so every
    honest agent has both variants in its own graph."""
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
    return m


class TestDecentralizedDetection:

    def test_no_alarms_in_honest_run(self):
        m = Mothership()
        m.add_agent(MockAgent("a", [[]]))
        m.add_agent(MockAgent("b", [[]]))
        joiner = MockByzantineAgent("d", _intro(), [], set(), set())
        m.open_boundary(joiner)
        m.run_crisis_phase(num_turns=1, gossip_rounds_per_turn=1)

        # Every agent's own detection returns empty
        for agent in m.agents.values():
            assert agent.detect_mutations() == []

    def test_each_honest_agent_detects_the_same_mutation(self):
        """The key decentralization property."""
        m = _post_gossip_team()
        for name in ("a", "b", "c"):
            alarms = m.agents[name].detect_mutations()
            assert len(alarms) == 1
            assert alarms[0].statement_id == "s03"
            assert alarms[0].detector_name == name
            # Both honest detectors agree on the canonical witness pair
            assert alarms[0].witness_digests[0] != alarms[0].witness_digests[1]

    def test_byzantine_does_not_detect_its_own_equivocation(self):
        """An agent never accuses itself."""
        m = _post_gossip_team()
        # The byzantine ended up with both equivocating variants in its
        # own graph (via gossip-back from honest peers). Its detect should
        # still return empty because it skips its own process id.
        d_alarms = m.agents["d"].detect_mutations()
        assert d_alarms == []

    def test_all_honest_detectors_produce_canonical_witness_pairs(self):
        """Three independent detectors must agree on the witness digest pair
        (sorted hex) so their AlarmClaims can be voted together."""
        m = _post_gossip_team()
        pairs = set()
        for name in ("a", "b", "c"):
            local = m.agents[name].detect_mutations()
            assert len(local) == 1
            pairs.add(local[0].witness_digests)
        assert len(pairs) == 1, "detectors disagree on the witness pair"


class TestDirectDetectionFunction:
    """The function detect_mutations_in_graph is the heart of detection;
    test it directly on a constructed graph too."""

    def test_returns_LocalAlarm_instances(self):
        m = _post_gossip_team()
        alarms = detect_mutations_in_graph(
            m.agents["a"].graph,
            detector_name="a",
            detector_process_id=m.agents["a"].process_id,
        )
        assert all(isinstance(a, LocalAlarm) for a in alarms)
