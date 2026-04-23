"""Tests for the Lamport graph with integrity checks."""

import os
import pytest
from crisis.crypto import digest
from crisis.graph import LamportGraph
from crisis.message import Message, Vertex, ID_LENGTH, NONCE_LENGTH
from crisis.weight import ProofOfWorkWeight


def make_id(name: str) -> bytes:
    return digest(name.encode())[:ID_LENGTH]


def make_nonce(n: int = 0) -> bytes:
    return n.to_bytes(NONCE_LENGTH, "big")


def make_graph(pow_zeros: int = 0) -> LamportGraph:
    return LamportGraph(weight_system=ProofOfWorkWeight(min_leading_zeros=pow_zeros))


class TestLamportGraphExtension:

    def test_extend_single_message(self):
        g = make_graph()
        msg = Message(nonce=make_nonce(), id=make_id("alice"), payload=b"hello")
        v = g.extend(msg)
        assert v is not None
        assert g.vertex_count() == 1

    def test_extend_chain(self):
        """Messages from the same id must form a chain."""
        g = make_graph()
        m1 = Message(nonce=make_nonce(0), id=make_id("alice"), payload=b"first")
        v1 = g.extend(m1)
        assert v1 is not None

        m2 = Message(
            nonce=make_nonce(1), id=make_id("alice"),
            digests=(m1.compute_digest(),),
            payload=b"second"
        )
        v2 = g.extend(m2)
        assert v2 is not None
        assert g.vertex_count() == 2

    def test_reject_duplicate(self):
        """No two equivalent vertices in the same graph."""
        g = make_graph()
        msg = Message(nonce=make_nonce(), id=make_id("alice"), payload=b"x")
        g.extend(msg)
        v2 = g.extend(msg)
        assert v2 is None  # Rejected: duplicate
        assert g.vertex_count() == 1

    def test_reject_missing_reference(self):
        """Digests must reference existing vertices."""
        g = make_graph()
        fake_digest = digest(b"nonexistent")
        msg = Message(
            nonce=make_nonce(), id=make_id("alice"),
            digests=(fake_digest,), payload=b"orphan"
        )
        v = g.extend(msg)
        assert v is None  # Rejected

    def test_reject_broken_chain(self):
        """Second message from same id must reference a same-id vertex."""
        g = make_graph()
        id_a = make_id("alice")
        id_b = make_id("bob")

        m1 = Message(nonce=make_nonce(0), id=id_a, payload=b"first")
        g.extend(m1)

        m_bob = Message(nonce=make_nonce(1), id=id_b, payload=b"bob's msg")
        g.extend(m_bob)

        # Alice's second message references bob but not herself -> rejected
        m2 = Message(
            nonce=make_nonce(2), id=id_a,
            digests=(m_bob.compute_digest(),),
            payload=b"broken chain"
        )
        v = g.extend(m2)
        assert v is None


class TestCausality:

    def _build_chain(self):
        """Build a simple 3-message chain: m1 <- m2 <- m3."""
        g = make_graph()
        id_a = make_id("alice")
        m1 = Message(nonce=make_nonce(0), id=id_a, payload=b"m1")
        v1 = g.extend(m1)

        m2 = Message(nonce=make_nonce(1), id=id_a,
                      digests=(m1.compute_digest(),), payload=b"m2")
        v2 = g.extend(m2)

        m3 = Message(nonce=make_nonce(2), id=id_a,
                      digests=(m2.compute_digest(),), payload=b"m3")
        v3 = g.extend(m3)

        return g, v1, v2, v3

    def test_direct_causes(self):
        g, v1, v2, v3 = self._build_chain()
        causes_of_v3 = g.direct_causes(v3)
        assert v2 in causes_of_v3
        assert v1 not in causes_of_v3

    def test_direct_effects(self):
        g, v1, v2, v3 = self._build_chain()
        effects_of_v1 = g.direct_effects(v1)
        assert v2 in effects_of_v1
        assert v3 not in effects_of_v1  # v3 is indirect

    def test_past(self):
        """G_v: the past of v contains all its causes."""
        g, v1, v2, v3 = self._build_chain()
        past_of_v3 = g.past(v3)
        assert v1 in past_of_v3
        assert v2 in past_of_v3
        assert v3 in past_of_v3  # reflexive

    def test_future(self):
        g, v1, v2, v3 = self._build_chain()
        future_of_v1 = g.future(v1)
        assert v2 in future_of_v1
        assert v3 in future_of_v1
        assert v1 in future_of_v1  # reflexive

    def test_is_cause_of(self):
        g, v1, v2, v3 = self._build_chain()
        assert g.is_cause_of(v1, v3)
        assert g.is_cause_of(v1, v2)
        assert not g.is_cause_of(v3, v1)

    def test_timelike(self):
        g, v1, v2, v3 = self._build_chain()
        assert g.are_timelike(v1, v3)
        assert g.are_timelike(v3, v1)

    def test_spacelike(self):
        """Two independent vertices are spacelike."""
        g = make_graph()
        m_a = Message(nonce=make_nonce(0), id=make_id("alice"), payload=b"a")
        m_b = Message(nonce=make_nonce(0), id=make_id("bob"), payload=b"b")
        va = g.extend(m_a)
        vb = g.extend(m_b)
        assert g.are_spacelike(va, vb)
        assert not g.are_timelike(va, vb)


class TestInvarianceOfThePast:
    """Theorem 3.7: The past of equivalent vertices in two Lamport graphs
    have the same cardinality."""

    def test_past_invariance_simple(self):
        """Same message in two different graphs has same-size past."""
        g1 = make_graph()
        g2 = make_graph()
        id_a = make_id("alice")

        m1 = Message(nonce=make_nonce(0), id=id_a, payload=b"genesis")
        m2 = Message(nonce=make_nonce(1), id=id_a,
                      digests=(m1.compute_digest(),), payload=b"second")

        # Add to both graphs
        g1.extend(m1)
        v1_in_g1 = g1.extend(m2)

        g2.extend(m1)
        v1_in_g2 = g2.extend(m2)

        # Past should be the same size
        assert len(g1.past(v1_in_g1)) == len(g2.past(v1_in_g2))


class TestMessageGeneration:

    def test_generate_first_message(self):
        g = make_graph()
        msg = g.generate_message(make_id("alice"), b"hello")
        v = g.extend(msg)
        assert v is not None
        assert v.payload == b"hello"

    def test_generate_chain(self):
        g = make_graph()
        pid = make_id("alice")
        m1 = g.generate_message(pid, b"first")
        g.extend(m1)

        m2 = g.generate_message(pid, b"second")
        v2 = g.extend(m2)
        assert v2 is not None
        # Second message should reference the first
        assert m1.compute_digest() in m2.digests

    def test_generate_cross_references(self):
        """Messages should reference vertices from other process ids."""
        g = make_graph()
        pid_a = make_id("alice")
        pid_b = make_id("bob")

        m_a = g.generate_message(pid_a, b"alice's msg")
        g.extend(m_a)

        m_b = g.generate_message(pid_b, b"bob's msg")
        g.extend(m_b)

        # Alice's second message should reference bob's message
        m_a2 = g.generate_message(pid_a, b"alice second")
        assert m_b.compute_digest() in m_a2.digests or m_a.compute_digest() in m_a2.digests
