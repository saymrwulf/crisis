"""
Mothership — bootstrap + asynchronous driver.

Two roles, both unprivileged:

  1. Bootstrap. The mothership knows the initial member set, introduces a
     joining agent into the boundary, and offers convenience accessors for
     tests. It never reads any agent's internal state in ways that would
     bypass the protocol.

  2. Driver. The mothership runs an event-loop-like cycle that asks each
     agent for any pending emissions, exchanges gossip between any pair,
     and asks each agent for any pending alarm claims — all interleaved
     in one loop until quiescent. There is no global clock; the driver
     is the in-process analog of "agents run their gossip + emission
     loops concurrently forever" that Section 5.9 of the paper describes.

What the mothership deliberately does NOT have:
  - a synchronous turn counter exposed to agents
  - a privileged graph store
  - any post-hoc scan over per-agent state

Termination is by quiescence: when no agent emits, no gossip pair has new
information, and no fresh alarms appear, the loop exits.
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
    """One row in the closed-phase log.

    `step` is a local sequence number used only for log ordering — it is
    NOT a global tick the agents observe.
    """
    agent_name: str
    step: int
    claim: Claim


@dataclass
class CrisisPhaseEntry:
    """Audit trail of an emission event during the Crisis phase.

    `step` is a local sequence number. Detection itself does not consult
    this log — that work happens in each agent's own `detect_mutations()`.
    """
    agent_name: str
    step: int
    claim: Claim
    message_digest_hex: str
    delivered_to: list[str]


@dataclass
class MothershipRunResult:
    closed_log: list[ClosedPhaseEntry] = field(default_factory=list)
    crisis_log: list[CrisisPhaseEntry] = field(default_factory=list)


@dataclass(frozen=True)
class QuiescenceReport:
    """How a driver loop terminated."""
    steps: int
    emissions: int
    gossip_transfers: int
    alarm_claims_emitted: int
    reached_quiescence: bool   # True iff loop exited because nothing changed
                               # (False iff max_steps was hit first)


class Mothership:
    """Coordinator for a team of CrisisAgents.

    Lifecycle:
        m = Mothership()
        m.add_agent(...); m.add_agent(...); m.add_agent(...)
        m.run_closed_phase()       # async until quiescent (no clock)
        m.open_boundary(joiner)
        m.run_until_quiescent()    # async until quiescent (no clock)
        # detection is decentralized — m.ratified_alarms_from("agent_alpha")
    """

    def __init__(self, *, pow_zeros: int = 0):
        self.agents: dict[str, CrisisAgent] = {}
        self.boundary = Boundary()
        self.run_result = MothershipRunResult()

        # Shared weight system so every agent's PoW is verifiable by every
        # other agent's graph.
        self._weight_system: WeightSystem = ProofOfWorkWeight(min_leading_zeros=pow_zeros)

    # ------------------------------------------------------------------
    # Setup
    # ------------------------------------------------------------------

    def add_agent(self, agent: CrisisAgent) -> None:
        """Register a trusted agent for the closed-phase team."""
        if self.boundary.is_open:
            raise RuntimeError("cannot add_agent after boundary opened; use open_boundary")
        if agent.name in self.agents:
            raise ValueError(f"agent {agent.name!r} already added")
        agent.weight_system = self._weight_system
        agent.graph.weight_system = self._weight_system
        self.agents[agent.name] = agent
        self.boundary.add_trusted(agent.process_id)

    def open_boundary(self, new_agent: CrisisAgent) -> None:
        """A new agent of unknown trust joins. Crisis activates."""
        if new_agent.name in self.agents:
            raise ValueError(f"agent {new_agent.name!r} is already inside the boundary")
        new_agent.weight_system = self._weight_system
        new_agent.graph.weight_system = self._weight_system
        self.agents[new_agent.name] = new_agent
        self.boundary.open(new_agent.process_id)

    # ------------------------------------------------------------------
    # Closed phase — quiescence-driven, not turn-counted
    # ------------------------------------------------------------------

    def run_closed_phase(self, max_steps: int = 50) -> QuiescenceReport:
        """Drive the closed-phase conversation until quiescent.

        Each iteration, each agent's `try_emit()` is called. Emitted claims
        are appended to the closed log and broadcast (via `observe`) to
        every other agent for context. The loop exits when no agent emits.
        """
        if self.boundary.is_open:
            raise RuntimeError("boundary already open; closed phase is over")

        step = 0
        emissions = 0
        progress = True
        while progress and step < max_steps:
            progress = False
            for agent in self.agents.values():
                for at in agent.try_emit():
                    self.run_result.closed_log.append(
                        ClosedPhaseEntry(agent_name=agent.name, step=step, claim=at.claim)
                    )
                    emissions += 1
                    progress = True
                    # Share to every other agent's observation buffer
                    for peer_name, peer in self.agents.items():
                        if peer_name == agent.name:
                            continue
                        peer.observe(at.claim)
            step += 1

        return QuiescenceReport(
            steps=step,
            emissions=emissions,
            gossip_transfers=0,
            alarm_claims_emitted=0,
            reached_quiescence=(step < max_steps or not progress),
        )

    # ------------------------------------------------------------------
    # Crisis phase — fully asynchronous event loop
    # ------------------------------------------------------------------

    def run_until_quiescent(self, max_steps: int = 200) -> QuiescenceReport:
        """Drive the Crisis-active network until nothing changes.

        Each iteration of the loop interleaves three concerns:

          1. **Emission.** For every agent, call `try_emit()`. Route any
             returned emissions to their target subset.
          2. **Gossip.** Run one all-pairs gossip round. Each receiver
             accepts vertices that pass integrity checks.
          3. **Alarm emission.** For every agent, call `pending_alarm_claims()`.
             Wrap each into a Crisis Message and broadcast.

        These are not phases — they're things the driver tries on each
        step. The loop exits when none of them makes progress.
        """
        if not self.boundary.is_open:
            raise RuntimeError("boundary not yet open; call open_boundary() first")

        step = 0
        emissions = 0
        gossip_transfers = 0
        alarms_emitted = 0
        all_names = list(self.agents.keys())

        while step < max_steps:
            progress = False

            # 1. Emissions
            for agent in self.agents.values():
                for at in agent.try_emit():
                    self._route_emission(agent, step, at, all_names)
                    emissions += 1
                    progress = True

            # 2. Gossip
            transfers = self.run_gossip_round()
            if transfers:
                gossip_transfers += sum(transfers.values())
                progress = True

            # 3. Alarm emissions
            for agent in self.agents.values():
                for ac in agent.pending_alarm_claims():
                    self._broadcast_alarm(agent, ac)
                    alarms_emitted += 1
                    progress = True

            step += 1
            if not progress:
                break

        return QuiescenceReport(
            steps=step,
            emissions=emissions,
            gossip_transfers=gossip_transfers,
            alarm_claims_emitted=alarms_emitted,
            reached_quiescence=(step < max_steps),
        )

    def _route_emission(self, sender: CrisisAgent, step: int, at: AgentTurn,
                        all_names: list[str]) -> None:
        """First-hop delivery + audit log entry.

          - target_subset=None ⇒ broadcast (every agent including sender)
          - target_subset=set  ⇒ targeted; sender's own graph NOT auto-included
        """
        if at.target_subset is None:
            targets = list(all_names)
        else:
            targets = [t for t in at.target_subset if t in self.agents]

        message = sender.emit_claim(at.claim)
        for tname in targets:
            self.agents[tname].receive(message)

        self.run_result.crisis_log.append(
            CrisisPhaseEntry(
                agent_name=sender.name,
                step=step,
                claim=at.claim,
                message_digest_hex=message.compute_digest().hex(),
                delivered_to=targets,
            )
        )

    def _broadcast_alarm(self, sender: CrisisAgent, alarm_claim) -> None:
        """Wrap an AlarmClaim into a Crisis Message and deliver to every
        agent (including sender, so its own tally is consistent)."""
        payload = alarm_claim.to_payload()
        message = sender._build_message(payload)
        for target in self.agents.values():
            target.receive(message)

    def run_gossip_round(self) -> dict[tuple[str, str], int]:
        """One all-pairs gossip round.

        For every ordered pair (sender, receiver), the sender shares
        everything in its graph that the receiver doesn't yet have.
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
    # Decentralized alarm tally — convenience method
    # ------------------------------------------------------------------

    def ratified_alarms_from(self, agent_name: str):
        """Get the ratified alarms as seen from one agent's graph.

        With sufficient gossip, every honest agent's graph produces the
        same ratified set — asserted by `test_no_chokepoint.py`.
        """
        from crisis_agents.vote import quorum_for, tally_alarms
        threshold = quorum_for(self.boundary.size())
        graph = self.agents[agent_name].graph
        return tally_alarms(graph, quorum_threshold=threshold)

    # ------------------------------------------------------------------
    # Convenience accessors
    # ------------------------------------------------------------------

    def honest_agents(self) -> list[CrisisAgent]:
        """The closed-phase team (every agent except the boundary-opener)."""
        if not self.boundary.is_open:
            return list(self.agents.values())
        all_agents = list(self.agents.values())
        return all_agents[:-1]

    def joiner(self) -> Optional[CrisisAgent]:
        if not self.boundary.is_open:
            return None
        return list(self.agents.values())[-1]
