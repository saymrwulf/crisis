"""Tests for the crypto module (random oracle model)."""

from crisis.crypto import (
    digest, digest_hex, verify_digest,
    least_significant_bit, count_leading_zero_bits,
    DIGEST_LENGTH,
)


def test_digest_returns_32_bytes():
    h = digest(b"hello")
    assert len(h) == DIGEST_LENGTH == 32


def test_digest_is_deterministic():
    assert digest(b"test") == digest(b"test")


def test_digest_different_inputs_different_outputs():
    assert digest(b"a") != digest(b"b")


def test_digest_hex_matches():
    h = digest(b"hello")
    assert digest_hex(b"hello") == h.hex()


def test_verify_digest():
    h = digest(b"data")
    assert verify_digest(b"data", h)
    assert not verify_digest(b"other", h)


def test_least_significant_bit():
    # 0x00 -> LSB = 0, 0x01 -> LSB = 1
    assert least_significant_bit(b"\x00") == 0
    assert least_significant_bit(b"\x01") == 1
    assert least_significant_bit(b"\x02") == 0
    assert least_significant_bit(b"\x03") == 1
    assert least_significant_bit(b"\xff") == 1
    assert least_significant_bit(b"\xfe") == 0


def test_count_leading_zero_bits():
    assert count_leading_zero_bits(b"\xff") == 0
    assert count_leading_zero_bits(b"\x7f") == 1
    assert count_leading_zero_bits(b"\x3f") == 2
    assert count_leading_zero_bits(b"\x00\xff") == 8
    assert count_leading_zero_bits(b"\x00\x00\x01") == 23
    assert count_leading_zero_bits(b"\x00") == 8


def test_empty_digest_is_well_defined():
    """Paper: 'Acknowledgement of the empty string is defined as H(∅)'."""
    h = digest(b"")
    assert len(h) == 32
    assert h == digest(b"")  # deterministic
