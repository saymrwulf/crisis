"""
Random Oracle Model (Section 2.1)

We work in the random oracle model, assuming the existence of a cryptographic
hash function that behaves like a random oracle:

    H : {0,1}* -> {0,1}^p                                          (Eq. 1)

We use SHA-256 as our concrete instantiation.  H is assumed to be collision-,
preimage-, and second-preimage-resistant.

We call H(b) the *digest* of the binary string b.
"""

import hashlib
from typing import Union

# The digest length in bytes (SHA-256 produces 32 bytes = 256 bits).
DIGEST_LENGTH = 32


def digest(data: Union[bytes, bytearray]) -> bytes:
    """Compute the SHA-256 digest of arbitrary binary data.

    This is the core random oracle H used throughout the protocol.
    Every reference to "the digest of" a message or byte string in the
    paper maps to this function.

    Returns:
        32-byte digest (256 bits).
    """
    return hashlib.sha256(data).digest()


def digest_hex(data: Union[bytes, bytearray]) -> str:
    """Convenience: return the digest as a hex string for display."""
    return digest(data).hex()


def verify_digest(data: bytes, expected: bytes) -> bool:
    """Check that H(data) equals the expected digest."""
    return digest(data) == expected


# ---------------------------------------------------------------------------
# Least significant bit helper  (used in the virtual coin flip, Algorithm 7)
# ---------------------------------------------------------------------------

def least_significant_bit(h: bytes) -> int:
    """Return the least significant bit of a hash value.

    Used in Algorithm 7 (virtual leader election) for the "genuine coin flip"
    stage, where the LSB of H(v_hat.m) determines the binary vote.

    The paper defines:
        b_coin := lsb(H(x.m))  for max weight x in S
    """
    return h[-1] & 1


# ---------------------------------------------------------------------------
# Proof-of-Work helpers  (used by the weight system, Section 3.1.1)
# ---------------------------------------------------------------------------

def count_leading_zero_bits(h: bytes) -> int:
    """Count the number of leading zero bits in a hash value.

    This is the standard measure of proof-of-work difficulty: a hash with
    k leading zero bits required roughly 2^k hash evaluations to find.
    """
    count = 0
    for byte in h:
        if byte == 0:
            count += 8
        else:
            # Count leading zeros in this byte
            count += (byte ^ 0xFF).bit_length() - (255 - byte).bit_length()
            # Simpler: count leading zeros via bit tricks
            for bit_pos in range(7, -1, -1):
                if byte & (1 << bit_pos):
                    return count
                count += 1
            break
    return count


def count_leading_zero_bits(h: bytes) -> int:
    """Count the number of leading zero bits in a hash value.

    A hash with k leading zero bits required roughly 2^k evaluations to find.
    Used by the PoW weight function to assign weight to messages.
    """
    count = 0
    for byte in h:
        if byte == 0:
            count += 8
            continue
        # Count leading zeros in this non-zero byte
        for bit_pos in range(7, -1, -1):
            if byte & (1 << bit_pos):
                return count
            count += 1
        break
    return count
