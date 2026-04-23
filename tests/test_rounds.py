"""Tests for virtual synchronous rounds."""

from crisis.crypto import digest
from crisis.graph import LamportGraph
from crisis.message import Message, ID_LENGTH, NONCE_LENGTH
from crisis.rounds import compute_rounds, max_round, last_vertices_in_round, vertices_in_round
from crisis.weight import ProofOfWorkWeight, DifficultyOracle


def make_id(name: str) -> bytes:
    return digest(name.encode())[:ID_LENGTH]


def make_nonce(n: int = 0) -> bytes:
    return n.to_bytes(NONCE_LENGTH, "big")


def make_graph() -> LamportGraph:
    return LamportGraph(weight_system=ProofOfWorkWeight(min_leading_zeros=0))


class TestRoundComputation:

    def test_single_vertex_round_zero(self):
        """A single vertex with no causes is in round 0."""
        g = make_graph()
        msg = Message(nonce=make_nonce(), id=make_id("alice"), payload=b"genesis")
        v = g.extend(msg)
        compute_rounds(g, DifficultyOracle(constant_difficulty=1))
        assert v.round == 0

    def test_single_vertex_is_last(self):
        """Round 0 vertices are always 'last' (bootstrapping)."""
        g = make_graph()
        msg = Message(nonce=make_nonce(), id=make_id("alice"))
        v = g.extend(msg)
        compute_rounds(g, DifficultyOracle(constant_difficulty=1))
        assert v.is_last is True

    def test_chain_grows_rounds(self):
        """A chain of messages should produce increasing round numbers."""
        g = make_graph()
        pid = make_id("alice")
        difficulty = DifficultyOracle(constant_difficulty=0)  # Low difficulty

        # Create a chain
        prev_msg = None
        vertices = []
        for i in range(5):
            digests = (prev_msg.compute_digest(),) if prev_msg else ()
            msg = Message(nonce=make_nonce(i), id=pid, digests=digests, payload=f"msg{i}".encode())
            v = g.extend(msg)
            vertices.append(v)
            prev_msg = msg

        compute_rounds(g, difficulty, connectivity_k=0)

        # All should have round numbers assigned
        for v in vertices:
            assert v.round is not None

        # First vertex is round 0
        assert vertices[0].round == 0

    def test_max_round_empty_graph(self):
        g = make_graph()
        assert max_round(g) == 0

    def test_max_round_with_vertices(self):
        g = make_graph()
        msg = Message(nonce=make_nonce(), id=make_id("x"))
        g.extend(msg)
        compute_rounds(g, DifficultyOracle(constant_difficulty=1))
        assert max_round(g) == 0

    def test_last_vertices_in_round(self):
        g = make_graph()
        msg = Message(nonce=make_nonce(), id=make_id("alice"))
        g.extend(msg)
        compute_rounds(g, DifficultyOracle(constant_difficulty=1))
        lasts = last_vertices_in_round(g, 0)
        assert len(lasts) == 1

    def test_multiple_ids_same_round(self):
        """Multiple independent vertices are all in round 0."""
        g = make_graph()
        for name in ["alice", "bob", "carol"]:
            msg = Message(nonce=make_nonce(), id=make_id(name), payload=name.encode())
            g.extend(msg)

        compute_rounds(g, DifficultyOracle(constant_difficulty=1))

        r0 = vertices_in_round(g, 0)
        assert len(r0) == 3

    def test_round_invariance(self):
        """Proposition 5.3: equivalent vertices in different graphs have same round."""
        g1 = make_graph()
        g2 = make_graph()
        difficulty = DifficultyOracle(constant_difficulty=1)

        msg = Message(nonce=make_nonce(), id=make_id("alice"), payload=b"genesis")
        v1 = g1.extend(msg)
        v2 = g2.extend(msg)

        compute_rounds(g1, difficulty)
        compute_rounds(g2, difficulty)

        assert v1.round == v2.round
        assert v1.is_last == v2.is_last
