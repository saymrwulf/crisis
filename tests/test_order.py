"""Tests for total order computation."""

from crisis.crypto import digest
from crisis.graph import LamportGraph
from crisis.message import Message, ID_LENGTH, NONCE_LENGTH
from crisis.order import LeaderStream, compute_order, _kahns_total_order
from crisis.weight import ProofOfWorkWeight


def make_id(name: str) -> bytes:
    return digest(name.encode())[:ID_LENGTH]


def make_nonce(n: int = 0) -> bytes:
    return n.to_bytes(NONCE_LENGTH, "big")


def make_graph() -> LamportGraph:
    return LamportGraph(weight_system=ProofOfWorkWeight(min_leading_zeros=0))


class TestLeaderStream:

    def test_empty_stream(self):
        ls = LeaderStream()
        assert ls.max_round() == -1
        assert ls.get_leader(0) is None

    def test_add_leader(self):
        ls = LeaderStream()
        msg = Message(nonce=make_nonce(), id=make_id("leader"), payload=b"L")
        updated = ls.update(0, 1, msg)
        assert updated is True
        assert ls.get_leader(0) is msg

    def test_higher_deciding_round_replaces(self):
        ls = LeaderStream()
        m1 = Message(nonce=make_nonce(1), id=make_id("l1"), payload=b"old")
        m2 = Message(nonce=make_nonce(2), id=make_id("l2"), payload=b"new")

        ls.update(0, 1, m1)
        ls.update(0, 2, m2)

        assert ls.get_leader(0) is m2

    def test_lower_deciding_round_rejected(self):
        ls = LeaderStream()
        m1 = Message(nonce=make_nonce(1), id=make_id("l1"), payload=b"first")
        m2 = Message(nonce=make_nonce(2), id=make_id("l2"), payload=b"late")

        ls.update(0, 5, m1)
        updated = ls.update(0, 3, m2)

        assert updated is False
        assert ls.get_leader(0) is m1

    def test_all_leaders_sorted(self):
        ls = LeaderStream()
        m0 = Message(nonce=make_nonce(0), id=make_id("l0"), payload=b"r0")
        m1 = Message(nonce=make_nonce(1), id=make_id("l1"), payload=b"r1")
        m2 = Message(nonce=make_nonce(2), id=make_id("l2"), payload=b"r2")

        ls.update(2, 3, m2)
        ls.update(0, 1, m0)
        ls.update(1, 2, m1)

        leaders = ls.all_leaders()
        rounds = [r for r, _ in leaders]
        assert rounds == sorted(rounds)


class TestKahnsAlgorithm:

    def test_empty_input(self):
        g = make_graph()
        result = _kahns_total_order([], g)
        assert result == []

    def test_single_vertex(self):
        g = make_graph()
        msg = Message(nonce=make_nonce(), id=make_id("x"), payload=b"only")
        v = g.extend(msg)
        result = _kahns_total_order([v], g)
        assert result == [v]

    def test_chain_order(self):
        """A chain should be ordered causes-first."""
        g = make_graph()
        pid = make_id("alice")
        m1 = Message(nonce=make_nonce(0), id=pid, payload=b"first")
        v1 = g.extend(m1)

        m2 = Message(nonce=make_nonce(1), id=pid,
                      digests=(m1.compute_digest(),), payload=b"second")
        v2 = g.extend(m2)

        m3 = Message(nonce=make_nonce(2), id=pid,
                      digests=(m2.compute_digest(),), payload=b"third")
        v3 = g.extend(m3)

        result = _kahns_total_order([v1, v2, v3], g)
        # Causes come first
        assert result.index(v1) < result.index(v2)
        assert result.index(v2) < result.index(v3)

    def test_respects_causality(self):
        """Total order must be consistent with causal order."""
        g = make_graph()
        m_a = Message(nonce=make_nonce(0), id=make_id("alice"), payload=b"a")
        va = g.extend(m_a)

        m_b = Message(nonce=make_nonce(0), id=make_id("bob"), payload=b"b")
        vb = g.extend(m_b)

        # Carol references both alice and bob
        m_c = Message(
            nonce=make_nonce(1), id=make_id("carol"),
            digests=(m_a.compute_digest(), m_b.compute_digest()),
            payload=b"c"
        )
        vc = g.extend(m_c)

        result = _kahns_total_order([va, vb, vc], g)
        # Carol must come after both alice and bob
        assert result.index(va) < result.index(vc)
        assert result.index(vb) < result.index(vc)
