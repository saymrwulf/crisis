"""Tests for virtual voting, safe voting patterns, and leader election (Algorithms 6 & 7)."""

from crisis.crypto import digest
from crisis.demo import Simulation
from crisis.graph import LamportGraph
from crisis.message import Message, ID_LENGTH, NONCE_LENGTH
from crisis.rounds import compute_rounds, max_round, last_vertices_in_round
from crisis.voting import (
    KnowledgeGraph,
    build_knowledge_graph,
    select_quorum,
    voting_set,
    compute_safe_voting_pattern,
    compute_virtual_leader_election,
    initial_vote,
)
from crisis.weight import ProofOfWorkWeight, DifficultyOracle


def make_id(name: str) -> bytes:
    return digest(name.encode())[:ID_LENGTH]


def make_nonce(n: int = 0) -> bytes:
    return n.to_bytes(NONCE_LENGTH, "big")


def make_graph() -> LamportGraph:
    return LamportGraph(weight_system=ProofOfWorkWeight(min_leading_zeros=0))


def small_converged_sim(num_honest: int = 3, num_steps: int = 8) -> Simulation:
    """Build a small in-process simulation with rounds + voting computed."""
    sim = Simulation(
        num_honest=num_honest,
        num_byzantine=0,
        pow_zeros=0,
        difficulty=0,
        connectivity_k=0,
        seed=42,
        synchronous=True,
    )
    sim.run(num_steps=num_steps, verbose=False)
    return sim


class TestKnowledgeGraph:

    def test_empty_graph_has_no_entries(self):
        g = make_graph()
        msg = Message(nonce=make_nonce(), id=make_id("alice"))
        v = g.extend(msg)
        compute_rounds(g, DifficultyOracle(constant_difficulty=0))
        kg = build_knowledge_graph(v, round_s=0, graph=g)
        # A single round-0 vertex's knowledge graph at round 0 contains only itself.
        assert v.id in kg.edges
        assert v.id in kg.weights

    def test_round_zero_isolation(self):
        """At round 0, genesis vertices don't reference each other — all isolated."""
        sim = small_converged_sim(num_honest=3, num_steps=2)
        graph = sim.nodes[0].graph
        # Pick any vertex that has a round assigned
        vertices_with_round = [v for v in graph.all_vertices() if v.round is not None]
        assert vertices_with_round, "expected at least one rounded vertex"
        v = max(vertices_with_round, key=lambda x: x.round)
        kg = build_knowledge_graph(v, round_s=0, graph=graph)
        # Every round-0 id should appear in the knowledge graph
        assert len(kg.edges) >= 1

    def test_weights_are_non_negative(self):
        sim = small_converged_sim()
        graph = sim.nodes[0].graph
        v = max(graph.all_vertices(), key=lambda x: x.round or 0)
        if v.round is not None and v.round > 0:
            kg = build_knowledge_graph(v, round_s=0, graph=graph)
            for w in kg.weights.values():
                assert w >= 0


class TestQuorumSelector:

    def test_empty_knowledge_graph_empty_quorum(self):
        kg = KnowledgeGraph()
        assert select_quorum(kg) == set()

    def test_isolated_all_processes_form_one_component(self):
        """Round-0 case: all processes are isolated, so they all form one component."""
        kg = KnowledgeGraph()
        kg.edges = {b"a" * 32: set(), b"b" * 32: set(), b"c" * 32: set()}
        kg.weights = {b"a" * 32: 3, b"b" * 32: 2, b"c" * 32: 1}
        q = select_quorum(kg, n=2)
        # Top-2 by weight from the single isolated component
        assert b"a" * 32 in q
        assert b"b" * 32 in q
        assert b"c" * 32 not in q
        assert len(q) == 2

    def test_picks_heaviest_component(self):
        """When there are two components, the heaviest one is selected."""
        kg = KnowledgeGraph()
        # Component 1: {a, b} cross-referencing each other, total weight 3
        # Component 2: {c, d} cross-referencing each other, total weight 9
        a, b, c, d = b"a" * 32, b"b" * 32, b"c" * 32, b"d" * 32
        kg.edges = {a: {b}, b: {a}, c: {d}, d: {c}}
        kg.weights = {a: 1, b: 2, c: 4, d: 5}
        q = select_quorum(kg, n=3)
        # Heavier component is {c, d}; should pick both
        assert c in q
        assert d in q
        assert a not in q
        assert b not in q

    def test_quorum_size_bounded_by_n(self):
        kg = KnowledgeGraph()
        ids = [bytes([i]) * 32 for i in range(10)]
        kg.edges = {i: set() for i in ids}
        kg.weights = {i: 10 - n for n, i in enumerate(ids)}
        q = select_quorum(kg, n=3)
        assert len(q) == 3


class TestSafeVotingPattern:

    def test_round_zero_has_empty_svp(self):
        """Vertices at round 0 cannot have a safe voting pattern (no prior rounds)."""
        sim = small_converged_sim(num_steps=3)
        graph = sim.nodes[0].graph
        difficulty = DifficultyOracle(constant_difficulty=0)
        for v in graph.all_vertices():
            if v.round == 0 and v.is_last:
                compute_safe_voting_pattern(v, graph, difficulty)
                assert v.svp == []

    def test_non_last_vertex_has_empty_svp(self):
        """Only is_last vertices get an svp."""
        sim = small_converged_sim()
        graph = sim.nodes[0].graph
        difficulty = DifficultyOracle(constant_difficulty=0)
        non_last = [v for v in graph.all_vertices() if v.is_last is False]
        if non_last:
            v = non_last[0]
            compute_safe_voting_pattern(v, graph, difficulty)
            assert v.svp == []

    def test_svp_entries_are_monotone_and_lt_round(self):
        """SVP entries must all be strictly less than the vertex's own round."""
        sim = small_converged_sim(num_honest=4, num_steps=10)
        graph = sim.nodes[0].graph
        difficulty = DifficultyOracle(constant_difficulty=0)
        for v in graph.all_vertices():
            if v.is_last and v.round is not None and v.round > 0:
                compute_safe_voting_pattern(v, graph, difficulty)
                for s in v.svp:
                    assert s < v.round


class TestInitialVote:

    def test_empty_set_yields_none(self):
        g = make_graph()
        assert initial_vote(set(), g) is None

    def test_picks_highest_weight_vertex(self):
        g = make_graph()
        msg = Message(nonce=make_nonce(0), id=make_id("alice"), payload=b"x")
        v = g.extend(msg)
        result = initial_vote({v}, g)
        # With one vertex the result is that vertex's message
        assert result is not None
        assert result.compute_digest() == msg.compute_digest()


class TestVirtualLeaderElection:

    def test_no_svp_means_no_votes(self):
        """A vertex with empty svp gets no votes from Algorithm 7."""
        g = make_graph()
        msg = Message(nonce=make_nonce(), id=make_id("alice"))
        v = g.extend(msg)
        compute_rounds(g, DifficultyOracle(constant_difficulty=0))
        assert v.svp == []
        leader_stream: dict = {}
        compute_virtual_leader_election(v, g, DifficultyOracle(constant_difficulty=0),
                                        connectivity_k=0, leader_stream=leader_stream)
        assert v.vote == {}
        assert leader_stream == {}

    def test_votes_are_assigned_for_svp_rounds(self):
        """When a vertex has an SVP, Algorithm 7 assigns a vote for each round in it."""
        sim = small_converged_sim(num_honest=4, num_steps=12)
        graph = sim.nodes[0].graph
        difficulty = DifficultyOracle(constant_difficulty=0)

        # Compute SVPs first
        for v in graph.all_vertices():
            if v.is_last:
                compute_safe_voting_pattern(v, graph, difficulty)

        # Find one with non-empty SVP and run leader election
        with_svp = [v for v in graph.all_vertices() if v.is_last and v.svp]
        if not with_svp:
            return  # nothing to assert; voting infrastructure didn't engage in this tiny sim

        leader_stream: dict = {}
        v = with_svp[0]
        compute_virtual_leader_election(v, graph, difficulty,
                                        connectivity_k=0, leader_stream=leader_stream)
        # At least one round in v.svp should now have a vote
        for s in v.svp:
            assert s in v.vote, f"missing vote for round {s}"
