"""Tests for the Mothership orchestrator — closed phase + Crisis-phase wiring."""

import pytest

from crisis_agents.agent import MockAgent, MockByzantineAgent
from crisis_agents.claim import Claim
from crisis_agents.mothership import Mothership


def _claim(sid: str, verdict: str = "true", turn: int = 0, evidence: str = "ok") -> Claim:
    return Claim(
        statement_id=sid, verdict=verdict, confidence=0.9,  # type: ignore[arg-type]
        evidence=evidence, timestamp_logical=turn,
    )


class TestClosedPhase:

    def test_no_dag_in_closed_phase(self):
        m = Mothership()
        m.add_agent(MockAgent("a", [[_claim("s01")]]))
        m.add_agent(MockAgent("b", [[_claim("s01")]]))
        result = m.run_closed_phase(num_turns=1)

        # Two agents emitted one claim each
        assert len(result.closed_log) == 2
        names = [e.agent_name for e in result.closed_log]
        assert "a" in names and "b" in names

        # No graphs allocated
        assert m.all_graphs() == {}
        assert not m.boundary.is_open

    def test_multi_turn_observes_prior_claims(self):
        """Each turn's agents see the claims emitted in previous turns."""
        class WatcherAgent(MockAgent):
            def __init__(self, name):
                super().__init__(name, [[_claim("s01")], [_claim("s02")]])
                self.received_per_turn: list[int] = []

            def next_turn(self, turn, received):
                self.received_per_turn.append(len(received))
                return super().next_turn(turn, received)

        w = WatcherAgent("watcher")
        other = MockAgent("other", [[_claim("s99")], [_claim("s99")]])
        m = Mothership()
        m.add_agent(w)
        m.add_agent(other)
        m.run_closed_phase(num_turns=2)
        # Turn 0: watcher sees 0 prior claims; Turn 1: watcher sees 2 from turn 0.
        assert w.received_per_turn == [0, 2]

    def test_add_agent_after_open_rejected(self):
        m = Mothership()
        m.add_agent(MockAgent("a", [[_claim("s01")]]))
        m.open_boundary(MockAgent("byz", [[_claim("s01")]]))
        with pytest.raises(RuntimeError, match="cannot add_agent"):
            m.add_agent(MockAgent("late", []))


class TestCrisisPhaseWiring:

    def test_open_boundary_initializes_graphs(self):
        m = Mothership()
        m.add_agent(MockAgent("a", [[_claim("s01")]]))
        m.add_agent(MockAgent("b", [[_claim("s01")]]))
        m.open_boundary(MockAgent("d", [[_claim("s01")]]))

        # One graph per agent, including the joiner
        graphs = m.all_graphs()
        assert set(graphs.keys()) == {"a", "b", "d"}
        for g in graphs.values():
            assert g.vertex_count() == 0  # not yet run

    def test_run_crisis_phase_extends_per_agent_graphs(self):
        m = Mothership()
        m.add_agent(MockAgent("a", [[_claim("s01")]]))
        m.add_agent(MockAgent("b", [[_claim("s01")]]))
        m.open_boundary(MockAgent("d", [[_claim("s01")]]))
        result = m.run_crisis_phase(num_turns=1)

        # Each agent's graph should now contain three vertices
        # (broadcast claims from a, b, d delivered to everyone).
        for name in ("a", "b", "d"):
            assert m.graph_of(name).vertex_count() == 3

        assert len(result.crisis_log) == 3
        for entry in result.crisis_log:
            assert set(entry.delivered_to) == {"a", "b", "d"}

    def test_byzantine_equivocation_splits_delivery(self):
        """A MockByzantineAgent delivers two different claims to disjoint
        subsets — the foundation of the equivocation detection demo."""
        m = Mothership()
        m.add_agent(MockAgent("a", [[]]))
        m.add_agent(MockAgent("b", [[]]))

        byz = MockByzantineAgent(
            "d",
            scripted_pairs=[(
                _claim("s01", verdict="true", evidence="to_a"),
                _claim("s01", verdict="false", evidence="to_b"),
            )],
            split_a={"a"},
            split_b={"b"},
        )
        m.open_boundary(byz)
        m.run_crisis_phase(num_turns=1)

        # a sees the true-variant, b sees the false-variant.
        # d (the byzantine sender) sees neither — see Mothership._emit docstring.
        a_payloads = [v.payload for v in m.graph_of("a").all_vertices()]
        b_payloads = [v.payload for v in m.graph_of("b").all_vertices()]
        d_payloads = [v.payload for v in m.graph_of("d").all_vertices()]

        assert any(b'"verdict":"true"' in p for p in a_payloads)
        assert all(b'"verdict":"false"' not in p for p in a_payloads)

        assert any(b'"verdict":"false"' in p for p in b_payloads)
        assert all(b'"verdict":"true"' not in p for p in b_payloads)

        # d's own graph holds neither equivocation (targeted delivery skips sender).
        assert len(d_payloads) == 0

        # But the crisis_log records both emissions so the mothership can
        # generate proofs from this perspective.
        assert len(m.run_result.crisis_log) == 2

    def test_run_crisis_phase_requires_open_boundary(self):
        m = Mothership()
        m.add_agent(MockAgent("a", [[_claim("s01")]]))
        with pytest.raises(RuntimeError, match="boundary not yet open"):
            m.run_crisis_phase(num_turns=1)
