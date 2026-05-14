"""
CrisisAgent — a first-class network participant in an asynchronous network.

Each agent owns:
  - a stable 32-byte process_id (derived from its name)
  - its own LamportGraph (the agent's view of the network)
  - its own weight system (shared across the network for compatibility)
  - decision logic: `try_emit()` is asked "do you have something to say?",
    `pending_alarm_claims()` is asked "do you currently observe an
    un-alarmed equivocation?"

There is no global clock. Agents don't see a "turn number" because there
isn't one — any synchronicity in the network is virtual, derived from the
DAG structure by the consensus algorithm itself (not by the driver loop).
The mothership/driver just cycles asking each agent for any pending
content until the network is quiescent.
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
    """One emission from an agent.

    The word "turn" here is vestigial — it means "this single emission
    event," not "a tick of a global clock." Kept because renaming the type
    causes more churn than it's worth.

    Attributes:
        claim:           The Claim being emitted.
        target_subset:   None means broadcast to every peer including
                         sender. A set of peer names means initial delivery
                         is limited to those peers (the byzantine
                         equivocation building block).
    """
    claim: Claim
    target_subset: Optional[set[str]] = None


class CrisisAgent(ABC):
    """An asynchronous network participant.

    Concrete subclasses implement `try_emit` to decide what to say. The
    base class handles emit/receive/gossip/detect mechanics uniformly so
    every agent — mock or live — uses the same Crisis substrate.
    """

    def __init__(self, name: str, *, weight_system: Optional[WeightSystem] = None):
        if not name:
            raise ValueError("agent name must be non-empty")
        self.name: str = name
        self.process_id: bytes = agent_id_from_name(name)
        self.weight_system: WeightSystem = weight_system or ProofOfWorkWeight(min_leading_zeros=0)
        self.graph: LamportGraph = LamportGraph(weight_system=self.weight_system)
        # Track alarms we've already emitted so pending_alarm_claims doesn't
        # repeat. Keyed by (accused, statement_id, sorted-witness-pair).
        self._already_alarmed: set[tuple[str, str, tuple[str, str]]] = set()

    # ------------------------------------------------------------------
    # Decision-making — implemented by subclasses
    # ------------------------------------------------------------------

    @abstractmethod
    def try_emit(self) -> list[AgentTurn]:
        """Return any emissions the agent is ready to make right now.

        The agent decides based on its own internal state. The driver loop
        asks this repeatedly until the agent returns nothing. There is no
        turn argument — agents in an async network don't see a global tick.
        """
        ...

    def observe(self, claim: Claim) -> None:
        """Optional callback for pre-Crisis context.

        Used by the closed-phase loop: when one agent emits a claim, every
        other agent's `observe(claim)` is called so they can incorporate
        the conversation history into their own state. Default is no-op;
        subclasses like LiveClaudeAgent override to maintain a context
        buffer for their LLM prompt.

        In the Crisis phase this is NOT called — agents introspect their
        own LamportGraph for context. The closed phase has no graph yet.
        """
        pass

    # ------------------------------------------------------------------
    # Crisis-protocol mechanics — uniform across all agents
    # ------------------------------------------------------------------

    def emit_claim(self, claim: Claim) -> Message:
        """Wrap a Claim into a fully-valid Crisis Message built FROM this
        agent's own graph state.

        The agent does NOT extend its own graph here — the routing layer
        decides whether the sender's own graph receives a copy.
        """
        return self._build_message(claim.to_payload())

    def _build_message(self, payload: bytes) -> Message:
        """Build a Crisis Message with arbitrary payload bytes.

        Used by both `emit_claim` (regular Claims) and the alarm-emission
        path (AlarmClaim payloads).
        """
        digests_list: list[bytes] = []

        # Chain link
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

        # Cross-references
        seen_other_ids: set[bytes] = {self.process_id}
        for v in self.graph.all_vertices():
            if v.id in seen_other_ids:
                continue
            if v.message_digest in past_digests:
                continue
            digests_list.append(v.message_digest)
            seen_other_ids.add(v.id)

        # Mine PoW
        if isinstance(self.weight_system, ProofOfWorkWeight):
            return self.weight_system.mine_nonce(
                self.process_id, tuple(digests_list), payload,
            )
        return Message(
            nonce=os.urandom(NONCE_LENGTH),
            id=self.process_id,
            digests=tuple(digests_list),
            payload=payload,
        )

    def receive(self, message: Message) -> Optional[Vertex]:
        """Extend my graph with the given message if integrity holds."""
        if message.compute_digest() in self.graph:
            return None
        return self.graph.extend(message)

    def gossip_to(self, peer: "CrisisAgent") -> int:
        """Share my vertices with `peer`. Returns count newly accepted.

        Iterates until no progress: a message is only accepted after all
        its referenced digests already exist in the peer's graph
        (Algorithm 4 in the paper, in-process flavor).
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

    def detect_mutations(self):
        """Scan MY graph for same-id spacelike vertex pairs.

        Returns a list of LocalAlarms. Imported lazily to avoid a cyclic
        import at module load time.
        """
        from crisis_agents.alarm import detect_mutations_in_graph
        return detect_mutations_in_graph(self.graph, self.name, self.process_id)

    def pending_alarm_claims(self) -> list:
        """Run detection and produce AlarmClaim payloads for any newly
        observed equivocations.

        An "already alarmed" set tracks claims this agent has already
        emitted, so calling this repeatedly is idempotent — the driver
        loop can call it until quiescence without flooding the network
        with duplicate AlarmClaims.

        Returns a list of AlarmClaim instances (defined in vote.py) that
        the driver should broadcast on the agent's behalf.
        """
        from crisis_agents.vote import AlarmClaim

        local_alarms = self.detect_mutations()
        new_claims: list = []
        for la in local_alarms:
            # Canonical key for dedup
            key = (la.accused_process_id_hex, la.statement_id, la.witness_digests)
            if key in self._already_alarmed:
                continue
            # detected_at_step is the agent's local sequence number — we
            # don't have a meaningful global step, so we use the count of
            # alarms already raised by this agent as a stable ordinal.
            ac = AlarmClaim(
                accused_process_id_hex=la.accused_process_id_hex,
                statement_id=la.statement_id,
                witness_digests=la.witness_digests,
                emitted_at_step=len(self._already_alarmed),
            )
            new_claims.append(ac)
            self._already_alarmed.add(key)
        return new_claims

    def __repr__(self) -> str:
        return f"{type(self).__name__}(name={self.name!r}, id={self.process_id.hex()[:8]}...)"


# ---------------------------------------------------------------------------
# MockAgent variants — scripted agents for tests and deterministic demos
# ---------------------------------------------------------------------------


class MockAgent(CrisisAgent):
    """An agent that emits a predetermined sequence of claims.

    `scripted_claims[N]` is the list of Claims emitted on the agent's Nth
    `try_emit()` invocation. After the script is exhausted, the agent
    emits nothing forever — the driver loop's quiescence check terminates
    naturally.
    """

    def __init__(self, name: str, scripted_claims: list[list[Claim]],
                 *, weight_system: Optional[WeightSystem] = None):
        super().__init__(name, weight_system=weight_system)
        self._script = scripted_claims
        self._invocations = 0

    def try_emit(self) -> list[AgentTurn]:
        idx = self._invocations
        self._invocations += 1
        if idx >= len(self._script):
            return []
        return [AgentTurn(claim=c) for c in self._script[idx]]


class MockByzantineAgent(CrisisAgent):
    """An agent designed to equivocate.

    On its first `try_emit()` invocation it broadcasts an `intro_claim` so
    every honest agent has a same-id vertex to chain the equivocation off.
    On subsequent invocations it emits pairs of contradictory claims from
    `scripted_pairs`, with the first variant targeted at `split_a` and the
    second at `split_b`.

    Byzantines never emit AlarmClaims about other agents — there's a
    subclass override of `pending_alarm_claims` that returns empty. (A
    more advanced byzantine could emit FALSE AlarmClaims to test the
    quorum-vote isolation; not in scope for this PoC.)
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

    def try_emit(self) -> list[AgentTurn]:
        idx = self._invocations
        self._invocations += 1
        if idx == 0:
            return [AgentTurn(claim=self._intro, target_subset=None)]
        pair_idx = idx - 1
        if pair_idx >= len(self._script):
            return []
        claim_a, claim_b = self._script[pair_idx]
        out: list[AgentTurn] = [AgentTurn(claim=claim_a, target_subset=set(self._split_a))]
        if claim_b is not None:
            out.append(AgentTurn(claim=claim_b, target_subset=set(self._split_b)))
        return out

    def pending_alarm_claims(self) -> list:
        """Byzantines don't emit alarms in our threat model."""
        return []
