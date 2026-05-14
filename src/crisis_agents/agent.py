"""
CrisisAgent — abstract base + Mock subclasses for the deterministic path.

An agent in this PoC is something that, given the current view of claims, can
produce its next contributions. Agents have a stable 32-byte process_id
derived from their human-readable name; Crisis uses this id for mutation
detection, so two agents must never share one.

Real Claude-driven agents live in `live_agent.py` (Phase 5) and inherit the
same `CrisisAgent` interface — the mothership doesn't care which kind it is
driving.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

from crisis.crypto import digest
from crisis.message import ID_LENGTH

from crisis_agents.claim import Claim


def agent_id_from_name(name: str) -> bytes:
    """Derive a stable 32-byte process id from a human-readable name.

    Matches the convention used in `crisis.demo.Simulation`, so agents
    coexisting with simulated nodes have ids in the same space.
    """
    return digest(name.encode())[:ID_LENGTH]


@dataclass
class AgentTurn:
    """One emission from an agent in a given turn.

    Attributes:
        claim:           The Claim being emitted.
        target_subset:   None means broadcast to every peer. A set of peer
                         names means this variant of the claim is only
                         delivered to those peers — the building block of
                         byzantine equivocation. Honest agents always set
                         this to None.
    """
    claim: Claim
    target_subset: Optional[set[str]] = None


class CrisisAgent(ABC):
    """Abstract base for any agent participating in a Crisis-coordinated team."""

    def __init__(self, name: str):
        if not name:
            raise ValueError("agent name must be non-empty")
        self.name: str = name
        self.process_id: bytes = agent_id_from_name(name)

    @abstractmethod
    def next_turn(self, turn: int, received_claims: list[Claim]) -> list[AgentTurn]:
        """Produce this agent's emissions for turn `turn`.

        Args:
            turn:             The 0-indexed turn counter (matched across all agents).
            received_claims:  All claims the agent has seen *up to and including*
                              the previous turn. The agent may use these to inform
                              its next emission or ignore them entirely.

        Returns:
            A possibly-empty list of AgentTurn entries. An honest agent emits one
            broadcast AgentTurn per scripted item; a byzantine equivocator emits
            two AgentTurns with disjoint `target_subset`s for the same logical
            claim slot.
        """
        ...

    def __repr__(self) -> str:
        return f"{type(self).__name__}(name={self.name!r}, id={self.process_id.hex()[:8]}...)"


class MockAgent(CrisisAgent):
    """An agent that emits a predetermined sequence of claims.

    Used for tests and deterministic demos. The `scripted_claims` argument is
    a list of per-step emission lists: on its Nth invocation, the agent emits
    `scripted_claims[N]`. Invocations past the end of the script produce
    no emissions.

    Each agent maintains its own invocation counter, **independent of the
    mothership's turn counter** — that way the same agent can be used across
    closed-phase and Crisis-phase invocations without the script restarting.
    The `turn` argument is observed but not used to index the script.

    All emissions are broadcast (no equivocation). For equivocation, use
    `MockByzantineAgent`.
    """

    def __init__(self, name: str, scripted_claims: list[list[Claim]]):
        super().__init__(name)
        self._script = scripted_claims
        self._invocations = 0

    def next_turn(self, turn: int, received_claims: list[Claim]) -> list[AgentTurn]:
        idx = self._invocations
        self._invocations += 1
        if idx >= len(self._script):
            return []
        return [AgentTurn(claim=c) for c in self._script[idx]]


class MockByzantineAgent(CrisisAgent):
    """An agent that equivocates by construction.

    For each turn, two parallel claim variants may be emitted. The first
    variant goes to peers in `split_a`; the second variant goes to peers in
    `split_b`. Peers not in either set receive nothing for that turn.

    `scripted_pairs[turn]` is `(claim_to_a, claim_to_b)` — the two
    contradictory claims this agent emits on turn `turn`. Both share the
    emitting agent's process_id, so Crisis's `find_mutations` will surface
    them as a mutation pair once both vertices are present in any honest
    agent's combined view.

    Set `claim_to_b = None` to skip the equivocation for that turn (the
    agent then behaves honestly to everyone).
    """

    def __init__(self, name: str,
                 scripted_pairs: list[tuple[Claim, Optional[Claim]]],
                 split_a: set[str],
                 split_b: set[str]):
        super().__init__(name)
        if split_a & split_b:
            raise ValueError("split_a and split_b must be disjoint")
        self._script = scripted_pairs
        self._split_a = split_a
        self._split_b = split_b
        self._invocations = 0

    def next_turn(self, turn: int, received_claims: list[Claim]) -> list[AgentTurn]:
        idx = self._invocations
        self._invocations += 1
        if idx >= len(self._script):
            return []
        claim_a, claim_b = self._script[idx]
        out: list[AgentTurn] = [AgentTurn(claim=claim_a, target_subset=set(self._split_a))]
        if claim_b is not None:
            out.append(AgentTurn(claim=claim_b, target_subset=set(self._split_b)))
        return out
