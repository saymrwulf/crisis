"""
Event Recording System for Crisis Protocol Visualization

Records all protocol events during a simulation run, producing a structured
event log and per-step snapshots.  The visualization application replays
these recordings with full timeline control.

Design: instrumentation wrappers diff state before/after calling the original
protocol functions, so the core algorithm files remain unmodified.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Any, Optional

from crisis.graph import LamportGraph
from crisis.message import Vertex
from crisis.order import LeaderStream, compute_order
from crisis.rounds import compute_rounds, max_round
from crisis.voting import (
    compute_safe_voting_pattern,
    compute_virtual_leader_election,
)
from crisis.weight import DifficultyOracle


# ---------------------------------------------------------------------------
# Event Types
# ---------------------------------------------------------------------------

class EventType(Enum):
    # Phase 1: Message generation
    MESSAGE_CREATED = auto()
    BYZANTINE_MUTATION = auto()

    # Phase 2: Gossip / delivery
    MESSAGE_DELIVERED = auto()

    # Phase 3: Consensus
    ROUND_ASSIGNED = auto()
    VERTEX_BECOMES_LAST = auto()
    SVP_COMPUTED = auto()
    VOTE_CAST = auto()
    LEADER_ELECTED = auto()
    ORDER_COMPUTED = auto()

    # Meta
    STEP_BEGIN = auto()
    STEP_END = auto()
    CONVERGENCE_CHECK = auto()


# ---------------------------------------------------------------------------
# Event
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class SimEvent:
    """A single recorded protocol event."""
    seq: int
    step: int
    event_type: EventType
    node_name: str
    data: dict[str, Any]


# ---------------------------------------------------------------------------
# Snapshots
# ---------------------------------------------------------------------------

@dataclass
class VertexSnapshot:
    """Snapshot of a single vertex at a point in time."""
    digest_hex: str          # 12-char hex prefix for display
    digest_full: str         # full hex for lookup
    process_id_hex: str      # 8-char hex prefix
    round_number: Optional[int] = None
    is_last: bool = False
    weight: int = 0
    payload_str: str = ""
    total_position: Optional[int] = None
    svp: list[int] = field(default_factory=list)
    is_byzantine_source: bool = False


@dataclass
class NodeSnapshot:
    """Snapshot of a node's full state at a given step."""
    name: str
    step: int
    vertex_count: int = 0
    max_round: int = 0
    num_leaders: int = 0
    num_ordered: int = 0
    is_byzantine: bool = False
    vertices: list[VertexSnapshot] = field(default_factory=list)
    edges: list[tuple[str, str]] = field(default_factory=list)  # (from_hex, to_hex)
    leader_rounds: dict[int, str] = field(default_factory=dict)  # round -> leader digest_hex


@dataclass
class StepSnapshot:
    """Full simulation state captured at a step boundary."""
    step: int
    node_snapshots: dict[str, NodeSnapshot] = field(default_factory=dict)
    convergence: bool = False
    agreed_prefix_length: int = 0


# ---------------------------------------------------------------------------
# EventRecorder
# ---------------------------------------------------------------------------

class EventRecorder:
    """Accumulates events and snapshots during a simulation run."""

    def __init__(self):
        self.events: list[SimEvent] = []
        self.snapshots: list[StepSnapshot] = []
        self._seq = 0

    def record(self, step: int, event_type: EventType,
               node_name: str, **data) -> SimEvent:
        self._seq += 1
        event = SimEvent(self._seq, step, event_type, node_name, data)
        self.events.append(event)
        return event

    def events_at_step(self, step: int) -> list[SimEvent]:
        return [e for e in self.events if e.step == step]

    def events_of_type(self, et: EventType) -> list[SimEvent]:
        return [e for e in self.events if e.event_type == et]

    def max_step(self) -> int:
        return max((e.step for e in self.events), default=0)


# ---------------------------------------------------------------------------
# Snapshot capture
# ---------------------------------------------------------------------------

def capture_snapshot(step: int, nodes, weight_system,
                     precomputed_orders: dict | None = None) -> StepSnapshot:
    """Capture a full StepSnapshot from the current simulation state.

    Args:
        step: The simulation step number.
        nodes: List of SimulatedNode objects.
        weight_system: The weight system for computing vertex weights.
        precomputed_orders: Optional dict node_name -> list[Vertex] to skip
            recomputing total order (expensive).
    """
    snap = StepSnapshot(step=step)

    for node in nodes:
        g = node.graph
        mr = max_round(g)
        if precomputed_orders and node.name in precomputed_orders:
            ordered = precomputed_orders[node.name]
        else:
            ordered = compute_order(g, node.leader_stream)

        # Build vertex snapshots
        v_snaps = []
        for v in g.all_vertices():
            vs = VertexSnapshot(
                digest_hex=v.message_digest.hex()[:12],
                digest_full=v.message_digest.hex(),
                process_id_hex=v.id.hex()[:8],
                round_number=v.round,
                is_last=bool(v.is_last),
                weight=weight_system.weight(v.m),
                payload_str=v.payload.decode(errors="replace")[:60],
                total_position=v.total_position,
                svp=list(v.svp) if v.svp else [],
            )
            v_snaps.append(vs)

        # Build edge list
        edge_list = []
        for d_from, refs in g.edges.items():
            from_hex = d_from.hex()[:12]
            for d_to in refs:
                if d_to in g.vertices:
                    edge_list.append((from_hex, d_to.hex()[:12]))

        # Leader digest map
        leader_rounds = {}
        for rn, (_, msg) in node.leader_stream.leaders.items():
            leader_rounds[rn] = msg.compute_digest().hex()[:12]

        ns = NodeSnapshot(
            name=node.name,
            step=step,
            vertex_count=g.vertex_count(),
            max_round=mr,
            num_leaders=len(node.leader_stream.leaders),
            num_ordered=len(ordered),
            is_byzantine=node.is_byzantine,
            vertices=v_snaps,
            edges=edge_list,
            leader_rounds=leader_rounds,
        )
        snap.node_snapshots[node.name] = ns

    # Convergence check across honest nodes
    honest = [n for n in nodes if not n.is_byzantine]
    if len(honest) >= 2:
        orders = []
        for n in honest:
            if precomputed_orders and n.name in precomputed_orders:
                o = precomputed_orders[n.name]
            else:
                o = compute_order(n.graph, n.leader_stream)
            orders.append([v.message_digest.hex()[:12] for v in o])
        # Find longest common prefix
        if orders:
            min_len = min(len(o) for o in orders)
            agreed = 0
            for i in range(min_len):
                if all(o[i] == orders[0][i] for o in orders[1:]):
                    agreed = i + 1
                else:
                    break
            snap.agreed_prefix_length = agreed
            snap.convergence = (agreed == min_len and min_len > 0
                                and all(len(o) == len(orders[0]) for o in orders))

    return snap


# ---------------------------------------------------------------------------
# Instrumentation wrappers
# ---------------------------------------------------------------------------

def record_rounds(graph: LamportGraph, difficulty: DifficultyOracle,
                  connectivity_k: int, recorder: EventRecorder,
                  step: int, node_name: str) -> None:
    """Wrapper around compute_rounds that records state changes."""
    old_state = {
        v.message_digest: (v.round, v.is_last)
        for v in graph.all_vertices()
    }

    compute_rounds(graph, difficulty, connectivity_k)

    for v in graph.all_vertices():
        d = v.message_digest
        old_r, old_last = old_state.get(d, (None, None))
        if v.round != old_r and v.round is not None:
            recorder.record(
                step, EventType.ROUND_ASSIGNED, node_name,
                digest_hex=d.hex()[:12],
                round_number=v.round,
                process_id_hex=v.id.hex()[:8],
            )
        if v.is_last and not old_last:
            recorder.record(
                step, EventType.VERTEX_BECOMES_LAST, node_name,
                digest_hex=d.hex()[:12],
                round_number=v.round,
                process_id_hex=v.id.hex()[:8],
            )


def record_voting(vertex: Vertex, graph: LamportGraph,
                  difficulty: DifficultyOracle, connectivity_k: int,
                  recorder: EventRecorder, step: int,
                  node_name: str) -> None:
    """Wrapper around compute_safe_voting_pattern that records SVP."""
    old_svp = list(vertex.svp) if vertex.svp else []

    compute_safe_voting_pattern(vertex, graph, difficulty, connectivity_k)

    if vertex.svp and vertex.svp != old_svp:
        recorder.record(
            step, EventType.SVP_COMPUTED, node_name,
            digest_hex=vertex.message_digest.hex()[:12],
            svp=list(vertex.svp),
            round_number=vertex.round,
        )


def record_leader_election(vertex: Vertex, graph: LamportGraph,
                           difficulty: DifficultyOracle,
                           connectivity_k: int,
                           leader_dict: dict,
                           recorder: EventRecorder, step: int,
                           node_name: str) -> None:
    """Wrapper around compute_virtual_leader_election that records results."""
    old_keys = set(leader_dict.keys())

    compute_virtual_leader_election(
        vertex, graph, difficulty, connectivity_k, leader_dict
    )

    new_keys = set(leader_dict.keys()) - old_keys
    for rn in new_keys:
        entries = leader_dict[rn]  # list[tuple[int, Message]]
        for deciding_round, leader_msg in entries:
            recorder.record(
                step, EventType.LEADER_ELECTED, node_name,
                round_number=rn,
                deciding_round=deciding_round,
                leader_digest_hex=leader_msg.compute_digest().hex()[:12],
            )
