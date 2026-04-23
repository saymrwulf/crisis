"""
Data Structures (Section 3)

3.1 Messages
-------------
Messages distribute payload across the network.  The purpose of the protocol
is to establish a total order on those messages that respects causality.

A message is a byte string of variable length with the following structure
(paper, page 3):

    struct Message {
        byte[c1]                nonce,
        byte[c2]                id,
        byte[c3]                num_digests,
        byte[p * num_digests]   digests,
        byte[]                  payload
    }

Where c1, c2, c3 are fixed protocol constants and p is the digest length.

The *nonce* is used by the weight function (e.g. PoW grinding).
The *id* groups messages into virtual processes.
The *digests* field encodes causal acknowledgement of other messages.

Key insight: a message that acknowledges other messages defines an inherent
natural causality -- this is the Lamport "happens-before" relation (1978).

    m -> m_hat  iff  H(m_hat) is contained in m.digests              (Eq. 2)

3.1.3 Vertices
---------------
To establish total order, messages are extended by local voting data that is
NOT transmitted.  Votes are deduced from the causal relation between messages.
This is the key characteristic of virtual voting (Moser & Melliar-Smith).

    struct Vertex {
        Message                          m,
        Option<uint>                     round,
        Option<boolean>                  is_last,
        Option<TotalOrderSet<uint>>      svp,         # safe voting pattern
        Option<(Message, Option<bool>)>  vote,
        Option<uint>                     total_position
    }
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

from crisis.crypto import digest, DIGEST_LENGTH


# ---------------------------------------------------------------------------
# Protocol constants (c1, c2, c3 from the paper)
# ---------------------------------------------------------------------------
# These define the byte-lengths of the fixed-size fields in a message.
# Chosen for a practical PoC: generous enough for real use, compact enough
# for clarity.

NONCE_LENGTH = 8       # c1: 8 bytes of nonce (plenty for PoW search space)
ID_LENGTH = 32         # c2: 32 bytes for virtual process id (a hash)
NUM_DIGESTS_LENGTH = 2  # c3: 2 bytes => up to 65535 referenced digests


# ---------------------------------------------------------------------------
# Message
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Message:
    """An immutable Crisis message as defined in Section 3.1.

    A message is the atomic unit of communication in the Crisis protocol.
    It carries a payload and encodes causal history through its digests field.

    Attributes:
        nonce:    Used by the weight function (e.g. PoW nonce grinding).
        id:       Groups this message into a virtual process.
        digests:  Tuple of digests of causally prior messages (H values).
        payload:  The actual application data being ordered.
    """
    nonce: bytes
    id: bytes
    digests: tuple[bytes, ...] = ()
    payload: bytes = b""

    def __post_init__(self):
        if len(self.nonce) != NONCE_LENGTH:
            raise ValueError(f"nonce must be {NONCE_LENGTH} bytes, got {len(self.nonce)}")
        if len(self.id) != ID_LENGTH:
            raise ValueError(f"id must be {ID_LENGTH} bytes, got {len(self.id)}")
        for i, d in enumerate(self.digests):
            if len(d) != DIGEST_LENGTH:
                raise ValueError(f"digest[{i}] must be {DIGEST_LENGTH} bytes")

    def serialize(self) -> bytes:
        """Serialize this message to a canonical byte string.

        The serialized form is what gets hashed to produce the message's digest.
        Format:  nonce | id | num_digests (2 bytes big-endian) | digests... | payload
        """
        num = len(self.digests)
        parts = [
            self.nonce,
            self.id,
            num.to_bytes(NUM_DIGESTS_LENGTH, "big"),
        ]
        for d in self.digests:
            parts.append(d)
        parts.append(self.payload)
        return b"".join(parts)

    def compute_digest(self) -> bytes:
        """Compute H(m) -- the digest of this message.

        This is the value other messages include in their digests field
        to acknowledge this message (establishing causality, Eq. 2).
        """
        return digest(self.serialize())

    @property
    def num_digests(self) -> int:
        return len(self.digests)

    def __repr__(self) -> str:
        h = self.compute_digest().hex()[:12]
        return f"Message(id={self.id.hex()[:8]}..., digests={self.num_digests}, hash={h}...)"


# ---------------------------------------------------------------------------
# The empty message (paper: ∅ ∈ MESSAGE)
# ---------------------------------------------------------------------------
# "We postulate a special non-message ∅ ∈ MESSAGE" (Section 3.1)
# Acknowledgement of ∅ is defined as H(empty string).

EMPTY_MESSAGE_DIGEST = digest(b"")


# ---------------------------------------------------------------------------
# Vote
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Vote:
    """A virtual vote as computed locally by each vertex.

    From the paper (Algorithm 7): v.vote(r) = (l, b) describes v's vote
    on some message l, together with a possibly undecided binary value
    b ∈ {⊥, 0, 1} in a round r.

    Attributes:
        message:   The message l being voted on (None = ∅, the non-leader).
        binary:    The binary part of the vote: None=⊥ (undecided), 0, or 1.
    """
    message: Optional[Message] = None
    binary: Optional[int] = None       # None = ⊥, 0, or 1

    def __repr__(self) -> str:
        msg_str = "∅" if self.message is None else self.message.compute_digest().hex()[:8]
        bin_str = "⊥" if self.binary is None else str(self.binary)
        return f"Vote({msg_str}, {bin_str})"


# ---------------------------------------------------------------------------
# Vertex
# ---------------------------------------------------------------------------

@dataclass
class Vertex:
    """A vertex in a Lamport graph (Section 3.1.3).

    A vertex wraps a message and adds locally-computed consensus state.
    The additional fields (round, is_last, svp, vote, total_position) are
    never transmitted -- they are deduced from the causal structure.

    From the paper (page 5, Eq. 6):
        w(v) <- w(v.m)
        v.nonce <- v.m.nonce
        v.id    <- v.m.id
        v.num_digests <- v.m.num_digests
        v.digests <- v.m.digests
        v.payload <- v.m.payload

    Attributes:
        m:              The underlying message.
        round:          The virtual round number (Algorithm 5).
        is_last:        Whether this is a "last vertex" of its round (Alg 5).
        svp:            Safe voting pattern -- ordered set of round numbers.
        vote:           Per-round votes: round -> Vote.
        total_position: Final position in the total order (Algorithm 9/10).
    """
    m: Message

    # Locally computed consensus state (initialized to None / ⊥)
    round: Optional[int] = None
    is_last: Optional[bool] = None
    svp: list[int] = field(default_factory=list)
    vote: dict[int, Vote] = field(default_factory=dict)
    total_position: Optional[int] = None

    # ------------------------------------------------------------------
    # Convenience accessors that delegate to the underlying message
    # ------------------------------------------------------------------

    @property
    def nonce(self) -> bytes:
        return self.m.nonce

    @property
    def id(self) -> bytes:
        return self.m.id

    @property
    def digests(self) -> tuple[bytes, ...]:
        return self.m.digests

    @property
    def payload(self) -> bytes:
        return self.m.payload

    @property
    def message_digest(self) -> bytes:
        """H(v.m) -- the digest that uniquely identifies this vertex's message."""
        return self.m.compute_digest()

    # ------------------------------------------------------------------
    # Equivalence (Definition 3.3)
    # ------------------------------------------------------------------
    # "Two vertices v and v_hat are equivalent if v.m = v_hat.m"
    # i.e. they wrap the same underlying message.

    def equivalent_to(self, other: Vertex) -> bool:
        """Check vertex equivalence: same underlying message."""
        return self.message_digest == other.message_digest

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Vertex):
            return NotImplemented
        return self.message_digest == other.message_digest

    def __hash__(self) -> int:
        return hash(self.message_digest)

    def __repr__(self) -> str:
        h = self.message_digest.hex()[:12]
        round_str = str(self.round) if self.round is not None else "?"
        last_str = "*" if self.is_last else ""
        return f"Vertex({h}..., r={round_str}{last_str})"
