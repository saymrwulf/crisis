"""
Total Order (Section 5.8)

As time goes by and the Lamport graph grows, more and more round leaders
are computed and incorporated into the global leader stream LEADER_G(·).

Algorithm 9 (Order loop): watches for leader stream updates and recomputes
total order.  Total order is achieved by topological sorting on the past
of appropriate vertices.

Algorithm 10 (Total order using Kahn's algorithm): generates total order
in linear runtime by processing vertices without outgoing causal edges first,
using voting weight to break ties among spacelike vertices.

The total order converges probabilistically: any two non-byzantine processes
will eventually compute the same total order (Proposition 6.21).

Definition 5.17 (Leader Stream):
    LEADER_G : N -> Option<(uint, MESSAGE)>
    is called the *global leader stream* of the Lamport graph.

Corollary 6.19 (Leader stream convergence):
    If the probability for new rounds and safe voting pattern is not zero,
    the leader streams of any two honest processes will converge.
"""

from __future__ import annotations

from typing import Optional

from crisis.graph import LamportGraph
from crisis.message import Message, Vertex


# ---------------------------------------------------------------------------
# Leader Stream (Definition 5.17)
# ---------------------------------------------------------------------------

class LeaderStream:
    """The global leader stream of a Lamport graph.

    Maps round numbers to (deciding_round, leader_message) pairs.
    Uses the Nakamoto longest chain rule: when a new leader is decided
    in a later round, it may replace leaders decided in earlier rounds.

    The leader stream converges to contain a single element per round
    (Theorem 6.18), and honest processes' leader streams converge to
    the same values (Corollary 6.19).
    """

    def __init__(self):
        # round_number -> (deciding_round, leader_message)
        self.leaders: dict[int, tuple[int, Message]] = {}

    def update(self, round_number: int, deciding_round: int,
               leader_message: Message) -> bool:
        """Update the leader for a round via the Nakamoto longest chain rule.

        Algorithm 8 (LONG_CHAIN): keep only the leader decided in the
        highest round.  Delete leaders from previous rounds that have
        lower deciding rounds.

        Returns True if the leader stream was modified.
        """
        current = self.leaders.get(round_number)

        if current is not None:
            existing_deciding_round, _ = current
            if existing_deciding_round >= deciding_round:
                return False  # Already have a leader from a higher round

        self.leaders[round_number] = (deciding_round, leader_message)

        # Prune: remove leaders with lower deciding rounds
        # (longest chain rule -- keep only the longest)
        max_deciding = max(dr for dr, _ in self.leaders.values())
        to_remove = []
        for r, (dr, _) in self.leaders.items():
            if dr < max_deciding and r < round_number:
                to_remove.append(r)
        for r in to_remove:
            del self.leaders[r]

        return True

    def get_leader(self, round_number: int) -> Optional[Message]:
        """Get the current leader message for a round, if any."""
        entry = self.leaders.get(round_number)
        return entry[1] if entry else None

    def max_round(self) -> int:
        """Highest round with a decided leader."""
        return max(self.leaders.keys()) if self.leaders else -1

    def all_leaders(self) -> list[tuple[int, Message]]:
        """Return all leaders ordered by round number."""
        return [(r, msg) for r, (_, msg) in sorted(self.leaders.items())]

    def __repr__(self) -> str:
        rounds = sorted(self.leaders.keys())
        return f"LeaderStream(rounds={rounds})"


# ---------------------------------------------------------------------------
# Algorithm 9: Order Loop
# ---------------------------------------------------------------------------

def compute_order(graph: LamportGraph, leader_stream: LeaderStream) -> list[Vertex]:
    """Algorithm 9: compute total order from the leader stream.

    Pseudocode:
        1: loop order update loop
        2:   wait for LEADER_G(·) to change
        3:   s <- min round of all changed LEADER_G(t)
        4:   r <- max round of all LEADER_G(t) ≠ ∅
        5:   v_{l_r} <- leader in highest round, smallest s in G
        6:   n <- max(v.total_position | v ∈ Ord_G(v_{l_{r-1}}))
        7:   for x ≤ t ≤ r do
        8:       randomly choose (p, l_t) ∈ LEADER_G(t)
        9:       if l_t ≠ ∅ then
        10:          ORDER(Ord_G(v_t), n)         ▷ v_t.m = l_t
        11:      end if
        12:  end for
        13: end loop

    For this PoC, we compute the order in a single pass over the current
    leader stream state.
    """
    if not leader_stream.leaders:
        return []

    ordered: list[Vertex] = []
    position = 0

    # Process leaders in round order
    for round_number, leader_message in leader_stream.all_leaders():
        # Find the vertex corresponding to this leader message
        leader_digest = leader_message.compute_digest()
        leader_vertex = graph.get_vertex(leader_digest)

        if leader_vertex is None:
            continue

        # Order the past of this leader vertex (excluding already-ordered)
        past_vertices = graph.past(leader_vertex)
        already_ordered = {v.message_digest for v in ordered}
        new_vertices = [
            v for v in past_vertices
            if v.message_digest not in already_ordered
        ]

        # Sort new vertices using Kahn's algorithm (Algorithm 10)
        sorted_new = _kahns_total_order(new_vertices, graph)

        for v in sorted_new:
            v.total_position = position
            ordered.append(v)
            position += 1

    return ordered


# ---------------------------------------------------------------------------
# Algorithm 10: Total Order using Kahn's Algorithm
# ---------------------------------------------------------------------------

def _kahns_total_order(vertices: list[Vertex], graph: LamportGraph) -> list[Vertex]:
    """Algorithm 10: generate total order using Kahn's algorithm.

    Kahn's algorithm in its "arrow reversed" incarnation: we want to order
    the past before the future in our Lamport graph.

    Pseudocode from the paper:
        1:  procedure ORDER(dag:Ord(v), uint:last)
        2:    n <- last + 1
        3:    S <- set of all elements of Ord(v) with no outgoing edges
        4:    while S ≠ ∅ do
        5:      remove x with highest weight w(x) from S
        6:      x.total_position <- n
        7:      n <- n + 1
        8:      for each vertex y ∈ Ord(v) with edge e : y -> x do
        9:        remove edge e from Ord(v)
        10:       if y has no other outgoing edge then
        11:         S <- S ∪ {y}
        12:       end if
        13:     end for
        14:   end while
        15: end procedure

    Tie-breaking by voting weight ensures that all honest processes produce
    the same total order from equivalent Lamport graphs.
    """
    if not vertices:
        return []

    # Build a local subgraph for just these vertices
    vertex_set = {v.message_digest for v in vertices}

    # out_degree: for each vertex, count edges to other vertices in this set
    out_edges: dict[bytes, set[bytes]] = {}
    in_edges: dict[bytes, set[bytes]] = {}

    for v in vertices:
        d = v.message_digest
        out_edges[d] = set()
        in_edges[d] = set()

    for v in vertices:
        d = v.message_digest
        for cause_d in graph.edges.get(d, set()):
            if cause_d in vertex_set:
                out_edges[d].add(cause_d)
                in_edges[cause_d].add(d)

    # Start with vertices that have no outgoing edges (sinks = earliest causes)
    result: list[Vertex] = []
    available = [
        v for v in vertices
        if len(out_edges[v.message_digest]) == 0
    ]

    while available:
        # Remove the vertex with highest weight (deterministic tie-breaking)
        available.sort(key=lambda v: graph.vertex_weight(v), reverse=True)
        chosen = available.pop(0)
        result.append(chosen)

        # Remove edges pointing to chosen
        chosen_d = chosen.message_digest
        for referrer_d in list(in_edges.get(chosen_d, set())):
            out_edges[referrer_d].discard(chosen_d)
            if len(out_edges[referrer_d]) == 0:
                referrer_vertex = graph.get_vertex(referrer_d)
                if referrer_vertex is not None and referrer_vertex not in result:
                    available.append(referrer_vertex)

    return result


# ---------------------------------------------------------------------------
# Convenience: full pipeline
# ---------------------------------------------------------------------------

def total_order_positions(graph: LamportGraph,
                          leader_stream: LeaderStream) -> dict[bytes, int]:
    """Return a mapping of message digest -> total order position.

    This is the final output of the Crisis protocol: a total order on
    messages that respects causality and is probabilistically invariant
    among all honest participants.
    """
    ordered = compute_order(graph, leader_stream)
    return {v.message_digest: v.total_position for v in ordered
            if v.total_position is not None}
