"""The centerpiece: assert there is no privileged observer.

After the full lifecycle — closed phase, boundary open, equivocation, gossip,
alarm emission, alarm gossip — *every honest agent's* ratified-alarms set must
be identical. If we ever re-introduce a chokepoint (a single observer holding
state nobody else can see), this test should fail.
"""

from crisis_agents.agent import MockAgent, MockByzantineAgent
from crisis_agents.claim import Claim
from crisis_agents.mothership import Mothership


def _claim(sid: str, verdict: str = "true", evidence: str = "ok") -> Claim:
    return Claim(statement_id=sid, verdict=verdict, confidence=0.9,  # type: ignore[arg-type]
                 evidence=evidence, timestamp_logical=0)


def _intro(name: str = "delta") -> Claim:
    return Claim(statement_id=f"intro:{name}", verdict="unknown", confidence=1.0,
                 evidence=f"{name} joining the team", timestamp_logical=0)


def test_all_honest_agents_agree_on_ratified_alarms():
    m = Mothership()
    m.add_agent(MockAgent("a", [[]]))
    m.add_agent(MockAgent("b", [[]]))
    m.add_agent(MockAgent("c", [[]]))
    m.open_boundary(MockByzantineAgent(
        "d", _intro(),
        scripted_pairs=[(
            _claim("s03", verdict="true", evidence="to_ac"),
            _claim("s03", verdict="false", evidence="to_b"),
        )],
        split_a={"a", "c"},
        split_b={"b"},
    ))
    m.run_crisis_phase(num_turns=2, gossip_rounds_per_turn=1)
    m.emit_alarms_from_detectors()
    m.run_gossip_round()

    # The headline assertion: three independent vantage points; same result.
    ratified_per_agent = {
        name: m.ratified_alarms_from(name)
        for name in ("a", "b", "c")
    }

    assert ratified_per_agent["a"] == ratified_per_agent["b"]
    assert ratified_per_agent["b"] == ratified_per_agent["c"]
    assert len(ratified_per_agent["a"]) == 1


def test_no_chokepoint_attribute_on_mothership():
    """Smoke-check: the mothership doesn't expose any privileged collection
    of per-agent graphs. Each agent owns its own state.
    """
    m = Mothership()
    # If anyone re-adds these, the test fails loudly.
    for forbidden in ("all_graphs", "graph_of", "_graphs",
                      "scan_for_mutations", "detect_byzantine"):
        assert not hasattr(m, forbidden), (
            f"Mothership grew back a chokepoint: {forbidden}"
        )


def test_byzantine_alone_cannot_ratify():
    """If only the byzantine emits an AlarmClaim (against a fictitious target),
    no quorum is reached.
    """
    m = Mothership()
    m.add_agent(MockAgent("a", [[]]))
    m.add_agent(MockAgent("b", [[]]))
    m.add_agent(MockAgent("c", [[]]))
    # No equivocation script — boundary opens cleanly.
    m.open_boundary(MockByzantineAgent("d", _intro(), [], set(), set()))
    m.run_crisis_phase(num_turns=1, gossip_rounds_per_turn=1)
    m.emit_alarms_from_detectors()
    m.run_gossip_round()

    # No honest agent should have ratified anything.
    for name in ("a", "b", "c"):
        assert m.ratified_alarms_from(name) == []
