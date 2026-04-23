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

import os
import random
import time
from dataclasses import dataclass, field
from typing import Optional

from crisis.crypto import digest
from crisis.graph import LamportGraph
from crisis.message import Message, Vertex, ID_LENGTH, NONCE_LENGTH
from crisis.order import LeaderStream, compute_order
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
                 pow_zeros: int = 0, difficulty: int = 2,
                 connectivity_k: int = 1, seed: int = 42):
        self.difficulty_oracle = DifficultyOracle(constant_difficulty=difficulty)
        self.connectivity_k = connectivity_k
        self.weight_system = ProofOfWorkWeight(min_leading_zeros=pow_zeros)
        self.seed = seed
        random.seed(seed)

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

    def step(self) -> dict:
        """Execute one simulation step.

        Returns a dict with step results for display.
        """
        self.step_count += 1
        step_results = {
            "step": self.step_count,
            "new_messages": [],
            "node_states": [],
        }

        # Phase 1: Each node generates a message
        new_messages: list[tuple[SimulatedNode, Message]] = []
        for node in self.nodes:
            if node.is_byzantine:
                msg = self._byzantine_message(node)
            else:
                payload = f"step-{self.step_count}-{node.name}"
                msg = node.generate_message(payload)

            if msg is not None:
                new_messages.append((node, msg))
                step_results["new_messages"].append({
                    "from": node.name,
                    "digest": msg.compute_digest().hex()[:12],
                    "weight": self.weight_system.weight(msg),
                    "payload": msg.payload.decode(errors="replace"),
                })

        # Phase 2: Gossip -- deliver all messages to all nodes
        for source_node, msg in new_messages:
            self.all_messages.append(msg)
            for target_node in self.nodes:
                # Deliver to all nodes (including source, for consistency)
                target_node.graph.extend(msg)

        # Also re-deliver older messages that nodes might be missing
        # (simulates pull gossip catching up)
        for msg in self.all_messages:
            for node in self.nodes:
                node.graph.extend(msg)  # extend() is idempotent (integrity check)

        # Phase 3: Compute consensus on each node
        for node in self.nodes:
            compute_rounds(node.graph, self.difficulty_oracle, self.connectivity_k)

            for vertex in node.graph.all_vertices():
                if vertex.is_last:
                    compute_safe_voting_pattern(
                        vertex, node.graph, self.difficulty_oracle,
                        self.connectivity_k
                    )

            leader_dict: dict[int, list[tuple[int, Message]]] = {}
            for vertex in node.graph.all_vertices():
                if vertex.svp:
                    compute_virtual_leader_election(
                        vertex, node.graph, self.difficulty_oracle,
                        self.connectivity_k, leader_dict
                    )

            for round_num, entries in leader_dict.items():
                for deciding_round, leader_msg in entries:
                    node.leader_stream.update(round_num, deciding_round, leader_msg)

            ordered = compute_order(node.graph, node.leader_stream)

            mr = max_round(node.graph)
            step_results["node_states"].append({
                "name": node.name,
                "vertices": node.graph.vertex_count(),
                "max_round": mr,
                "leaders": len(node.leader_stream.leaders),
                "ordered": len(ordered),
                "is_byzantine": node.is_byzantine,
            })

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

    def run(self, num_steps: int = 10, verbose: bool = True) -> list[dict]:
        """Run the simulation for a number of steps."""
        results = []
        for _ in range(num_steps):
            result = self.step()
            results.append(result)
            if verbose:
                _print_step(result)

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
    parser.add_argument("--pow-zeros", type=int, default=0,
                        help="Min PoW leading zeros (default: 0 = no PoW)")
    parser.add_argument("--difficulty", type=int, default=2,
                        help="Difficulty oracle constant (default: 2)")
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
