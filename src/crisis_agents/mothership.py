"""
Mothership — bootstrap + clock, **not** an observer.

The mothership's only privileged role is starting the network: it knows the
initial member set, it asks each agent to take its turn, and it routes the
first hop of each emission to the sender's chosen target subset. After that
first hop, gossip rounds propagate messages and each agent reaches its own
view of the network.

What the mothership deliberately does NOT do (which the previous version
did, and was correctly criticized for):
  - hold a dict of all agents' LamportGraphs
  - wrap Claims into Crisis Messages on agents' behalf
  - scan any agent's graph for byzantine behavior

Those responsibilities belong to the agents.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

from crisis.weight import ProofOfWorkWeight, WeightSystem

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
    """Audit trail of an emission event during the Crisis phase.

    Kept for proof generation and human-readable demos. Detection itself
    does NOT consult this log — that work happens in each agent's
    `detect_mutations()` against its own graph.
    """
    agent_name: str
    turn: int
    claim: Claim
    message_digest_hex: str
    delivered_to: list[str]


@dataclass
class MothershipRunResult:
    closed_log: list[ClosedPhaseEntry] = field(default_factory=list)
    crisis_log: list[CrisisPhaseEntry] = field(default_factory=list)


class Mothership:
    """Coordinator for a team of CrisisAgents.

    Lifecycle:
        m = Mothership()
        m.add_agent(...); m.add_agent(...); m.add_agent(...)
        m.run_closed_phase(num_turns=1)
        m.open_boundary(joining_agent)
        m.run_crisis_phase(num_turns=2, gossip_rounds_per_turn=1)
        # detection is decentralized — each agent's .detect_mutations()
    """

    def __init__(self, *, pow_zeros: int = 0):
        self.agents: dict[str, CrisisAgent] = {}
        self.boundary = Boundary()
        self.run_result = MothershipRunResult()

        # Shared weight system across the network — every agent's PoW must
        # be verifiable by every other agent's graph, so the threshold has
        # to match. Assigned to each agent's graph at registration time.
        self._weight_system: WeightSystem = ProofOfWorkWeight(min_leading_zeros=pow_zeros)

        self._closed_turn_index = 0
        self._crisis_turn_index = 0

    # ------------------------------------------------------------------
    # Setup
    # ------------------------------------------------------------------

    def add_agent(self, agent: CrisisAgent) -> None:
        """Register a trusted agent for the closed-phase team.

        Replaces the agent's weight system with the mothership's shared one
        so PoW thresholds match across the network.
        """
        if self.boundary.is_open:
            raise RuntimeError("cannot add_agent after boundary opened; use open_boundary")
        if agent.name in self.agents:
            raise ValueError(f"agent {agent.name!r} already added")
        agent.weight_system = self._weight_system
        agent.graph.weight_system = self._weight_system
        self.agents[agent.name] = agent
        self.boundary.add_trusted(agent.process_id)

    # ------------------------------------------------------------------
    # Phase 1: closed
    # ------------------------------------------------------------------

    def run_closed_phase(self, num_turns: int) -> MothershipRunResult:
        """Drive `num_turns` of plain agent communication. No Crisis."""
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
    # Phase 2: boundary opens
    # ------------------------------------------------------------------

    def open_boundary(self, new_agent: CrisisAgent) -> None:
        """A new agent of unknown trust joins. Crisis activates."""
        if new_agent.name in self.agents:
            raise ValueError(f"agent {new_agent.name!r} is already inside the boundary")
        new_agent.weight_system = self._weight_system
        new_agent.graph.weight_system = self._weight_system
        self.agents[new_agent.name] = new_agent
        self.boundary.open(new_agent.process_id)

    # ------------------------------------------------------------------
    # Crisis-phase mechanics: emission → gossip
    # ------------------------------------------------------------------

    def _crisis_received_view(self, agent: CrisisAgent) -> list[Claim]:
        """Decode every non-self vertex in `agent`'s graph back to Claim form.

        Used to populate the `received_claims` argument of `next_turn()` so
        each agent sees what it has actually observed (not what the mothership
        observed — they may differ if gossip has been partial).
        """
        out: list[Claim] = []
        for v in agent.graph.all_vertices():
            if v.id == agent.process_id:
                continue
            try:
                out.append(Claim.from_payload(v.payload))
            except (ValueError, TypeError):
                continue  # non-Claim payloads (e.g. AlarmClaim — phase 23)
        return out

    def run_crisis_phase(self, num_turns: int,
                         *, gossip_rounds_per_turn: int = 1) -> MothershipRunResult:
        """Drive `num_turns` of Crisis-active activity.

        Each turn:
          1. Every agent's `next_turn()` runs; emissions are routed first-hop
             to their declared target_subset (or broadcast to everyone).
          2. `gossip_rounds_per_turn` rounds of all-pairs gossip propagate
             messages across the network.
        """
        if not self.boundary.is_open:
            raise RuntimeError("boundary not yet open; call open_boundary() first")

        all_names = list(self.agents.keys())

        for _ in range(num_turns):
            turn = self._crisis_turn_index

            # (1) Emission phase — ask each agent what they want to say.
            #     The agent builds the Crisis Message from its own graph.
            #     The mothership only handles the first-hop routing.
            for agent in self.agents.values():
                received = self._crisis_received_view(agent)
                for at in agent.next_turn(turn, received):
                    self._route_emission(agent, turn, at, all_names)

            # (2) Gossip — each pair exchanges what they have until quiescent.
            for _ in range(gossip_rounds_per_turn):
                self.run_gossip_round()

            self._crisis_turn_index += 1

        return self.run_result

    def _route_emission(self, sender: CrisisAgent, turn: int, at: AgentTurn,
                        all_names: list[str]) -> None:
        """First-hop delivery + audit log entry.

        Delivery rule (same as before — kept for byzantine equivocation):
          - target_subset is None  ⇒ broadcast (every agent including sender)
          - target_subset is set   ⇒ targeted; sender's own graph NOT auto-included
        """
        if at.target_subset is None:
            targets = list(all_names)
        else:
            targets = [t for t in at.target_subset if t in self.agents]

        # The agent wraps the Claim using its own graph as the source of truth.
        message = sender.emit_claim(at.claim)

        for tname in targets:
            self.agents[tname].receive(message)

        self.run_result.crisis_log.append(
            CrisisPhaseEntry(
                agent_name=sender.name,
                turn=turn,
                claim=at.claim,
                message_digest_hex=message.compute_digest().hex(),
                delivered_to=targets,
            )
        )

    def run_gossip_round(self) -> dict[tuple[str, str], int]:
        """One all-pairs gossip round.

        For every ordered pair (sender, receiver), the sender shares everything
        in its graph that the receiver doesn't yet have. Returns a dict mapping
        (sender_name, receiver_name) -> number of newly-accepted vertices.

        Order matters mildly: if A -> B propagates new info to B that B then
        re-emits to C, that's covered in this same round only if A appears
        before B in the iteration. We loop until no progress to avoid edge
        cases. In practice one ordered pass is usually enough.
        """
        names = list(self.agents.keys())
        transfers: dict[tuple[str, str], int] = {}
        for s_name in names:
            for r_name in names:
                if s_name == r_name:
                    continue
                n = self.agents[s_name].gossip_to(self.agents[r_name])
                if n:
                    transfers[(s_name, r_name)] = n
        return transfers

    # ------------------------------------------------------------------
    # Decentralized alarm flow — orchestration only; the work is per-agent
    # ------------------------------------------------------------------

    def emit_alarms_from_detectors(self,
                                    *, accuse_self_ok: bool = False
                                    ) -> dict[str, list]:
        """Every agent independently runs `detect_mutations()` on its own
        graph; any LocalAlarms it produces become AlarmClaims that the agent
        emits into the gossip layer (broadcast).

        Returns a dict mapping agent_name -> list[LocalAlarm] (what each
        agent independently found). Callers can use this for diagnostics
        without ever having read into an agent's graph directly.

        The byzantine joiner will of course not emit alarms about itself.
        If `accuse_self_ok` is False (the default), we additionally skip
        any LocalAlarm whose `detector_process_id_hex` matches the
        `accused_process_id_hex` — sanity guard against malformed cases.
        """
        from crisis_agents.vote import AlarmClaim

        all_local: dict[str, list] = {}
        for agent in self.agents.values():
            locals_for_agent = agent.detect_mutations()
            if not accuse_self_ok:
                locals_for_agent = [
                    a for a in locals_for_agent
                    if a.detector_process_id_hex != a.accused_process_id_hex
                ]
            all_local[agent.name] = locals_for_agent

            for local in locals_for_agent:
                alarm_claim = AlarmClaim.from_local_alarm(
                    local, detected_at_turn=self._crisis_turn_index,
                )
                # Wrap the AlarmClaim's payload into a Crisis Message and
                # broadcast it. We bypass the Claim/AgentTurn machinery
                # because AlarmClaim is a different payload schema.
                self._broadcast_alarm(agent, alarm_claim)

        return all_local

    def _broadcast_alarm(self, sender: CrisisAgent, alarm_claim) -> None:
        """Wrap an AlarmClaim into a Crisis Message via the sender's
        `emit_claim` machinery (re-using the digest-build + PoW path)
        but with the AlarmClaim payload, and broadcast it to all peers
        (including the sender so its own ratified set is consistent)."""
        # We can't pass a non-Claim into emit_claim directly because emit_claim
        # types its argument as Claim. Hack-around: build the Message manually
        # using the same chain/cross-ref logic as emit_claim. Cleaner
        # alternative is to refactor emit_claim to accept any payload-bytes
        # producer; for now this duplication is minor.
        import os
        from crisis.message import Message, NONCE_LENGTH
        from crisis.weight import ProofOfWorkWeight

        payload = alarm_claim.to_payload()

        digests_list: list[bytes] = []
        same_id = [v for v in sender.graph.all_vertices() if v.id == sender.process_id]
        past_digests: set[bytes] = set()
        if same_id:
            referenced = set()
            for v in same_id:
                for d in v.digests:
                    ref = sender.graph.get_vertex(d)
                    if ref is not None and ref.id == sender.process_id:
                        referenced.add(d)
            last = next(
                (v for v in same_id if v.message_digest not in referenced),
                same_id[-1],
            )
            digests_list.append(last.message_digest)
            past_digests = {v.message_digest for v in sender.graph.past(last)}

        seen_other_ids: set[bytes] = {sender.process_id}
        for v in sender.graph.all_vertices():
            if v.id in seen_other_ids:
                continue
            if v.message_digest in past_digests:
                continue
            digests_list.append(v.message_digest)
            seen_other_ids.add(v.id)

        if isinstance(sender.weight_system, ProofOfWorkWeight):
            message = sender.weight_system.mine_nonce(
                sender.process_id, tuple(digests_list), payload,
            )
        else:
            message = Message(
                nonce=os.urandom(NONCE_LENGTH),
                id=sender.process_id,
                digests=tuple(digests_list),
                payload=payload,
            )

        for target in self.agents.values():
            target.receive(message)

    def ratified_alarms_from(self, agent_name: str):
        """Get the ratified alarms as seen from one agent's graph.

        With sufficient gossip, every honest agent's graph produces the same
        ratified set — and the test in test_no_chokepoint.py asserts that.
        """
        from crisis_agents.vote import quorum_for, tally_alarms
        threshold = quorum_for(self.boundary.size())
        graph = self.agents[agent_name].graph
        return tally_alarms(graph, quorum_threshold=threshold)

    # ------------------------------------------------------------------
    # Convenience accessors
    # ------------------------------------------------------------------

    def honest_agents(self) -> list[CrisisAgent]:
        """The agents trusted at the start (closed-phase team) — i.e. every
        agent except the boundary-opener. Use only as a demo aid; in a real
        network the mothership doesn't reliably know who's honest."""
        if not self.boundary.is_open:
            return list(self.agents.values())
        # The boundary-opener is added last via open_boundary(); peel it off.
        all_agents = list(self.agents.values())
        return all_agents[:-1]

    def joiner(self) -> Optional[CrisisAgent]:
        """The boundary-opener, if any."""
        if not self.boundary.is_open:
            return None
        return list(self.agents.values())[-1]
