"""
Virtual Synchronous Rounds (Section 5.3)

Lamport graphs represent a timelike order between vertices that we interpret
as virtual communication channels.  Going one step further, we can think from
inside the Lamport graph to define a virtual clock tick as a transition from
one vertex to another.

This simple idea allows for internal synchronism that enables us to execute
strongly synchronous agreement protocols like Feldman & Micali's BA*
virtually, but without any compromise in external asynchronism.

Algorithm 5 (Virtual synchronous rounds):
    The algorithm computes *round numbers* and the *is_last* property
    of any vertex.

    - The round number is computed by taking the largest round of all
      direct causes.
    - If the vertex is a direct effect of a current round vertex with
      the is_last property, a new round begins.
    - If the vertex has enough last vertices of the previous round in its
      past and it is k-reachable from all of them, the vertex becomes a
      last vertex in its own round.

Definition 5.1 (k-reachability):
    v_hat is said to be k-reachable from v, if the overall weight of all
    vertices in all paths from v to v_hat is greater than k.

Proposition 5.3 (Round invariance):
    The round number and is_last property do not depend on the actual
    Lamport graph, but are the same for equivalent vertices.
"""

from __future__ import annotations

from crisis.graph import LamportGraph
from crisis.message import Vertex
from crisis.weight import DifficultyOracle


def compute_rounds(graph: LamportGraph, difficulty: DifficultyOracle,
                   connectivity_k: int = 2) -> None:
    """Execute Algorithm 5 on all vertices in the graph.

    This computes v.round and v.is_last for every vertex v in the graph.
    The algorithm processes vertices in causal order (causes before effects)
    to ensure dependencies are resolved before they are needed.

    Args:
        graph:          The Lamport graph to process.
        difficulty:     The difficulty oracle d : N -> W.
        connectivity_k: The connectivity parameter k for k-reachability.
    """
    # Process vertices in topological order (causes first)
    ordered = _topological_sort(graph)

    for vertex in ordered:
        _compute_round_for_vertex(vertex, graph, difficulty, connectivity_k)


def _compute_round_for_vertex(vertex: Vertex, graph: LamportGraph,
                              difficulty: DifficultyOracle,
                              connectivity_k: int) -> None:
    """Algorithm 5: compute round number and is_last for a single vertex.

    Pseudocode from the paper:
        1: procedure ROUND(vertex:v, lamport_graph:G)
        2:   N_v <- {v_hat ∈ G | v -> v_hat}       # direct causes
        3:   r <- max({v_hat.round | v_hat ∈ N_v} ∪ {0})
        4:   if there is a v_hat ∈ N_v with v_hat.is_last and v_hat.round = r then
        5:       v.round <- r + 1
        6:   else
        7:       v.round <- r
        8:   end if
        9:   S_r <- {v_hat ∈ G | v_hat.round = v.round - 1, v_hat.is_last, v_hat ≤_k v}
        10:  if w(S_r) > 3 * d_r then
        11:      v.is_last <- true
        12:  else
        13:      v.is_last <- (r = 0)
        14:  end if
        15: end procedure
    """
    # Step 2: direct causes
    direct_causes = graph.direct_causes(vertex)

    # Step 3: max round of direct causes (default 0 if no causes)
    if direct_causes:
        max_round = max(
            (dc.round if dc.round is not None else 0) for dc in direct_causes
        )
    else:
        max_round = 0

    # Steps 4-8: determine this vertex's round
    # If any direct cause is a "last vertex" of the current max round,
    # this vertex starts a new round.
    has_last_cause_in_max_round = any(
        dc.is_last and dc.round == max_round
        for dc in direct_causes
        if dc.round is not None and dc.is_last is not None
    )

    if has_last_cause_in_max_round:
        vertex.round = max_round + 1
    else:
        vertex.round = max_round

    # Steps 9-14: determine is_last
    r = vertex.round
    if r == 0:
        # All round-0 vertices are "last" (bootstrapping)
        vertex.is_last = True
        return

    # Find last vertices of the previous round that are k-reachable from v
    d_r = difficulty.difficulty(r)

    previous_round_lasts = [
        v_hat for v_hat in graph.all_vertices()
        if v_hat.round == r - 1
        and v_hat.is_last
        and _is_k_reachable(v_hat, vertex, graph, connectivity_k)
    ]

    # Weight of k-reachable last vertices from previous round
    weight_of_previous_lasts = graph.set_weight(previous_round_lasts)

    if weight_of_previous_lasts > 3 * d_r:
        vertex.is_last = True
    else:
        vertex.is_last = False


def _is_k_reachable(v_from: Vertex, v_to: Vertex,
                    graph: LamportGraph, k: int) -> bool:
    """Check k-reachability (Definition 5.1).

    v_hat is k-reachable from v if the overall weight of all vertices in
    all paths from v to v_hat is greater than k.

    For simplicity in this PoC, we approximate this by checking if v_from
    is in the past of v_to and the total weight along the path exceeds k.

    The paper notes (page 11): "counting disjoint paths is computationally
    expensive and not really necessary in our setting... all we need is some
    insurance that information flows through enough real world processes."
    We use total path weight as a simpler proxy.

    Special case: k <= 0 degenerates to simple reachability (is v_from in
    the past of v_to?).  This is the appropriate setting for small demos
    where weight accumulation is limited.
    """
    past_of_to = graph.past(v_to)

    if v_from not in past_of_to:
        return False

    # k <= 0: simple reachability suffices
    if k <= 0:
        return True

    # k > 0: check that enough weight exists on the path
    future_of_from = graph.future(v_from)
    path_vertices = past_of_to & future_of_from
    total_weight = graph.set_weight(path_vertices)

    return total_weight > k


def _topological_sort(graph: LamportGraph) -> list[Vertex]:
    """Sort vertices in causal order: causes come before their effects.

    Uses Kahn's algorithm.  Vertices with no causes (sources) come first.
    This ensures that when we process a vertex, all its causes already
    have their round numbers computed.
    """
    # Compute in-degree (number of causes each vertex has within the graph)
    in_degree: dict[bytes, int] = {}
    for d, v in graph.vertices.items():
        in_degree[d] = 0

    for d, v in graph.vertices.items():
        for ref_d in graph.edges.get(d, set()):
            if ref_d in graph.vertices:
                # ref_d is a cause of d, so d has an additional in-edge
                # But we want causal order: causes first
                # edges go from effect -> cause, so we need reverse
                pass

    # Actually: edges[d] contains the causes of d (d -> cause).
    # For topological sort where causes come first, we need:
    # in_degree[d] = number of digests in edges[d] that are in the graph
    for d in graph.vertices:
        count = 0
        for cause_d in graph.edges.get(d, set()):
            if cause_d in graph.vertices:
                count += 1
        in_degree[d] = count

    # Start with vertices that have no causes (in_degree = 0)
    queue = [d for d, deg in in_degree.items() if deg == 0]
    result = []

    while queue:
        current = queue.pop(0)
        result.append(graph.vertices[current])

        # For each vertex that current is a cause of (reverse edges)
        for effect_d in graph.reverse_edges.get(current, set()):
            if effect_d in in_degree:
                in_degree[effect_d] -= 1
                if in_degree[effect_d] == 0:
                    queue.append(effect_d)

    return result


# ---------------------------------------------------------------------------
# Queries on computed rounds
# ---------------------------------------------------------------------------

def last_vertices_in_round(graph: LamportGraph, round_number: int) -> list[Vertex]:
    """Return all last vertices in a given round."""
    return [
        v for v in graph.all_vertices()
        if v.round == round_number and v.is_last
    ]


def max_round(graph: LamportGraph) -> int:
    """Return the highest round number in the graph."""
    rounds = [v.round for v in graph.all_vertices() if v.round is not None]
    return max(rounds) if rounds else 0


def vertices_in_round(graph: LamportGraph, round_number: int) -> list[Vertex]:
    """Return all vertices in a given round."""
    return [v for v in graph.all_vertices() if v.round == round_number]
