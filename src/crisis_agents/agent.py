"""
CrisisAgent — a first-class network participant.

Each agent owns:
  - a stable 32-byte process_id (derived from its name)
  - its own LamportGraph (the agent's view of the network)
  - its own weight system (shared across the network for compatibility)
  - the means to wrap Claims into Crisis Messages and extend its own graph

Crucially the agent is **NOT a passive script driven by the mothership**. The
mothership coordinates the clock and the bootstrap; the agent does the work.

This is the change from the centralized version: previously the mothership
held a dict of all agents' graphs and called `_wrap_as_message` against each.
Now `emit_claim` lives on the agent. The mothership routes the resulting
message to its delivery targets, but it never reads the graph.
"""

from __future__ import annotations

import os
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

from crisis.crypto import digest
from crisis.graph import LamportGraph
from crisis.message import ID_LENGTH, Message, NONCE_LENGTH, Vertex
from crisis.weight import ProofOfWorkWeight, WeightSystem

from crisis_agents.claim import Claim


def agent_id_from_name(name: str) -> bytes:
    """Derive a stable 32-byte process id from a human-readable name."""
    return digest(name.encode())[:ID_LENGTH]


@dataclass
class AgentTurn:
    """One emission from an agent in a given turn.

    Attributes:
        claim:           The Claim being emitted.
        target_subset:   None means broadcast (every agent including sender
                         receives it via the mothership's initial routing).
                         A set of peer names means initial delivery is limited
                         to those peers — the byzantine equivocation building
                         block. Subsequent gossip rounds may propagate it to
                         other peers anyway.
    """
    claim: Claim
    target_subset: Optional[set[str]] = None


class CrisisAgent(ABC):
    """A network participant with its own graph and its own brain.

    Concrete subclasses implement `next_turn` to decide what to say. The
    base class handles emit/receive/gossip mechanics so every agent — mock
    or live — uses the same Crisis-protocol machinery underneath.
    """

    def __init__(self, name: str, *, weight_system: Optional[WeightSystem] = None):
        if not name:
            raise ValueError("agent name must be non-empty")
        self.name: str = name
        self.process_id: bytes = agent_id_from_name(name)
        self.weight_system: WeightSystem = weight_system or ProofOfWorkWeight(min_leading_zeros=0)
        self.graph: LamportGraph = LamportGraph(weight_system=self.weight_system)

    # ------------------------------------------------------------------
    # Decision-making — to be implemented by subclasses
    # ------------------------------------------------------------------

    @abstractmethod
    def next_turn(self, turn: int, received_claims: list[Claim]) -> list[AgentTurn]:
        """Produce this agent's emissions for the given turn."""
        ...

    # ------------------------------------------------------------------
    # Crisis-protocol mechanics — uniform across all agents
    # ------------------------------------------------------------------

    def emit_claim(self, claim: Claim) -> Message:
        """Wrap a Claim into a fully-valid Crisis Message built FROM this
        agent's own graph state.

        The agent does NOT extend its own graph here — the mothership decides
        whether the sender receives a copy (broadcast: yes; targeted: no, to
        enable byzantine equivocation without immediately failing the chain
        constraint in the sender's own graph).
        """
        payload = claim.to_payload()

        digests_list: list[bytes] = []

        # Step 1: chain link — if there's any same-id vertex in MY graph, the
        # new message must reference one of them.
        same_id = [v for v in self.graph.all_vertices() if v.id == self.process_id]
        past_digests: set[bytes] = set()
        if same_id:
            referenced = set()
            for v in same_id:
                for d in v.digests:
                    ref = self.graph.get_vertex(d)
                    if ref is not None and ref.id == self.process_id:
                        referenced.add(d)
            last = next(
                (v for v in same_id if v.message_digest not in referenced),
                same_id[-1],
            )
            digests_list.append(last.message_digest)
            past_digests = {v.message_digest for v in self.graph.past(last)}

        # Step 2: cross-references — one most-recent vertex per other id.
        seen_other_ids: set[bytes] = {self.process_id}
        for v in self.graph.all_vertices():
            if v.id in seen_other_ids:
                continue
            if v.message_digest in past_digests:
                continue
            digests_list.append(v.message_digest)
            seen_other_ids.add(v.id)

        # Step 3: mine a valid PoW nonce.
        if isinstance(self.weight_system, ProofOfWorkWeight):
            return self.weight_system.mine_nonce(
                self.process_id, tuple(digests_list), payload
            )
        return Message(
            nonce=os.urandom(NONCE_LENGTH),
            id=self.process_id,
            digests=tuple(digests_list),
            payload=payload,
        )

    def receive(self, message: Message) -> Optional[Vertex]:
        """Extend my graph with the given message if integrity holds.

        Returns the resulting Vertex on success, None if the integrity check
        rejects it (duplicate, missing references, broken chain). Receiving
        is idempotent: extending with a message whose digest is already in
        the graph is a silent no-op (returns None).
        """
        if message.compute_digest() in self.graph:
            return None
        return self.graph.extend(message)

    def detect_mutations(self):
        """Scan MY graph for byzantine equivocation. Returns a list of
        LocalAlarms (defined in alarm.py). Imported lazily to avoid a
        cyclic import at module load time.
        """
        from crisis_agents.alarm import detect_mutations_in_graph
        return detect_mutations_in_graph(self.graph, self.name, self.process_id)

    def gossip_to(self, peer: "CrisisAgent") -> int:
        """Share my vertices with `peer`. Returns the count newly accepted.

        Iterates until no progress: a message can only be accepted after all
        its referenced digests already exist in the peer's graph, so this is
        a multi-pass extend (Algorithm 4 in the paper, in-process flavor).

        Honest gossip: the sender doesn't pick what to share — it shares
        everything it has, and the peer's integrity check filters. A byzantine
        could selectively gossip, but that's modeled at emit time, not gossip
        time; we don't expose a "skip this vertex" hook here.
        """
        accepted = 0
        progress = True
        while progress:
            progress = False
            for v in self.graph.all_vertices():
                if v.message_digest in peer.graph:
                    continue
                if peer.receive(v.m) is not None:
                    accepted += 1
                    progress = True
        return accepted

    def __repr__(self) -> str:
        return f"{type(self).__name__}(name={self.name!r}, id={self.process_id.hex()[:8]}...)"


# ---------------------------------------------------------------------------
# MockAgent variants — scripted agents for tests and deterministic demos
# ---------------------------------------------------------------------------


class MockAgent(CrisisAgent):
    """An agent that emits a predetermined sequence of claims.

    `scripted_claims[N]` is the list of Claims this agent emits on its Nth
    `next_turn()` invocation. The agent maintains its own invocation counter
    independent of the mothership's turn counter, so it can be reused across
    closed-phase and Crisis-phase calls without restarting.

    All emissions are broadcast (no equivocation). For equivocation, use
    `MockByzantineAgent`.
    """

    def __init__(self, name: str, scripted_claims: list[list[Claim]],
                 *, weight_system: Optional[WeightSystem] = None):
        super().__init__(name, weight_system=weight_system)
        self._script = scripted_claims
        self._invocations = 0

    def next_turn(self, turn: int, received_claims: list[Claim]) -> list[AgentTurn]:
        idx = self._invocations
        self._invocations += 1
        if idx >= len(self._script):
            return []
        return [AgentTurn(claim=c) for c in self._script[idx]]


class MockByzantineAgent(CrisisAgent):
    """An agent designed to equivocate.

    Lifecycle:
      - Invocation 0: emit a broadcast `intro_claim` (a benign "I've joined"
        message). This is **necessary** for the equivocation step: both
        variants of the equivocating claim will chain to this intro, so they
        can propagate through the gossip layer (otherwise the chain constraint
        in `Message.message_integrity` step 6 would reject the second variant
        in any graph that already holds the first).
      - Invocations 1..N: emit pairs of contradictory claims, with the first
        variant targeted at `split_a` and the second at `split_b`. Both
        variants in a pair carry the same `statement_id` but contradict on
        `verdict`.

    Set `scripted_pairs` empty to test "byzantine joined but didn't equivocate".
    """

    def __init__(self, name: str, intro_claim: Claim,
                 scripted_pairs: list[tuple[Claim, Optional[Claim]]],
                 split_a: set[str], split_b: set[str],
                 *, weight_system: Optional[WeightSystem] = None):
        super().__init__(name, weight_system=weight_system)
        if split_a & split_b:
            raise ValueError("split_a and split_b must be disjoint")
        self._intro = intro_claim
        self._script = scripted_pairs
        self._split_a = split_a
        self._split_b = split_b
        self._invocations = 0

    def next_turn(self, turn: int, received_claims: list[Claim]) -> list[AgentTurn]:
        idx = self._invocations
        self._invocations += 1
        if idx == 0:
            # The introduction turn: a single broadcast so all peers learn my
            # identity and have a same-id vertex to chain my equivocations to.
            return [AgentTurn(claim=self._intro, target_subset=None)]
        pair_idx = idx - 1
        if pair_idx >= len(self._script):
            return []
        claim_a, claim_b = self._script[pair_idx]
        out: list[AgentTurn] = [AgentTurn(claim=claim_a, target_subset=set(self._split_a))]
        if claim_b is not None:
            out.append(AgentTurn(claim=claim_b, target_subset=set(self._split_b)))
        return out
