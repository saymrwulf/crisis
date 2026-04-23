"""
Communication (Section 4)

Crisis is built on top of two simple push & pull gossip protocols:
1. Member discovery gossip (Algorithm 3)
2. Message gossip (Algorithm 4)

These are well suited for communication in unstructured P2P networks.
All the system needs is a way to distribute messages in a byzantine-prone
environment.

4.3 Member Discovery Gossip (Algorithm 3):
    Each process maintains a partial view Π_j(t) of the network.
    Periodically, a process pushes its neighbor list to a random peer
    and pulls neighbor lists from other peers.

4.4 Message Gossip (Algorithm 4):
    Processes push unordered messages to random peers and pull missing
    messages.  Already ordered messages are pushed only as responses
    to pull requests (stop criterion for push gossip).

This module implements both gossip protocols using asyncio for the
"run in parallel forever" loops described in the paper.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import random
import struct
from dataclasses import dataclass, field
from typing import Optional

from crisis.graph import LamportGraph
from crisis.message import Message, Vertex, NONCE_LENGTH, ID_LENGTH
from crisis.crypto import DIGEST_LENGTH

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Peer identity and network view
# ---------------------------------------------------------------------------

@dataclass
class PeerInfo:
    """Information about a known peer in the network."""
    host: str
    port: int
    process_id: bytes = b""  # The peer's virtual process id, if known

    @property
    def address(self) -> tuple[str, int]:
        return (self.host, self.port)

    def __hash__(self):
        return hash((self.host, self.port))

    def __eq__(self, other):
        if not isinstance(other, PeerInfo):
            return NotImplemented
        return self.host == other.host and self.port == other.port


@dataclass
class NetworkView:
    """Π_j(t): a process's partial view of the network at time t.

    "No process must know the entire system and each j ∈ Π(t) might
    have a partial view Π_j(t) only." (Section 4.3)
    """
    peers: set[PeerInfo] = field(default_factory=set)
    max_peers: int = 50  # Limit to prevent unbounded growth

    def add_peer(self, peer: PeerInfo) -> None:
        if len(self.peers) < self.max_peers:
            self.peers.add(peer)

    def remove_peer(self, peer: PeerInfo) -> None:
        self.peers.discard(peer)

    def random_peer(self) -> Optional[PeerInfo]:
        if not self.peers:
            return None
        return random.choice(list(self.peers))

    def random_subset(self, k: int) -> list[PeerInfo]:
        peers_list = list(self.peers)
        return random.sample(peers_list, min(k, len(peers_list)))


# ---------------------------------------------------------------------------
# Message serialization for network transport
# ---------------------------------------------------------------------------

def serialize_message(message: Message) -> bytes:
    """Serialize a Message for network transmission.

    Format: [total_length:4][nonce:8][id:32][num_digests:2][digests...][payload]
    """
    body = message.serialize()
    length = len(body)
    return struct.pack("!I", length) + body


def deserialize_message(data: bytes) -> Message:
    """Deserialize a Message from network bytes.

    Parses the fixed-size fields and reconstructs the Message object.
    """
    offset = 0
    nonce = data[offset:offset + NONCE_LENGTH]
    offset += NONCE_LENGTH

    id_bytes = data[offset:offset + ID_LENGTH]
    offset += ID_LENGTH

    num_digests = int.from_bytes(data[offset:offset + 2], "big")
    offset += 2

    digests = []
    for _ in range(num_digests):
        d = data[offset:offset + DIGEST_LENGTH]
        digests.append(d)
        offset += DIGEST_LENGTH

    payload = data[offset:]

    return Message(
        nonce=nonce,
        id=id_bytes,
        digests=tuple(digests),
        payload=payload,
    )


# ---------------------------------------------------------------------------
# Protocol message types
# ---------------------------------------------------------------------------

# Simple protocol: 1-byte type prefix
MSG_TYPE_PUSH_MESSAGE = b"\x01"     # Push a crisis message
MSG_TYPE_PULL_REQUEST = b"\x02"     # Request missing messages
MSG_TYPE_PULL_RESPONSE = b"\x03"    # Response with requested messages
MSG_TYPE_PEER_PUSH = b"\x04"       # Push peer list
MSG_TYPE_PEER_PULL = b"\x05"       # Request peer list
MSG_TYPE_PEER_RESPONSE = b"\x06"   # Response with peer list


# ---------------------------------------------------------------------------
# Gossip Server
# ---------------------------------------------------------------------------

class GossipServer:
    """Asyncio-based gossip server implementing Algorithms 3 and 4.

    Runs two parallel loops:
    1. Member discovery push & pull (Algorithm 3)
    2. Message push & pull (Algorithm 4)

    Plus a listener that handles incoming connections.
    """

    def __init__(self, host: str, port: int, graph: LamportGraph,
                 network_view: NetworkView,
                 push_interval: float = 2.0,
                 discovery_interval: float = 5.0):
        self.host = host
        self.port = port
        self.graph = graph
        self.network_view = network_view
        self.push_interval = push_interval
        self.discovery_interval = discovery_interval
        self._server: Optional[asyncio.Server] = None
        self._running = False

    async def start(self) -> None:
        """Start the gossip server and all gossip loops."""
        self._running = True
        self._server = await asyncio.start_server(
            self._handle_connection, self.host, self.port
        )
        logger.info(f"Gossip server listening on {self.host}:{self.port}")

        # Run the gossip loops concurrently (paper: "run in parallel forever")
        await asyncio.gather(
            self._server.serve_forever(),
            self._discovery_push_loop(),
            self._message_push_loop(),
        )

    async def stop(self) -> None:
        """Stop the gossip server."""
        self._running = False
        if self._server:
            self._server.close()
            await self._server.wait_closed()

    # ------------------------------------------------------------------
    # Algorithm 3: Member discovery push & pull
    # ------------------------------------------------------------------

    async def _discovery_push_loop(self) -> None:
        """Algorithm 3, lines 1-5: periodically push peer list to random peers."""
        while self._running:
            await asyncio.sleep(self.discovery_interval)

            peer = self.network_view.random_peer()
            if peer is None:
                continue

            try:
                await self._send_peer_push(peer)
                await self._send_peer_pull(peer)
            except (ConnectionError, OSError) as e:
                logger.debug(f"Discovery push to {peer.address} failed: {e}")
                self.network_view.remove_peer(peer)

    async def _send_peer_push(self, peer: PeerInfo) -> None:
        """Push our peer list to a remote peer."""
        peer_data = self._encode_peer_list(list(self.network_view.peers))
        await self._send_to_peer(peer, MSG_TYPE_PEER_PUSH + peer_data)

    async def _send_peer_pull(self, peer: PeerInfo) -> None:
        """Request a peer list from a remote peer."""
        response = await self._send_and_receive(peer, MSG_TYPE_PEER_PULL)
        if response and response[0:1] == MSG_TYPE_PEER_RESPONSE:
            new_peers = self._decode_peer_list(response[1:])
            for p in new_peers:
                if p.host != self.host or p.port != self.port:
                    self.network_view.add_peer(p)

    # ------------------------------------------------------------------
    # Algorithm 4: Message gossip push & pull
    # ------------------------------------------------------------------

    async def _message_push_loop(self) -> None:
        """Algorithm 4, lines 1-5: push unordered messages to random peers.

        "Messages are retransmitted via push gossip, only if they don't
        have a total order yet." (Section 4.4)
        """
        while self._running:
            await asyncio.sleep(self.push_interval)

            peer = self.network_view.random_peer()
            if peer is None:
                continue

            # Push messages that don't have total_position yet
            unordered = [
                v for v in self.graph.all_vertices()
                if v.total_position is None
            ]

            if not unordered:
                continue

            try:
                for vertex in unordered:
                    msg_bytes = serialize_message(vertex.m)
                    await self._send_to_peer(
                        peer, MSG_TYPE_PUSH_MESSAGE + msg_bytes
                    )
            except (ConnectionError, OSError) as e:
                logger.debug(f"Message push to {peer.address} failed: {e}")

    # ------------------------------------------------------------------
    # Connection handler (incoming)
    # ------------------------------------------------------------------

    async def _handle_connection(self, reader: asyncio.StreamReader,
                                 writer: asyncio.StreamWriter) -> None:
        """Handle an incoming gossip connection.

        Algorithm 3, lines 6-13 (peer data) and Algorithm 4, lines 6-13
        (message data).
        """
        try:
            data = await asyncio.wait_for(reader.read(65536), timeout=10.0)
            if not data:
                return

            msg_type = data[0:1]
            payload = data[1:]

            if msg_type == MSG_TYPE_PUSH_MESSAGE:
                # Received a message: try to extend our Lamport graph
                self._handle_push_message(payload)

            elif msg_type == MSG_TYPE_PULL_REQUEST:
                # Someone wants messages: send what we have
                response = self._handle_pull_request(payload)
                writer.write(response)
                await writer.drain()

            elif msg_type == MSG_TYPE_PEER_PUSH:
                # Received a peer list: update our view
                new_peers = self._decode_peer_list(payload)
                for p in new_peers:
                    if p.host != self.host or p.port != self.port:
                        self.network_view.add_peer(p)

            elif msg_type == MSG_TYPE_PEER_PULL:
                # Someone wants our peer list
                response = MSG_TYPE_PEER_RESPONSE + self._encode_peer_list(
                    list(self.network_view.peers)
                )
                writer.write(response)
                await writer.drain()

        except (asyncio.TimeoutError, ConnectionError):
            pass
        finally:
            writer.close()

    def _handle_push_message(self, data: bytes) -> Optional[Vertex]:
        """Process a pushed message: validate and extend graph if valid.

        Algorithm 4, lines 7-8: "if MESSAGE_INTEGRITY(m, G) then
        expand G with vertex v, such that v.m = m"
        """
        try:
            # Parse length prefix
            if len(data) < 4:
                return None
            length = struct.unpack("!I", data[:4])[0]
            msg_data = data[4:4 + length]

            message = deserialize_message(msg_data)
            return self.graph.extend(message)
        except Exception as e:
            logger.debug(f"Failed to process pushed message: {e}")
            return None

    def _handle_pull_request(self, data: bytes) -> bytes:
        """Respond to a pull request with messages the requester is missing.

        Algorithm 4, lines 10-11: "respond with appropriate set of messages"
        """
        # Data contains a list of digests the requester already has
        known_digests = set()
        offset = 0
        while offset + DIGEST_LENGTH <= len(data):
            known_digests.add(data[offset:offset + DIGEST_LENGTH])
            offset += DIGEST_LENGTH

        # Send messages the requester doesn't have
        response_parts = [MSG_TYPE_PULL_RESPONSE]
        for d, vertex in self.graph.vertices.items():
            if d not in known_digests:
                response_parts.append(serialize_message(vertex.m))
        return b"".join(response_parts)

    # ------------------------------------------------------------------
    # Network I/O helpers
    # ------------------------------------------------------------------

    async def _send_to_peer(self, peer: PeerInfo, data: bytes) -> None:
        """Send data to a peer (fire-and-forget)."""
        reader, writer = await asyncio.open_connection(peer.host, peer.port)
        writer.write(data)
        await writer.drain()
        writer.close()

    async def _send_and_receive(self, peer: PeerInfo, data: bytes) -> Optional[bytes]:
        """Send data and wait for a response."""
        try:
            reader, writer = await asyncio.open_connection(peer.host, peer.port)
            writer.write(data)
            await writer.drain()
            response = await asyncio.wait_for(reader.read(65536), timeout=5.0)
            writer.close()
            return response
        except Exception:
            return None

    # ------------------------------------------------------------------
    # Peer list encoding
    # ------------------------------------------------------------------

    @staticmethod
    def _encode_peer_list(peers: list[PeerInfo]) -> bytes:
        """Encode a list of peers as bytes: [count:2][host_len:1][host][port:2]..."""
        parts = [struct.pack("!H", len(peers))]
        for peer in peers:
            host_bytes = peer.host.encode("utf-8")
            parts.append(struct.pack("!B", len(host_bytes)))
            parts.append(host_bytes)
            parts.append(struct.pack("!H", peer.port))
        return b"".join(parts)

    @staticmethod
    def _decode_peer_list(data: bytes) -> list[PeerInfo]:
        """Decode a peer list from bytes."""
        if len(data) < 2:
            return []
        count = struct.unpack("!H", data[:2])[0]
        offset = 2
        peers = []
        for _ in range(count):
            if offset >= len(data):
                break
            host_len = data[offset]
            offset += 1
            host = data[offset:offset + host_len].decode("utf-8")
            offset += host_len
            port = struct.unpack("!H", data[offset:offset + 2])[0]
            offset += 2
            peers.append(PeerInfo(host=host, port=port))
        return peers
