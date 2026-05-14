"""Tests for the slimmed-down Mothership (bootstrap + clock + routing only)."""

import pytest

from crisis_agents.agent import MockAgent, MockByzantineAgent
from crisis_agents.claim import Claim
from crisis_agents.mothership import Mothership


def _claim(sid: str, verdict: str = "true", evidence: str = "ok") -> Claim:
    return Claim(statement_id=sid, verdict=verdict, confidence=0.9,  # type: ignore[arg-type]
                 evidence=evidence, timestamp_logical=0)


def _intro(name: str = "delta") -> Claim:
    """A benign 'I have joined' claim for the byzantine's first turn."""
    return Claim(statement_id=f"intro:{name}", verdict="unknown", confidence=1.0,
                 evidence=f"{name} joining the team", timestamp_logical=0)


class TestClosedPhase:

    def test_no_dag_in_closed_phase_for_active_agents(self):
        """In the closed phase, agents don't extend their graphs."""
        m = Mothership()
        m.add_agent(MockAgent("a", [[_claim("s01")]]))
        m.add_agent(MockAgent("b", [[_claim("s01")]]))
        report = m.run_closed_phase()

        # Two agents emitted one claim each via the closed-phase log
        assert len(m.run_result.closed_log) == 2
        # The async loop reached quiescence within the step budget
        assert report.reached_quiescence
        assert report.emissions == 2

        # No Crisis messages sent yet, so per-agent graphs are still empty
        for agent in m.agents.values():
            assert agent.graph.vertex_count() == 0

        assert not m.boundary.is_open

    def test_add_agent_after_open_rejected(self):
        m = Mothership()
        m.add_agent(MockAgent("a", [[_claim("s01")]]))
        m.open_boundary(MockByzantineAgent("byz", _intro("byz"), [], set(), set()))
        with pytest.raises(RuntimeError, match="cannot add_agent"):
            m.add_agent(MockAgent("late", []))


class TestCrisisPhaseAgentOwnership:

    def test_each_agent_owns_its_graph(self):
        """After open_boundary every agent has its own LamportGraph."""
        m = Mothership()
        m.add_agent(MockAgent("a", [[]]))
        m.add_agent(MockAgent("b", [[]]))
        joiner = MockByzantineAgent("d", _intro(), [], set(), set())
        m.open_boundary(joiner)

        # Each agent has a graph attribute, and they're distinct objects
        graphs = [a.graph for a in m.agents.values()]
        assert len(graphs) == 3
        assert len({id(g) for g in graphs}) == 3   # distinct identity
        for g in graphs:
            assert g.vertex_count() == 0

    def test_broadcast_emission_reaches_every_agent(self):
        """A target_subset=None emission ends up in every peer's graph."""
        m = Mothership()
        m.add_agent(MockAgent("a", [[]]))
        m.add_agent(MockAgent("b", [[]]))
        # Joiner with a single broadcast intro, no equivocation script
        joiner = MockByzantineAgent("d", _intro(), [], set(), set())
        m.open_boundary(joiner)
        m.run_until_quiescent()

        for name, agent in m.agents.items():
            assert agent.graph.vertex_count() == 1, (
                f"agent {name!r} should have received the intro broadcast"
            )

    def test_targeted_emission_seeds_disjoint_views(self):
        """After the async loop with gossip, every honest agent sees both
        variants — but the byzantine itself never has both in its own graph
        (it never re-receives its own targeted emissions, and gossip from
        honest peers may or may not feed them back).

        The protocol-level invariant: the byzantine's two contradictory
        vertices end up reachable to every honest agent. THAT is what
        decentralized detection depends on.
        """
        m = Mothership()
        m.add_agent(MockAgent("a", [[]]))
        m.add_agent(MockAgent("b", [[]]))
        byz = MockByzantineAgent(
            "d", _intro(),
            scripted_pairs=[(
                _claim("s03", verdict="true", evidence="to_a"),
                _claim("s03", verdict="false", evidence="to_b"),
            )],
            split_a={"a"},
            split_b={"b"},
        )
        m.open_boundary(byz)
        m.run_until_quiescent()

        # Every honest agent's graph has both variants of the equivocation
        # (the post-condition that lets decentralized detection work).
        for name in ("a", "b"):
            payloads = [v.payload for v in m.agents[name].graph.all_vertices()]
            assert any(b'"verdict":"true"' in p for p in payloads), (
                f"agent {name!r} missing the true-variant"
            )
            assert any(b'"verdict":"false"' in p for p in payloads), (
                f"agent {name!r} missing the false-variant"
            )


class TestGossipRound:

    def test_gossip_propagates_byzantine_equivocation(self):
        """After one gossip round, every honest agent has both variants —
        the prerequisite for decentralized detection."""
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
        # Two turns (intro + equivocation), then gossip
        m.run_until_quiescent()

        # After gossip, every honest agent should have both byzantine variants
        # (intro + 2 equivocations = 3 vertices minimum). The byzantine itself
        # ends up with intro + everything its peers shared back.
        for name in ("a", "b", "c"):
            payloads = [v.payload for v in m.agents[name].graph.all_vertices()]
            assert any(b'"verdict":"true"' in p for p in payloads), (
                f"agent {name!r} missing the true-variant after gossip"
            )
            assert any(b'"verdict":"false"' in p for p in payloads), (
                f"agent {name!r} missing the false-variant after gossip"
            )

    def test_mothership_doesnt_hold_a_graph_dict(self):
        """Regression guard against the chokepoint we just removed."""
        m = Mothership()
        # The old API exposed `m.all_graphs()` and `m.graph_of(name)`.
        # Neither should exist now.
        assert not hasattr(m, "all_graphs")
        assert not hasattr(m, "graph_of")
        assert not hasattr(m, "_graphs")

    def test_run_crisis_phase_requires_open_boundary(self):
        m = Mothership()
        m.add_agent(MockAgent("a", [[_claim("s01")]]))
        with pytest.raises(RuntimeError, match="boundary not yet open"):
            m.run_until_quiescent()
