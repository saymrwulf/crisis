"""Tests for the message and vertex data structures."""

import pytest
from crisis.crypto import digest, DIGEST_LENGTH
from crisis.message import (
    Message, Vertex, Vote,
    NONCE_LENGTH, ID_LENGTH, NUM_DIGESTS_LENGTH,
    EMPTY_MESSAGE_DIGEST,
)


def make_id(name: str) -> bytes:
    return digest(name.encode())[:ID_LENGTH]


def make_nonce(n: int = 0) -> bytes:
    return n.to_bytes(NONCE_LENGTH, "big")


class TestMessage:

    def test_create_minimal_message(self):
        msg = Message(nonce=make_nonce(), id=make_id("test"), digests=(), payload=b"")
        assert msg.num_digests == 0

    def test_nonce_length_validation(self):
        with pytest.raises(ValueError, match="nonce"):
            Message(nonce=b"\x00", id=make_id("x"))

    def test_id_length_validation(self):
        with pytest.raises(ValueError, match="id"):
            Message(nonce=make_nonce(), id=b"\x00")

    def test_digest_length_validation(self):
        with pytest.raises(ValueError, match="digest"):
            Message(nonce=make_nonce(), id=make_id("x"),
                    digests=(b"\x00",))

    def test_serialize_roundtrip_deterministic(self):
        msg = Message(nonce=make_nonce(42), id=make_id("proc1"),
                      digests=(), payload=b"hello world")
        serialized = msg.serialize()
        assert isinstance(serialized, bytes)
        # Same message serializes the same way
        assert msg.serialize() == serialized

    def test_compute_digest_deterministic(self):
        msg = Message(nonce=make_nonce(), id=make_id("test"), payload=b"data")
        d1 = msg.compute_digest()
        d2 = msg.compute_digest()
        assert d1 == d2
        assert len(d1) == DIGEST_LENGTH

    def test_different_messages_different_digests(self):
        m1 = Message(nonce=make_nonce(1), id=make_id("a"), payload=b"x")
        m2 = Message(nonce=make_nonce(2), id=make_id("a"), payload=b"x")
        assert m1.compute_digest() != m2.compute_digest()

    def test_message_with_digests(self):
        parent = Message(nonce=make_nonce(), id=make_id("a"), payload=b"parent")
        child = Message(
            nonce=make_nonce(1), id=make_id("a"),
            digests=(parent.compute_digest(),),
            payload=b"child"
        )
        assert child.num_digests == 1
        assert child.digests[0] == parent.compute_digest()

    def test_message_is_immutable(self):
        msg = Message(nonce=make_nonce(), id=make_id("x"), payload=b"y")
        with pytest.raises(AttributeError):
            msg.nonce = b"\x00" * NONCE_LENGTH


class TestVertex:

    def test_vertex_wraps_message(self):
        msg = Message(nonce=make_nonce(), id=make_id("proc"), payload=b"data")
        v = Vertex(m=msg)
        assert v.nonce == msg.nonce
        assert v.id == msg.id
        assert v.payload == msg.payload
        assert v.digests == msg.digests

    def test_vertex_default_state(self):
        msg = Message(nonce=make_nonce(), id=make_id("x"))
        v = Vertex(m=msg)
        assert v.round is None
        assert v.is_last is None
        assert v.svp == []
        assert v.vote == {}
        assert v.total_position is None

    def test_vertex_equivalence(self):
        """Definition 3.3: two vertices are equivalent if v.m = v_hat.m"""
        msg = Message(nonce=make_nonce(), id=make_id("x"), payload=b"same")
        v1 = Vertex(m=msg)
        v2 = Vertex(m=msg)
        assert v1.equivalent_to(v2)
        assert v1 == v2
        assert hash(v1) == hash(v2)

    def test_vertex_non_equivalence(self):
        m1 = Message(nonce=make_nonce(1), id=make_id("x"))
        m2 = Message(nonce=make_nonce(2), id=make_id("x"))
        v1 = Vertex(m=m1)
        v2 = Vertex(m=m2)
        assert not v1.equivalent_to(v2)
        assert v1 != v2


class TestVote:

    def test_vote_undecided(self):
        v = Vote(message=None, binary=None)
        assert "∅" in repr(v)
        assert "⊥" in repr(v)

    def test_vote_with_message(self):
        msg = Message(nonce=make_nonce(), id=make_id("x"))
        v = Vote(message=msg, binary=1)
        assert v.binary == 1

    def test_empty_message_digest(self):
        assert EMPTY_MESSAGE_DIGEST == digest(b"")
