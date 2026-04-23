"""
Weight Systems (Section 3.1.1)

Definition 3.1 (Weight system):  Let MESSAGE be the metric space of all
messages and (W, ≤) a totally ordered set.  Then the tuple (W, w, ⊕, c_min)
is a *weight system* if w is a function

    w : MESSAGE -> W                                                (Eq. 3)

that assigns an element of W to any message, c_min ∈ W is a constant called
the *weight threshold*, and ⊕ is a function

    ⊕ : W × W -> W                                                 (Eq. 4)

called the *weight sum*, such that:

    - Tamper proof:   w(m) >= c_min and m_hat ≠ m implies w(m_hat) < c_min
                      with high probability.
    - Uniqueness:     m ≠ m_hat implies w(m) ≠ w(m_hat) with high probability.
    - Summability:    (W, ⊕) is a totally ordered, abelian group.

The weight w(m) is interpreted as the amount of voting power m holds to
influence total order generation.

This module provides:
    1. An abstract WeightSystem protocol
    2. A concrete Proof-of-Work implementation (Hashcash-style)

The PoW weight function counts leading zero bits of H(m), similar to Bitcoin's
difficulty mechanism (Nakamoto, 2009; Beck, 2002).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from crisis.crypto import digest, count_leading_zero_bits
from crisis.message import Message


# ---------------------------------------------------------------------------
# Abstract weight system
# ---------------------------------------------------------------------------

class WeightSystem(Protocol):
    """Protocol defining the weight system interface (Definition 3.1).

    Any concrete weight system must provide:
        - weight():     Compute w(m) for a message
        - threshold:    The minimum weight c_min
        - weight_sum(): Compute ⊕ for two weights
    """

    @property
    def threshold(self) -> int:
        """c_min: the minimum weight threshold.

        Messages with weight below this are rejected.  This prevents Sybil
        attacks by ensuring every message requires a minimum investment.
        """
        ...

    def weight(self, message: Message) -> int:
        """w(m): compute the weight of a message.

        The weight represents the voting power of this message in the
        consensus protocol.
        """
        ...

    def weight_sum(self, a: int, b: int) -> int:
        """⊕: combine two weights.

        Must form a totally ordered abelian group.
        For our purposes, ordinary integer addition suffices.
        """
        ...

    def is_valid_weight(self, message: Message) -> bool:
        """Check whether w(m) >= c_min."""
        ...


# ---------------------------------------------------------------------------
# Proof-of-Work weight system
# ---------------------------------------------------------------------------

@dataclass
class ProofOfWorkWeight:
    """A Hashcash-style Proof-of-Work weight system.

    The weight of a message is the number of leading zero bits in H(m).
    This is similar to Bitcoin's mining: finding a message whose hash starts
    with k zero bits requires approximately 2^k hash evaluations on average.

    The nonce field of the message is used to search for a valid hash,
    analogous to Bitcoin's block header nonce.

    Attributes:
        min_leading_zeros:  c_min -- minimum leading zero bits required.
                            A value of 1 means every message needs at least
                            1 leading zero bit (50% of hashes qualify).
    """
    min_leading_zeros: int = 1

    @property
    def threshold(self) -> int:
        return self.min_leading_zeros

    def weight(self, message: Message) -> int:
        """Count leading zero bits in H(m).

        More leading zeros = more work performed = higher voting weight.
        """
        h = message.compute_digest()
        return count_leading_zero_bits(h)

    def weight_sum(self, a: int, b: int) -> int:
        """Simple integer addition for combining weights.

        This satisfies the abelian group requirement: (Z, +) is a totally
        ordered abelian group with identity 0.
        """
        return a + b

    def is_valid_weight(self, message: Message) -> bool:
        """Check w(m) >= c_min."""
        return self.weight(message) >= self.threshold

    def mine_nonce(self, id_bytes: bytes, digests: tuple[bytes, ...],
                   payload: bytes, target_weight: int | None = None) -> Message:
        """Search for a nonce that produces a message meeting the weight target.

        This is the "nonce grinding" step: try successive nonce values until
        H(m) has enough leading zero bits.

        Args:
            id_bytes:       The virtual process id for this message.
            digests:        Causal acknowledgements (digests of prior messages).
            payload:        The application payload.
            target_weight:  Minimum weight to achieve.  Defaults to c_min.

        Returns:
            A Message with a valid nonce.
        """
        if target_weight is None:
            target_weight = self.threshold

        nonce_int = 0
        while True:
            nonce = nonce_int.to_bytes(8, "big")
            msg = Message(nonce=nonce, id=id_bytes, digests=digests, payload=payload)
            if self.weight(msg) >= target_weight:
                return msg
            nonce_int += 1


# ---------------------------------------------------------------------------
# Difficulty Oracle (Section 5.4, Definition 5.2)
# ---------------------------------------------------------------------------

@dataclass
class DifficultyOracle:
    """Maps round numbers to difficulty values (Definition 5.2).

    The difficulty oracle d : N -> W maps natural numbers (rounds) onto
    weights.  The value d_r := d(r) is called the *round r difficulty*.

    The difficulty is designed so that the overall voting weight per round
    is bounded:

        lim sum(w_s^G / d_s) <= 6                                  (Eq. 8)

    for all time parameters t, where w_s^G is the overall voting weight of
    last vertices in round s.

    Example 1 (paper): A fixed constant that does not change over time.
    This is the simplest starting point for a PoC.
    """
    constant_difficulty: int = 4

    def difficulty(self, round_number: int) -> int:
        """d(r): return the difficulty for round r.

        For this PoC we use a fixed constant (paper Example 1).
        A production system might adapt this based on observed voting
        weight, similar to Bitcoin's difficulty adjustment.
        """
        return self.constant_difficulty
