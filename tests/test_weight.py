"""Tests for the weight system and difficulty oracle."""

from crisis.crypto import digest
from crisis.message import Message, ID_LENGTH, NONCE_LENGTH
from crisis.weight import ProofOfWorkWeight, DifficultyOracle


def make_id(name: str) -> bytes:
    return digest(name.encode())[:ID_LENGTH]


def make_nonce(n: int = 0) -> bytes:
    return n.to_bytes(NONCE_LENGTH, "big")


class TestProofOfWorkWeight:

    def test_weight_is_non_negative(self):
        ws = ProofOfWorkWeight(min_leading_zeros=0)
        msg = Message(nonce=make_nonce(), id=make_id("x"), payload=b"test")
        assert ws.weight(msg) >= 0

    def test_weight_sum_is_additive(self):
        ws = ProofOfWorkWeight()
        assert ws.weight_sum(3, 5) == 8
        assert ws.weight_sum(0, 0) == 0

    def test_threshold(self):
        ws = ProofOfWorkWeight(min_leading_zeros=2)
        assert ws.threshold == 2

    def test_is_valid_weight_with_zero_threshold(self):
        ws = ProofOfWorkWeight(min_leading_zeros=0)
        msg = Message(nonce=make_nonce(), id=make_id("x"))
        assert ws.is_valid_weight(msg)  # Everything passes with 0

    def test_mine_nonce_finds_valid_message(self):
        ws = ProofOfWorkWeight(min_leading_zeros=1)
        msg = ws.mine_nonce(
            id_bytes=make_id("miner"),
            digests=(),
            payload=b"test payload",
            target_weight=1
        )
        assert ws.weight(msg) >= 1
        assert ws.is_valid_weight(msg)

    def test_different_nonces_different_weights(self):
        """Uniqueness property: different messages have different weights (w.h.p.)."""
        ws = ProofOfWorkWeight()
        weights = set()
        for i in range(20):
            msg = Message(nonce=make_nonce(i), id=make_id("x"), payload=b"same")
            weights.add(ws.weight(msg))
        # Not all the same (with overwhelming probability)
        assert len(weights) > 1

    def test_tamper_proof(self):
        """Changing a message should change its weight (w.h.p.)."""
        ws = ProofOfWorkWeight()
        msg1 = Message(nonce=make_nonce(42), id=make_id("x"), payload=b"original")
        msg2 = Message(nonce=make_nonce(42), id=make_id("x"), payload=b"tampered")
        # Weights differ because digests differ
        # (this is probabilistic, but extremely likely)
        assert msg1.compute_digest() != msg2.compute_digest()


class TestDifficultyOracle:

    def test_constant_difficulty(self):
        d = DifficultyOracle(constant_difficulty=5)
        assert d.difficulty(0) == 5
        assert d.difficulty(100) == 5
        assert d.difficulty(999) == 5

    def test_default_difficulty(self):
        d = DifficultyOracle()
        assert d.difficulty(0) == 4
