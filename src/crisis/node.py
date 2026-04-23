"""
Crisis Node (Section 5.9 -- The Crisis Protocol)

This module ties all components together into a full Crisis node.

From the paper (Section 5.9):
    "The overall algorithm works as follows: Member discovery (3) and
    message gossip (4) are executed in infinite loops, concurrently to
    the rest of the system.  Ideally the message sending loop is executed
    on as many parallel threads as possible.  This implies that an overall
    unbounded amount of new messages arrive over time due to our liveness
    assumption.  In addition each process may generate messages and write
    them into its own Lamport graph."

The full node runs these concurrent loops:
    1. Gossip: member discovery + message dissemination
    2. Message generation: create new messages with PoW
    3. Consensus: compute rounds, voting patterns, leader elections, order

Each loop runs independently and they communicate through the shared
Lamport graph.
"""

from __future__ import annotations

import asyncio
import logging
import os
import time
from typing import Optional

from crisis.crypto import digest
from crisis.graph import LamportGraph
from crisis.gossip import GossipServer, NetworkView, PeerInfo
from crisis.message import Message, Vertex, ID_LENGTH, NONCE_LENGTH
from crisis.order import LeaderStream, compute_order
from crisis.rounds import compute_rounds
from crisis.voting import compute_virtual_leader_election, compute_safe_voting_pattern
from crisis.weight import ProofOfWorkWeight, DifficultyOracle

logger = logging.getLogger(__name__)


class CrisisNode:
    """A full Crisis protocol node.

    Combines all protocol components into a single running process:
    - Lamport graph (the shared DAG)
    - Weight system (PoW)
    - Difficulty oracle
    - Gossip server (member discovery + message dissemination)
    - Consensus engine (rounds, voting, ordering)

    Attributes:
        process_id:     This node's virtual process identity.
        graph:          The local Lamport graph.
        leader_stream:  The evolving total order leader stream.
        network_view:   Known peers in the network.
    """

    def __init__(self, host: str = "127.0.0.1", port: int = 9000,
                 min_pow_zeros: int = 1,
                 difficulty_constant: int = 4,
                 connectivity_k: int = 2,
                 message_interval: float = 3.0,
                 consensus_interval: float = 5.0,
                 seed_peers: list[tuple[str, int]] | None = None):
        # Identity: use a hash of host:port as this node's virtual process id
        self.process_id = digest(f"{host}:{port}".encode())[:ID_LENGTH]
        self.host = host
        self.port = port

        # Protocol components
        self.weight_system = ProofOfWorkWeight(min_leading_zeros=min_pow_zeros)
        self.difficulty = DifficultyOracle(constant_difficulty=difficulty_constant)
        self.connectivity_k = connectivity_k
        self.graph = LamportGraph(weight_system=self.weight_system)
        self.leader_stream = LeaderStream()

        # Timing
        self.message_interval = message_interval
        self.consensus_interval = consensus_interval

        # Network
        self.network_view = NetworkView()
        if seed_peers:
            for h, p in seed_peers:
                self.network_view.add_peer(PeerInfo(host=h, port=p))

        self.gossip = GossipServer(
            host=host, port=port,
            graph=self.graph,
            network_view=self.network_view,
        )

        # State
        self._running = False
        self._message_count = 0

        # Callbacks for monitoring
        self.on_new_vertex: Optional[callable] = None
        self.on_round_update: Optional[callable] = None
        self.on_order_update: Optional[callable] = None

    # ------------------------------------------------------------------
    # Main entry point
    # ------------------------------------------------------------------

    async def run(self) -> None:
        """Start all protocol loops concurrently.

        This is the Crisis protocol (Section 5.9): three concurrent loops.
        """
        self._running = True
        logger.info(
            f"Crisis node starting on {self.host}:{self.port} "
            f"(id={self.process_id.hex()[:16]}...)"
        )

        try:
            await asyncio.gather(
                self._gossip_loop(),
                self._message_generation_loop(),
                self._consensus_loop(),
            )
        except asyncio.CancelledError:
            logger.info("Crisis node shutting down")
        finally:
            self._running = False

    async def stop(self) -> None:
        self._running = False
        await self.gossip.stop()

    # ------------------------------------------------------------------
    # Loop 1: Gossip (Algorithms 3 & 4)
    # ------------------------------------------------------------------

    async def _gossip_loop(self) -> None:
        """Run the gossip server (member discovery + message dissemination)."""
        try:
            await self.gossip.start()
        except Exception as e:
            logger.error(f"Gossip loop error: {e}")

    # ------------------------------------------------------------------
    # Loop 2: Message generation (Algorithm 1)
    # ------------------------------------------------------------------

    async def _message_generation_loop(self) -> None:
        """Periodically generate new messages and add them to the graph.

        Each message:
        1. References the last same-id message (chain constraint)
        2. References a sample of other vertices (cross-links for connectivity)
        3. Has a PoW nonce meeting the weight threshold
        4. Carries an application payload
        """
        while self._running:
            await asyncio.sleep(self.message_interval)

            try:
                payload = self._generate_payload()
                message = self.graph.generate_message(
                    self.process_id, payload, self.weight_system
                )
                vertex = self.graph.extend(message)

                if vertex is not None:
                    self._message_count += 1
                    logger.debug(
                        f"Generated message #{self._message_count}: {vertex}"
                    )
                    if self.on_new_vertex:
                        self.on_new_vertex(vertex)

            except Exception as e:
                logger.error(f"Message generation error: {e}")

    def _generate_payload(self) -> bytes:
        """Generate a payload for a new message.

        In this PoC, payloads are simple timestamped entries.
        A real application would put actual data here.
        """
        self._message_count += 1
        return f"msg-{self._message_count}-{time.time():.3f}".encode()

    # ------------------------------------------------------------------
    # Loop 3: Consensus (Algorithms 5, 6, 7, 9, 10)
    # ------------------------------------------------------------------

    async def _consensus_loop(self) -> None:
        """Periodically recompute consensus state.

        From Section 5.9 and the proof section (Section 6):
        "algorithms (5), (6) and (7) are executed in that order concurrently
        on each vertex from V... the total order loop (9) runs concurrently
        and waits for updates of the leader stream."
        """
        while self._running:
            await asyncio.sleep(self.consensus_interval)

            if self.graph.vertex_count() == 0:
                continue

            try:
                # Step 1: Compute rounds (Algorithm 5)
                compute_rounds(self.graph, self.difficulty, self.connectivity_k)

                if self.on_round_update:
                    self.on_round_update(self.graph)

                # Step 2: Compute safe voting patterns (Algorithm 6)
                for vertex in self.graph.all_vertices():
                    if vertex.is_last:
                        compute_safe_voting_pattern(
                            vertex, self.graph, self.difficulty,
                            self.connectivity_k
                        )

                # Step 3: Virtual leader election (Algorithm 7)
                leader_dict: dict[int, list[tuple[int, Message]]] = {}
                for vertex in self.graph.all_vertices():
                    if vertex.svp:
                        compute_virtual_leader_election(
                            vertex, self.graph, self.difficulty,
                            self.connectivity_k, leader_dict
                        )

                # Update leader stream from election results
                for round_num, entries in leader_dict.items():
                    for deciding_round, leader_msg in entries:
                        self.leader_stream.update(
                            round_num, deciding_round, leader_msg
                        )

                # Step 4: Compute total order (Algorithms 9 & 10)
                ordered = compute_order(self.graph, self.leader_stream)

                if ordered and self.on_order_update:
                    self.on_order_update(ordered)

                logger.debug(
                    f"Consensus: {self.graph.vertex_count()} vertices, "
                    f"{len(self.leader_stream.leaders)} leaders, "
                    f"{len(ordered)} ordered"
                )

            except Exception as e:
                logger.error(f"Consensus loop error: {e}")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def submit_message(self, payload: bytes) -> Optional[Vertex]:
        """Submit an application message to be ordered by the protocol."""
        message = self.graph.generate_message(
            self.process_id, payload, self.weight_system
        )
        return self.graph.extend(message)

    def get_total_order(self) -> list[tuple[int, bytes]]:
        """Get the current total order as (position, payload) pairs."""
        ordered = compute_order(self.graph, self.leader_stream)
        return [
            (v.total_position, v.payload)
            for v in ordered
            if v.total_position is not None
        ]

    def status(self) -> dict:
        """Return a summary of this node's current state."""
        from crisis.rounds import max_round as get_max_round
        return {
            "process_id": self.process_id.hex()[:16],
            "address": f"{self.host}:{self.port}",
            "vertices": self.graph.vertex_count(),
            "process_ids": len(self.graph.all_process_ids()),
            "max_round": get_max_round(self.graph),
            "leaders": len(self.leader_stream.leaders),
            "peers": len(self.network_view.peers),
            "messages_generated": self._message_count,
        }


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main():
    """Run a Crisis node from the command line."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Crisis Protocol Node",
        epilog="Probabilistically self-organizing total order in P2P networks"
    )
    parser.add_argument("--host", default="127.0.0.1", help="Listen address")
    parser.add_argument("--port", type=int, default=9000, help="Listen port")
    parser.add_argument("--pow-zeros", type=int, default=1,
                        help="Min PoW leading zeros (weight threshold)")
    parser.add_argument("--difficulty", type=int, default=4,
                        help="Difficulty oracle constant")
    parser.add_argument("--msg-interval", type=float, default=3.0,
                        help="Seconds between message generation")
    parser.add_argument("--peers", nargs="*", default=[],
                        help="Seed peers as host:port")

    args = parser.parse_args()

    seed_peers = []
    for peer_str in args.peers:
        h, p = peer_str.rsplit(":", 1)
        seed_peers.append((h, int(p)))

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s"
    )

    node = CrisisNode(
        host=args.host,
        port=args.port,
        min_pow_zeros=args.pow_zeros,
        difficulty_constant=args.difficulty,
        seed_peers=seed_peers,
        message_interval=args.msg_interval,
    )

    asyncio.run(node.run())


if __name__ == "__main__":
    main()
