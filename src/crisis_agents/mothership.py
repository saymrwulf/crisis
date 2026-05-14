"""
Mothership — the orchestrator that runs a Crisis-Agents network.

Two phases:

1. **Closed phase.** Agents talk freely. `run_closed_phase(N)` advances N
   turns, collecting every claim into a flat log. No DAG, no voting, no
   overhead. This is the "normal life" the user described.

2. **Crisis phase.** Triggered by `open_boundary(new_agent)`. From that
   point on every claim is wrapped into a Crisis `Message`, extended into
   per-agent `LamportGraph`s, and consensus algorithms run. Mutation
   detection raises alarms; proofs are generated separately by `proof.py`.

The mothership keeps one LamportGraph per agent (the agent's view of the
network) and updates them in lockstep — the PoC uses synchronous in-process
delivery, so all honest agents see the same vertices except where a
byzantine agent has selectively delivered an equivocation. Each honest
graph still observes both equivocating vertices once the network gossips
enough; that's what `LamportGraph.find_mutations` keys on.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Optional

from crisis.graph import LamportGraph
from crisis.message import Message, NONCE_LENGTH
from crisis.weight import ProofOfWorkWeight

from crisis_agents.agent import AgentTurn, CrisisAgent
from crisis_agents.boundary import Boundary
from crisis_agents.claim import Claim


@dataclass
class ClosedPhaseEntry:
    """One row in the closed-phase log: who said what, when."""
    agent_name: str
    turn: int
    claim: Claim


@dataclass
class CrisisPhaseEntry:
    """One row in the Crisis-phase log: the (agent, turn, claim, vertex_digest)
    of an emitted-and-accepted Crisis message, plus the target subset (set of
    peer names) it was delivered to. Useful as the raw material for proofs.
    """
    agent_name: str
    turn: int
    claim: Claim
    message_digest_hex: str
    delivered_to: list[str]


@dataclass
class MothershipRunResult:
    """What `run_closed_phase` / `run_crisis_phase` returns."""
    closed_log: list[ClosedPhaseEntry] = field(default_factory=list)
    crisis_log: list[CrisisPhaseEntry] = field(default_factory=list)


class Mothership:
    """Orchestrates a team of CrisisAgents.

    Usage:
        m = Mothership()
        m.add_agent(MockAgent("agent_a", ...))
        m.add_agent(MockAgent("agent_b", ...))
        m.add_agent(MockAgent("agent_c", ...))

        # Closed phase
        m.run_closed_phase(num_turns=2)

        # Boundary opens
        m.open_boundary(MockByzantineAgent("agent_d", ...))

        # Crisis phase
        m.run_crisis_phase(num_turns=5)
    """

    def __init__(self, *, pow_zeros: int = 0):
        self.agents: dict[str, CrisisAgent] = {}
        self.boundary = Boundary()
        self.run_result = MothershipRunResult()

        # Per-agent Lamport graphs (only used in the Crisis phase).
        self._graphs: dict[str, LamportGraph] = {}
        self._weight_system = ProofOfWorkWeight(min_leading_zeros=pow_zeros)

        # Independent turn counters: closed and Crisis phases share none.
        # Crisis-phase turns count from 0 again so the proof JSON has a
        # clean "round after boundary open" timeline.
        self._closed_turn_index = 0
        self._crisis_turn_index = 0

    # ------------------------------------------------------------------
    # Setup
    # ------------------------------------------------------------------

    def add_agent(self, agent: CrisisAgent) -> None:
        """Register a trusted agent (must be called before run_closed_phase)."""
        if self.boundary.is_open:
            raise RuntimeError("cannot add_agent after boundary opened; use open_boundary")
        if agent.name in self.agents:
            raise ValueError(f"agent {agent.name!r} already added")
        self.agents[agent.name] = agent
        self.boundary.add_trusted(agent.process_id)

    # ------------------------------------------------------------------
    # Phase 1: closed
    # ------------------------------------------------------------------

    def run_closed_phase(self, num_turns: int) -> MothershipRunResult:
        """Drive `num_turns` of plain agent communication. No Crisis.

        Each turn:
          - All agents see the cumulative claims observed so far.
          - Each agent emits its scripted claims; each emission is appended
            to the closed log.
        """
        if self.boundary.is_open:
            raise RuntimeError("boundary already open; closed phase is over")

        observed: list[Claim] = [e.claim for e in self.run_result.closed_log]
        for _ in range(num_turns):
            turn = self._closed_turn_index
            new_this_turn: list[Claim] = []
            for agent in self.agents.values():
                for at in agent.next_turn(turn, observed):
                    self.run_result.closed_log.append(
                        ClosedPhaseEntry(agent_name=agent.name, turn=turn, claim=at.claim)
                    )
                    new_this_turn.append(at.claim)
            observed.extend(new_this_turn)
            self._closed_turn_index += 1
        return self.run_result

    # ------------------------------------------------------------------
    # Phase 2: boundary opens, Crisis activates
    # ------------------------------------------------------------------

    def open_boundary(self, new_agent: CrisisAgent) -> None:
        """The trigger: a new agent of unknown trust joins.

        Crisis is now active for all subsequent claim emission. Each existing
        agent gets a fresh LamportGraph; the new agent does too. From this
        moment, `run_crisis_phase()` drives the consensus loop.
        """
        if new_agent.name in self.agents:
            raise ValueError(f"agent {new_agent.name!r} is already inside the boundary")
        self.agents[new_agent.name] = new_agent
        self.boundary.open(new_agent.process_id)

        # Initialize a graph for every agent (including the joiner).
        for name in self.agents:
            self._graphs[name] = LamportGraph(weight_system=self._weight_system)

    # ------------------------------------------------------------------
    # Phase 2 mechanics: building Crisis messages from Claims
    # ------------------------------------------------------------------

    def _wrap_as_message(self, agent: CrisisAgent, claim: Claim,
                        graph: LamportGraph) -> Message:
        """Convert a Claim into a Crisis Message and return it (un-extended).

        Builds the digests tuple per Algorithm 1:
          - reference the agent's own last vertex in `graph` (chain link),
          - cross-reference one most-recent vertex per other id (sample).
        Mines a PoW nonce that satisfies the weight system.
        """
        payload = claim.to_payload()

        # Last vertex with this agent's id (chain link, if any)
        same_id = [v for v in graph.all_vertices() if v.id == agent.process_id]
        digests_list: list[bytes] = []
        if same_id:
            # Pick the one not referenced by any other same-id vertex
            referenced = set()
            for v in same_id:
                for d in v.digests:
                    ref = graph.get_vertex(d)
                    if ref is not None and ref.id == agent.process_id:
                        referenced.add(d)
            last = next(
                (v for v in same_id if v.message_digest not in referenced),
                same_id[-1],
            )
            digests_list.append(last.message_digest)
            past_digests = {v.message_digest for v in graph.past(last)}
        else:
            past_digests = set()

        # Cross-references: one most-recent vertex per other id
        seen_other_ids: set[bytes] = {agent.process_id}
        for v in graph.all_vertices():
            if v.id in seen_other_ids:
                continue
            if v.message_digest in past_digests:
                continue
            digests_list.append(v.message_digest)
            seen_other_ids.add(v.id)

        # Mine a valid nonce; reuse the weight system
        if isinstance(self._weight_system, ProofOfWorkWeight):
            return self._weight_system.mine_nonce(
                agent.process_id, tuple(digests_list), payload
            )
        else:
            return Message(
                nonce=os.urandom(NONCE_LENGTH),
                id=agent.process_id,
                digests=tuple(digests_list),
                payload=payload,
            )

    def _deliver(self, sender: CrisisAgent, message: Message,
                 target_names: list[str]) -> None:
        """Extend the message into the LamportGraphs of `target_names`."""
        for name in target_names:
            graph = self._graphs[name]
            graph.extend(message)

    # ------------------------------------------------------------------
    # Phase 2: the Crisis-active run loop
    # ------------------------------------------------------------------

    def run_crisis_phase(self, num_turns: int) -> MothershipRunResult:
        """Drive `num_turns` of agent activity with Crisis active.

        Each turn:
          1. Every agent (including the byzantine joiner) is asked for its
             emissions. Each emission carries an optional `target_subset`.
          2. Each emission is wrapped into a Crisis Message against the
             SENDER's view of the graph (the agent's own LamportGraph).
          3. The Message is delivered (extended) into the LamportGraphs of
             every peer in the target subset (or every peer if None).
          4. The (agent, turn, claim, message_digest, delivered_to) tuple
             is logged for downstream proof generation.
        """
        if not self.boundary.is_open:
            raise RuntimeError("boundary not yet open; call open_boundary() first")

        all_names = list(self.agents.keys())

        for _ in range(num_turns):
            turn = self._crisis_turn_index

            # Snapshot of received claims per agent — for the agent's view
            # of the conversation when it decides what to say next. In the
            # PoC this is the agent's graph's vertex set, decoded back to
            # Claim objects.
            for agent in self.agents.values():
                received: list[Claim] = []
                for v in self._graphs[agent.name].all_vertices():
                    if v.id == agent.process_id:
                        continue
                    try:
                        received.append(Claim.from_payload(v.payload))
                    except (ValueError, TypeError):
                        # Not all vertices need to be Claim-shaped (defensive)
                        continue

                for at in agent.next_turn(turn, received):
                    self._emit(agent, turn, at, all_names)

            self._crisis_turn_index += 1

        return self.run_result

    def _emit(self, agent: CrisisAgent, turn: int, at: AgentTurn,
              all_names: list[str]) -> None:
        """Resolve target subset, build message, deliver, log.

        Delivery rule:
          - target_subset is None  ⇒ honest broadcast to all peers including
            the sender's own graph.
          - target_subset is set   ⇒ targeted delivery; the sender's own
            graph is NOT auto-included. This is what enables byzantine
            equivocation: a byzantine sender emits two variants with
            disjoint targets, and its own graph holds neither — otherwise
            the second variant would fail the same-id chain constraint
            against the first variant.

        The byzantine still "knows" what it said via the crisis_log; what
        it doesn't keep in its own LamportGraph is the conflicting state.
        """
        if at.target_subset is None:
            targets = list(all_names)
        else:
            targets = [t for t in at.target_subset if t in self.agents]

        msg = self._wrap_as_message(agent, at.claim, self._graphs[agent.name])
        self._deliver(agent, msg, targets)

        self.run_result.crisis_log.append(
            CrisisPhaseEntry(
                agent_name=agent.name,
                turn=turn,
                claim=at.claim,
                message_digest_hex=msg.compute_digest().hex(),
                delivered_to=targets,
            )
        )

    # ------------------------------------------------------------------
    # Read-only accessors (used by alarm.py and proof.py in later phases)
    # ------------------------------------------------------------------

    def graph_of(self, agent_name: str) -> LamportGraph:
        """The LamportGraph held by `agent_name` (Crisis phase only)."""
        if agent_name not in self._graphs:
            raise KeyError(f"no Crisis-phase graph for agent {agent_name!r}")
        return self._graphs[agent_name]

    def all_graphs(self) -> dict[str, LamportGraph]:
        return dict(self._graphs)
