"""
Demonstration / Simulation Harness

This module provides a deterministic, single-process simulation of the Crisis
protocol with N virtual nodes.  It is designed as the foundation for a lecture
series: each phase of the protocol can be observed step by step.

The simulation bypasses the network layer entirely -- messages are delivered
directly between in-memory Lamport graphs.  This makes the consensus mechanism
visible without network noise.

Usage:
    python -m crisis.demo                    # Run the full demo
    python -m crisis.demo --nodes 5          # 5 honest nodes
    python -m crisis.demo --byzantine 1      # 1 byzantine node
    python -m crisis.demo --rounds 10        # Run for 10 message rounds
"""

from __future__ import annotations

import math
import os
import random
import time
from dataclasses import dataclass, field
from typing import Optional

from crisis.crypto import digest
from crisis.graph import LamportGraph
from crisis.message import Message, Vertex, ID_LENGTH, NONCE_LENGTH
from crisis.order import LeaderStream, compute_order
from crisis.recorder import (
    EventRecorder, EventType, capture_snapshot,
    record_rounds, record_voting, record_leader_election,
)
from crisis.rounds import compute_rounds, max_round, last_vertices_in_round
from crisis.voting import compute_safe_voting_pattern, compute_virtual_leader_election
from crisis.weight import ProofOfWorkWeight, DifficultyOracle


# ---------------------------------------------------------------------------
# Simulated Node
# ---------------------------------------------------------------------------

@dataclass
class SimulatedNode:
    """A simulated Crisis node running in-memory.

    Each node has its own Lamport graph and process id.  Messages are
    exchanged by directly sharing Message objects (no serialization needed).
    """
    name: str
    process_id: bytes
    graph: LamportGraph
    leader_stream: LeaderStream = field(default_factory=LeaderStream)
    is_byzantine: bool = False
    messages_created: int = 0

    def generate_message(self, payload: str) -> Message:
        """Generate a new message from this node."""
        self.messages_created += 1
        return self.graph.generate_message(
            self.process_id,
            payload.encode(),
        )


# ---------------------------------------------------------------------------
# Network Model — adds realistic delays, drops, silences, and bursts
# ---------------------------------------------------------------------------

@dataclass
class NetworkParams:
    """Tuning knobs for the simulated network.

    Defaults aim for a "messy but converging" environment: a node-pair link
    delivers most messages within 1–3 ticks, drops a few percent outright,
    occasionally silences a node entirely for a step, and occasionally lets
    a node emit a burst of catch-up messages.
    """
    # Per-link delivery delay (ticks). Lognormal so most are short, tail is long.
    delay_mu: float = 0.0         # log-space mean (median ~1 tick)
    delay_sigma: float = 0.5      # log-space stddev — modest tail
    delay_max: int = 3            # hard cap to keep convergence bounded

    # Probability a message is dropped on a given link (gossip eventually
    # re-delivers via the all_messages backlog, so this just slows things).
    drop_rate: float = 0.02

    # Probability that a node skips message generation entirely this step
    # (simulates a slow / partially offline peer).
    silence_prob: float = 0.05

    # Probability that a node "bursts" — emits an extra 1–2 backlogged messages.
    burst_prob: float = 0.03
    burst_extra_max: int = 2

    # How many trailing messages to gossip-replay onto lagging nodes per step.
    # Real gossip protocols heal partition with retransmission; this models
    # that without making the network trivially synchronous.
    catchup_window: int = 30
    catchup_lag_threshold: int = 3   # vertices behind the leader before catch-up


@dataclass
class _Envelope:
    """A pending in-flight delivery."""
    deliver_at: int          # step number when this should be applied
    target: "SimulatedNode"
    source_name: str
    msg: Message


class NetworkModel:
    """Per-link queued delivery with delays, drops, silences, and bursts.

    Each `dispatch()` schedules a delivery for some future step (or none, if
    dropped). `tick()` drains everything due at or before the current step.
    """

    def __init__(self, params: NetworkParams, rng: random.Random):
        self.params = params
        self.rng = rng
        self._pending: list[_Envelope] = []
        # Per-step counters for telemetry (drops, deliveries).
        self.stats = {"sent": 0, "dropped": 0, "delivered": 0, "silenced": 0, "bursts": 0}

    def dispatch(
        self,
        current_step: int,
        msg: "Message",
        source_name: str,
        targets: list["SimulatedNode"],
    ) -> None:
        p = self.params
        for target in targets:
            self.stats["sent"] += 1
            if self.rng.random() < p.drop_rate:
                self.stats["dropped"] += 1
                continue
            # Lognormal delay, capped, with the source-to-itself delivered now.
            if target.name == source_name:
                delay = 0
            else:
                raw = self.rng.lognormvariate(p.delay_mu, p.delay_sigma)
                delay = max(0, min(p.delay_max, int(round(raw))))
            self._pending.append(_Envelope(
                deliver_at=current_step + delay,
                target=target,
                source_name=source_name,
                msg=msg,
            ))

    def tick(self, current_step: int) -> list[_Envelope]:
        """Return (and remove) all envelopes due at or before current_step."""
        due, kept = [], []
        for env in self._pending:
            if env.deliver_at <= current_step:
                due.append(env)
            else:
                kept.append(env)
        self._pending = kept
        self.stats["delivered"] += len(due)
        return due

    def should_silence(self) -> bool:
        return self.rng.random() < self.params.silence_prob

    def burst_extra(self) -> int:
        """How many extra messages a node should emit this step (0 if no burst)."""
        if self.rng.random() < self.params.burst_prob:
            self.stats["bursts"] += 1
            return self.rng.randint(1, max(1, self.params.burst_extra_max))
        return 0


# ---------------------------------------------------------------------------
# Simulation Engine
# ---------------------------------------------------------------------------

class Simulation:
    """Deterministic simulation of N Crisis nodes.

    Runs the protocol in lock-step rounds:
    1. Each node generates a message
    2. Messages are gossiped (delivered to all nodes)
    3. Consensus is computed on each node
    4. State is displayed

    This allows observing how the Lamport graph grows, rounds emerge,
    and total order converges.
    """

    def __init__(self, num_honest: int = 3, num_byzantine: int = 0,
                 pow_zeros: int = 2, difficulty: int = 1,
                 connectivity_k: int = 0, seed: int = 42,
                 recorder: Optional[EventRecorder] = None,
                 network: Optional["NetworkParams"] = None,
                 synchronous: bool = True):
        self.difficulty_oracle = DifficultyOracle(constant_difficulty=difficulty)
        self.connectivity_k = connectivity_k
        self.weight_system = ProofOfWorkWeight(min_leading_zeros=pow_zeros)
        self.seed = seed
        self.recorder = recorder
        random.seed(seed)

        # Network: realistic by default, opt-out for tests via synchronous=True.
        self.synchronous = synchronous
        if synchronous:
            self.network: Optional[NetworkModel] = None
        else:
            params = network or NetworkParams()
            self.network = NetworkModel(params, random.Random(seed ^ 0xA5A5A5))

        # Create nodes
        self.nodes: list[SimulatedNode] = []
        for i in range(num_honest):
            name = f"honest-{i}"
            pid = digest(name.encode())[:ID_LENGTH]
            graph = LamportGraph(weight_system=self.weight_system)
            self.nodes.append(SimulatedNode(
                name=name, process_id=pid, graph=graph
            ))

        for i in range(num_byzantine):
            name = f"byzantine-{i}"
            pid = digest(name.encode())[:ID_LENGTH]
            graph = LamportGraph(weight_system=self.weight_system)
            self.nodes.append(SimulatedNode(
                name=name, process_id=pid, graph=graph, is_byzantine=True
            ))

        self.step_count = 0
        self.all_messages: list[Message] = []
        self.snapshots: list[capture_snapshot.__class__] = []  # type: ignore

    def step(self) -> dict:
        """Execute one simulation step.

        Returns a dict with step results for display.
        """
        self.step_count += 1
        rec = self.recorder

        if rec:
            rec.record(self.step_count, EventType.STEP_BEGIN, "",
                       sim_step=self.step_count)

        step_results = {
            "step": self.step_count,
            "new_messages": [],
            "node_states": [],
        }

        # Phase 1: Each node generates a message (subject to silences/bursts).
        new_messages: list[tuple[SimulatedNode, Message]] = []
        net = self.network
        for node in self.nodes:
            if net is not None and not node.is_byzantine and net.should_silence():
                # Node is "offline" this step — produces nothing.
                net.stats["silenced"] += 1
                continue

            # How many messages this node emits this step: 1, plus optional burst.
            emit_count = 1
            if net is not None and not node.is_byzantine:
                emit_count += net.burst_extra()

            for k in range(emit_count):
                if node.is_byzantine:
                    msg = self._byzantine_message(node)
                else:
                    suffix = "" if k == 0 else f"-burst{k}"
                    payload = f"step-{self.step_count}-{node.name}{suffix}"
                    msg = node.generate_message(payload)
                if msg is None:
                    continue

                new_messages.append((node, msg))
                msg_digest = msg.compute_digest().hex()[:12]
                msg_weight = self.weight_system.weight(msg)

                step_results["new_messages"].append({
                    "from": node.name,
                    "digest": msg_digest,
                    "weight": msg_weight,
                    "payload": msg.payload.decode(errors="replace"),
                })

                if rec:
                    evt = EventType.BYZANTINE_MUTATION if node.is_byzantine else EventType.MESSAGE_CREATED
                    rec.record(
                        self.step_count, evt, node.name,
                        digest_hex=msg_digest,
                        process_id_hex=msg.id.hex()[:8],
                        payload_str=msg.payload.decode(errors="replace")[:60],
                        weight=msg_weight,
                        num_refs=len(msg.digests),
                    )

        # Phase 2: Gossip — queued delivery if a network is in play, otherwise
        # the original synchronous fan-out (used by deterministic tests).
        if net is None:
            for source_node, msg in new_messages:
                self.all_messages.append(msg)
                for target_node in self.nodes:
                    result = target_node.graph.extend(msg)
                    if rec and result is not None:
                        rec.record(
                            self.step_count, EventType.MESSAGE_DELIVERED, target_node.name,
                            digest_hex=msg.compute_digest().hex()[:12],
                            from_node=source_node.name,
                        )
            # Synchronous mode also retransmits the backlog so re-converged
            # nodes catch up.
            for msg in self.all_messages:
                for node in self.nodes:
                    node.graph.extend(msg)
        else:
            # Schedule new envelopes with per-link delays / drops.
            for source_node, msg in new_messages:
                self.all_messages.append(msg)
                net.dispatch(self.step_count, msg, source_node.name, self.nodes)

            # Drain everything due now (including from earlier steps).
            for env in net.tick(self.step_count):
                result = env.target.graph.extend(env.msg)
                if rec and result is not None:
                    rec.record(
                        self.step_count, EventType.MESSAGE_DELIVERED, env.target.name,
                        digest_hex=env.msg.compute_digest().hex()[:12],
                        from_node=env.source_name,
                    )

            # Anti-amnesia: simulate gossip retransmission. Any honest node
            # that's fallen >= catchup_lag_threshold vertices behind the
            # graph leader gets the recent backlog replayed. This is how
            # real gossip heals after drops; without it the sim deadlocks
            # under packet loss because rounds can never quorum-form.
            if self.all_messages:
                counts = [(n, n.graph.vertex_count()) for n in self.nodes]
                leader_count = max(c for _, c in counts)
                threshold = leader_count - self.network.params.catchup_lag_threshold
                tail = self.all_messages[-self.network.params.catchup_window:]
                for n, c in counts:
                    if c < threshold:
                        for msg in tail:
                            n.graph.extend(msg)

        # Phase 3: Compute consensus on each node
        self._last_orders: dict[str, list] = {}
        for node in self.nodes:
            if rec:
                record_rounds(node.graph, self.difficulty_oracle,
                              self.connectivity_k, rec,
                              self.step_count, node.name)
            else:
                compute_rounds(node.graph, self.difficulty_oracle,
                               self.connectivity_k)

            # Compute SVP for all last vertices
            for vertex in node.graph.all_vertices():
                if vertex.is_last:
                    if rec:
                        record_voting(vertex, node.graph,
                                      self.difficulty_oracle,
                                      self.connectivity_k, rec,
                                      self.step_count, node.name)
                    else:
                        compute_safe_voting_pattern(
                            vertex, node.graph, self.difficulty_oracle,
                            self.connectivity_k
                        )

            # Compute leader election in round order
            leader_dict: dict[int, list[tuple[int, Message]]] = {}
            svp_vertices = [v for v in node.graph.all_vertices() if v.svp]
            svp_vertices.sort(key=lambda v: v.round if v.round is not None else 0)

            for vertex in svp_vertices:
                if rec:
                    record_leader_election(
                        vertex, node.graph, self.difficulty_oracle,
                        self.connectivity_k, leader_dict, rec,
                        self.step_count, node.name
                    )
                else:
                    compute_virtual_leader_election(
                        vertex, node.graph, self.difficulty_oracle,
                        self.connectivity_k, leader_dict
                    )

            for round_num, entries in leader_dict.items():
                for deciding_round, leader_msg in entries:
                    node.leader_stream.update(round_num, deciding_round, leader_msg)

            ordered = compute_order(node.graph, node.leader_stream)
            self._last_orders[node.name] = ordered

            if rec:
                rec.record(
                    self.step_count, EventType.ORDER_COMPUTED, node.name,
                    count=len(ordered),
                )

            mr = max_round(node.graph)
            step_results["node_states"].append({
                "name": node.name,
                "vertices": node.graph.vertex_count(),
                "max_round": mr,
                "leaders": len(node.leader_stream.leaders),
                "ordered": len(ordered),
                "is_byzantine": node.is_byzantine,
            })

        if rec:
            rec.record(self.step_count, EventType.STEP_END, "",
                       sim_step=self.step_count)

        return step_results

    def _byzantine_message(self, node: SimulatedNode) -> Optional[Message]:
        """Generate a byzantine message.

        Byzantine nodes can exhibit several faulty behaviors:
        - Mutations: same id, forking the causal chain
        - Strategic distribution: different messages to different peers
        - Time travel: referencing old rounds

        For this demo, we generate a message with a random payload that
        may not reference the latest same-id message (creating a mutation).
        """
        payload = f"byz-{self.step_count}-{node.name}-{random.randint(0, 999)}"

        # 50% chance of creating a mutation (not referencing last same-id vertex)
        if random.random() < 0.5 and node.graph.vertex_count() > 0:
            # Pick random digests instead of following the chain
            available = list(node.graph.vertices.keys())
            num_refs = min(random.randint(1, 3), len(available))
            digests = tuple(random.sample(available, num_refs))
            nonce = os.urandom(NONCE_LENGTH)
            return Message(
                nonce=nonce, id=node.process_id,
                digests=digests, payload=payload.encode()
            )
        else:
            return node.generate_message(payload)

    def run(self, num_steps: int = 10, verbose: bool = True,
            progress_callback=None) -> list[dict]:
        """Run the simulation for a number of steps.

        Args:
            num_steps: Number of simulation steps to run.
            verbose: Print step results to stdout.
            progress_callback: Optional callable(step, total) for progress UI.
        """
        results = []
        for i in range(num_steps):
            result = self.step()
            results.append(result)
            if verbose:
                _print_step(result)

            # Capture snapshot for visualization
            if self.recorder:
                snap = capture_snapshot(self.step_count, self.nodes,
                                        self.weight_system,
                                        precomputed_orders=self._last_orders)
                self.recorder.snapshots.append(snap)

                # Convergence check event
                self.recorder.record(
                    self.step_count, EventType.CONVERGENCE_CHECK, "",
                    convergence=snap.convergence,
                    agreed_prefix=snap.agreed_prefix_length,
                )

            if progress_callback:
                progress_callback(i + 1, num_steps)

        if verbose:
            _print_convergence_summary(self)

        return results


# ---------------------------------------------------------------------------
# Display functions
# ---------------------------------------------------------------------------

def _print_step(result: dict) -> None:
    """Print the results of a simulation step."""
    print(f"\n{'='*70}")
    print(f"  Step {result['step']}")
    print(f"{'='*70}")

    print(f"\n  New messages:")
    for msg in result["new_messages"]:
        print(f"    {msg['from']:>15s} -> {msg['digest']}  "
              f"w={msg['weight']}  {msg['payload'][:40]}")

    print(f"\n  Node states:")
    print(f"    {'Name':>15s}  {'Vertices':>8s}  {'Round':>5s}  "
          f"{'Leaders':>7s}  {'Ordered':>7s}")
    print(f"    {'-'*15}  {'-'*8}  {'-'*5}  {'-'*7}  {'-'*7}")
    for ns in result["node_states"]:
        byz = " [BYZ]" if ns["is_byzantine"] else ""
        print(f"    {ns['name']:>15s}  {ns['vertices']:>8d}  "
              f"{ns['max_round']:>5d}  {ns['leaders']:>7d}  "
              f"{ns['ordered']:>7d}{byz}")


def _print_convergence_summary(sim: Simulation) -> None:
    """Print a summary showing whether honest nodes have converged."""
    print(f"\n{'='*70}")
    print(f"  Convergence Summary")
    print(f"{'='*70}")

    honest_nodes = [n for n in sim.nodes if not n.is_byzantine]

    # Check if all honest nodes have the same total order
    orders = []
    for node in honest_nodes:
        ordered = compute_order(node.graph, node.leader_stream)
        order_digests = [v.message_digest.hex()[:12] for v in ordered]
        orders.append(order_digests)

    if len(orders) >= 2:
        # Compare pairwise
        all_agree = all(o == orders[0] for o in orders[1:])
        if all_agree:
            print(f"\n  All {len(honest_nodes)} honest nodes AGREE "
                  f"on total order ({len(orders[0])} messages)")
        else:
            print(f"\n  Honest nodes have DIVERGENT total orders "
                  f"(convergence in progress)")
            for i, (node, order) in enumerate(zip(honest_nodes, orders)):
                print(f"    {node.name}: {len(order)} ordered messages")

    # Show the total order from the first honest node
    if orders and orders[0]:
        print(f"\n  Total order (from {honest_nodes[0].name}):")
        first_node = honest_nodes[0]
        ordered = compute_order(first_node.graph, first_node.leader_stream)
        for v in ordered[:20]:  # Show first 20
            print(f"    pos={v.total_position:>3d}  "
                  f"hash={v.message_digest.hex()[:12]}  "
                  f"r={v.round}  "
                  f"payload={v.payload.decode(errors='replace')[:40]}")
        if len(ordered) > 20:
            print(f"    ... and {len(ordered) - 20} more")

    # Show leader stream
    if honest_nodes:
        ls = honest_nodes[0].leader_stream
        if ls.leaders:
            print(f"\n  Leader stream ({honest_nodes[0].name}):")
            for round_num, (dec_round, msg) in sorted(ls.leaders.items()):
                print(f"    round {round_num}: leader={msg.compute_digest().hex()[:12]}  "
                      f"decided_in_round={dec_round}")

    print()


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Crisis Protocol Simulation",
        epilog="Demonstrates probabilistic total order convergence"
    )
    parser.add_argument("--nodes", type=int, default=3,
                        help="Number of honest nodes (default: 3)")
    parser.add_argument("--byzantine", type=int, default=0,
                        help="Number of byzantine nodes (default: 0)")
    parser.add_argument("--steps", type=int, default=10,
                        help="Number of simulation steps (default: 10)")
    parser.add_argument("--pow-zeros", type=int, default=2,
                        help="Min PoW leading zeros (default: 2)")
    parser.add_argument("--difficulty", type=int, default=1,
                        help="Difficulty oracle constant (default: 1)")
    parser.add_argument("--seed", type=int, default=42,
                        help="Random seed for reproducibility (default: 42)")

    args = parser.parse_args()

    print(f"Crisis Protocol Simulation")
    print(f"  Honest nodes:   {args.nodes}")
    print(f"  Byzantine nodes: {args.byzantine}")
    print(f"  Steps:          {args.steps}")
    print(f"  PoW zeros:      {args.pow_zeros}")
    print(f"  Difficulty:     {args.difficulty}")
    print(f"  Seed:           {args.seed}")

    sim = Simulation(
        num_honest=args.nodes,
        num_byzantine=args.byzantine,
        pow_zeros=args.pow_zeros,
        difficulty=args.difficulty,
        seed=args.seed,
    )

    sim.run(num_steps=args.steps)


if __name__ == "__main__":
    main()
