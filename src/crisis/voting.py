"""
Virtual Voting, Safe Voting Patterns, and Leader Election (Section 5)

This module implements the heart of the Crisis protocol: the virtual voting
mechanism that achieves total order without ever sending explicit vote messages.

Key concepts:

5.5 Virtual Process Sortition & Knowledge Graphs
    - Knowledge graph (Def 5.8): quotient graph projecting vertices to virtual
      processes, representing what each process "knows" about others.
    - Quorum selector (Def 5.11): deterministically chooses a subset of virtual
      processes for each round -- the quorum that participates in agreement.

5.6 Safe Voting Pattern
    - Voting sets (Def 5.12): the set of vertices participating in round s
      agreement, reachable with connectivity k from vertex v.
    - Algorithm 6: computes the safe voting pattern -- a nested sequence of
      rounds where voting took place with appropriately bounded byzantine weight.

5.7 Local Leader Election
    - Algorithm 7: virtual leader elections -- an adaptation of Chen, Feldman
      & Micali's BA* to virtual voting on Lamport graphs.
    - Three stage types: initial proposal (δ=0), presorting/gradecast (δ∈{1,2}),
      and BBA* binary agreement (δ≥3) with "coin fixed to 0/1" and "genuine
      coin flip" sub-stages.

5.8 Longest Chain Rule
    - Algorithm 8: maintains the leader stream by keeping only the longest
      chain of round leaders (similar to Nakamoto's longest chain rule).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

from crisis.crypto import digest, least_significant_bit
from crisis.graph import LamportGraph
from crisis.message import Message, Vertex, Vote, EMPTY_MESSAGE_DIGEST
from crisis.rounds import last_vertices_in_round, max_round
from crisis.weight import DifficultyOracle


# ---------------------------------------------------------------------------
# Knowledge Graph (Definition 5.8)
# ---------------------------------------------------------------------------

@dataclass
class KnowledgeGraph:
    """The round s knowledge graph of vertex v (Definition 5.8).

    Given rounds s < r, a Lamport graph G, and v a last message in round r,
    the knowledge graph Π^s_v is the quotient graph G^s_v / ≃_id.

    Each node in the knowledge graph represents a virtual process (identified
    by its id).  An edge from process id to id' means that some vertex with
    v.id = id in round s has a vertex with v_hat.id = id' in its past.

    This represents what each virtual process "knows" about others.
    """
    # id -> set of ids that this process has edges to
    edges: dict[bytes, set[bytes]] = field(default_factory=dict)
    # id -> total weight of vertices in this equivalence class
    weights: dict[bytes, int] = field(default_factory=dict)


def build_knowledge_graph(vertex: Vertex, round_s: int,
                          graph: LamportGraph) -> KnowledgeGraph:
    """Build the round s knowledge graph for vertex v.

    Collects all round-s vertices in v's past, groups them by id,
    and builds the quotient graph.

    Each node represents a virtual process (an id).  An edge from id to id'
    means some round-s vertex with that id acknowledges a round-s vertex
    with id'.  Isolated nodes (no same-round edges) are still included --
    they represent processes whose messages are known but who didn't
    cross-reference other round-s processes.
    """
    kg = KnowledgeGraph()
    past = graph.past(vertex)

    # Find all round-s vertices in v's past
    round_s_vertices = [v for v in past if v.round == round_s]

    # Group by id and compute weights
    for v_s in round_s_vertices:
        vid = v_s.id
        if vid not in kg.edges:
            kg.edges[vid] = set()
        if vid not in kg.weights:
            kg.weights[vid] = 0

        kg.weights[vid] = graph.weight_system.weight_sum(
            kg.weights[vid], graph.vertex_weight(v_s)
        )

        # Add edges: if this vertex references another round-s vertex
        for cause in graph.direct_causes(v_s):
            if cause.round is not None and cause.round == round_s:
                kg.edges[vid].add(cause.id)

        # Also check if any round-s vertex references this one (reverse)
        for other in round_s_vertices:
            if other.id != vid:
                for cause in graph.direct_causes(other):
                    if cause.id == vid and cause.round == round_s:
                        kg.edges[other.id].add(vid)

    return kg


# ---------------------------------------------------------------------------
# Quorum Selector (Definition 5.11)
# ---------------------------------------------------------------------------

def select_quorum(knowledge_graph: KnowledgeGraph, n: int = 3) -> set[bytes]:
    """Select a quorum from a knowledge graph (Definition 5.11).

    Example 3 (Highest voting weight quorum):
    Choose the weakly connected component with the highest combined voting
    weight, then take the heaviest n virtual processes from it.

    The quorum selector serves as a filter to reduce byzantine noise that
    might appear in the voting process.  By restricting to a heavily
    connected component, faulty behavior based on graph partition is reduced.

    Special case: when all processes are isolated (no edges between them,
    typical for round 0 genesis vertices), we treat all of them as one
    component.  This is the bootstrapping case -- we know about all these
    processes through the vertex that triggered this query.
    """
    if not knowledge_graph.edges:
        return set()

    all_ids = set(knowledge_graph.edges.keys())

    # Check if all edges are empty (all processes are isolated).
    # This happens at round 0: genesis vertices don't reference each other.
    # In that case, treat all processes as a single component -- the
    # triggering vertex has all of them in its past, which is sufficient
    # evidence of connectivity.
    all_isolated = all(
        len(neighbors) == 0
        for neighbors in knowledge_graph.edges.values()
    )

    if all_isolated:
        # All ids form one virtual component
        best_component = all_ids
    else:
        # Find weakly connected components using BFS
        visited: set[bytes] = set()
        components: list[set[bytes]] = []

        for start_id in all_ids:
            if start_id in visited:
                continue
            component: set[bytes] = set()
            queue = [start_id]
            while queue:
                current = queue.pop(0)
                if current in visited:
                    continue
                visited.add(current)
                component.add(current)
                # Follow edges in both directions (weakly connected)
                for neighbor in knowledge_graph.edges.get(current, set()):
                    if neighbor not in visited and neighbor in all_ids:
                        queue.append(neighbor)
                # Reverse edges
                for other_id, neighbors in knowledge_graph.edges.items():
                    if current in neighbors and other_id not in visited:
                        queue.append(other_id)
            components.append(component)

        # Choose the component with highest total weight
        def component_weight(comp: set[bytes]) -> int:
            return sum(knowledge_graph.weights.get(pid, 0) for pid in comp)

        best_component = max(components, key=component_weight)

    # Take the n heaviest processes from this component
    sorted_by_weight = sorted(
        best_component,
        key=lambda pid: knowledge_graph.weights.get(pid, 0),
        reverse=True
    )

    return set(sorted_by_weight[:n])


# ---------------------------------------------------------------------------
# Voting Sets (Definition 5.12)
# ---------------------------------------------------------------------------

def voting_set(vertex: Vertex, round_s: int, connectivity_k: int,
               graph: LamportGraph) -> set[Vertex]:
    """Compute S_v(s,k): v's round s voting set (Definition 5.12).

    S_v(s,k) := { x | x.id ∈ Q(v,s) ∧ x ≤_{(r-s)*k} v
                  ∧ x.round = s ∧ x.is_last = true }

    The voting set consists of all last vertices in round s that:
    1. Belong to a quorum-selected virtual process
    2. Are k-reachable from v (with distance scaled by round gap)
    3. Are in v's past
    """
    if vertex.round is None:
        return set()

    r = vertex.round
    if round_s >= r:
        return set()

    # Build knowledge graph and select quorum
    kg = build_knowledge_graph(vertex, round_s, graph)
    quorum = select_quorum(kg)

    past_of_v = graph.past(vertex)

    result = set()
    for v_hat in past_of_v:
        if (v_hat.round == round_s
                and v_hat.is_last
                and v_hat.id in quorum):
            result.add(v_hat)

    return result


# ---------------------------------------------------------------------------
# Algorithm 6: Safe Voting Pattern (Section 5.6)
# ---------------------------------------------------------------------------

def compute_safe_voting_pattern(vertex: Vertex, graph: LamportGraph,
                                difficulty: DifficultyOracle,
                                connectivity_k: int = 2) -> None:
    """Algorithm 6: compute the safe voting pattern for a vertex.

    The safe voting pattern v.svp is a totally ordered set of round numbers
    where "safe" voting took place.  Safe means:
    - The voting set has enough overall weight
    - The svp of all members agree
    - Byzantine weight is bounded

    Pseudocode from the paper:
        1: procedure SVP(vertex:v, lamport_graph:G)
        2:   v.svp <- ∅
        3:   if v.is_last and [safe voting pattern conditions are met] then
        4:       s <- maximum of all such k
        5:       v.svp <- v.svp ∪ {s} for all t ≤ s
        6:   end if
        7: end procedure

    The procedure checks if the current vertex's round qualifies as a new
    entry in the safe voting pattern by verifying weight and agreement
    conditions from its voting set.
    """
    vertex.svp = []

    if not vertex.is_last or vertex.round is None or vertex.round == 0:
        return

    r = vertex.round

    # Check each previous round for safe voting pattern membership.
    # The SVP contains rounds strictly LESS than v.round (Algorithm 6).
    # It does NOT include v.round itself -- the current round's peers
    # are spacelike and cannot be part of v's voting set.
    for s in range(r):
        d_s = difficulty.difficulty(s)

        # Get voting set for round s
        vs = voting_set(vertex, s, connectivity_k, graph)
        if not vs:
            continue

        total_weight = graph.set_weight(vs)

        # Check if voting weight exceeds threshold (6 * d_s from Eq. 8)
        if total_weight <= 6 * d_s:
            continue

        # Check that all members of the voting set have compatible svp
        svps_agree = True
        for x in vs:
            for y in vs:
                if x.svp != y.svp:
                    # Allow prefix agreement
                    min_len = min(len(x.svp), len(y.svp))
                    if x.svp[:min_len] != y.svp[:min_len]:
                        svps_agree = False
                        break
            if not svps_agree:
                break

        if svps_agree:
            vertex.svp.append(s)


# ---------------------------------------------------------------------------
# Initial Vote Function (Definition 5.16, Example 4)
# ---------------------------------------------------------------------------

def initial_vote(vertices: set[Vertex], graph: LamportGraph) -> Optional[Message]:
    """INITIAL_VOTE: deterministically choose a leader proposal (Def 5.16).

    Example 4 (Highest weight): Choose the underlying message of the highest
    voting weight vertex.  Since we assume it is infeasible to have different
    vertices of equal weight, this is practically deterministic.

    The initial vote function is a system parameter.  Different choices lead
    to different long-term behavior.  Ideally all members of a safe voting
    pattern would compute the same initial vote.
    """
    if not vertices:
        return None

    best_vertex = max(vertices, key=lambda v: graph.vertex_weight(v))
    return best_vertex.m


# ---------------------------------------------------------------------------
# Algorithm 7: Virtual Leader Elections (Section 5.7)
# ---------------------------------------------------------------------------

def compute_virtual_leader_election(vertex: Vertex, graph: LamportGraph,
                                    difficulty: DifficultyOracle,
                                    connectivity_k: int,
                                    leader_stream: dict[int, list[tuple[int, Message]]]) -> None:
    """Algorithm 7: compute votes for all rounds in v's safe voting pattern.

    This is the core virtual BA* protocol.  For each element t in v.svp,
    the vertex computes a vote v.vote(t) = (l, b) based on the stage δ.

    Key details from the paper (pages 19-20):
    - s = max(v.svp): the highest round in the safe voting pattern
    - S = S_v(s, k): the voting set is computed ONCE for round s
    - δ = d_{v.svp}(s, t): the SVP distance from s to t
      - δ = 0 at t = s (the newest round): Initial leader proposal
      - δ = 1: Leader presorting (Feldman-Micali gradecast step 1)
      - δ = 2: BBA* initialization (gradecast step 2)
      - δ ≥ 3: Binary byzantine agreement rounds
        - δ mod 3 = 0: Coin fixed to 0
        - δ mod 3 = 1: Coin fixed to 1
        - δ mod 3 = 2: Genuine coin flip (using hash LSB)

    The votes of S members at round t are read from x.vote(t), which those
    members computed in their own execution of Algorithm 7.  Processing
    goes from δ=0 (no dependency) to higher δ (reads lower δ votes from
    S members), so votes cascade correctly.
    """
    if not vertex.svp:
        return

    s = max(vertex.svp)
    last_idx = len(vertex.svp) - 1

    # Line 6: S ← v's safe voting pattern S_v(s, k)
    # The voting set is computed ONCE for the max round s
    voting_set_s = voting_set(vertex, s, connectivity_k, graph)
    n = graph.set_weight(voting_set_s)
    d_s = difficulty.difficulty(s)

    if n == 0:
        return

    # Process in δ order: start at δ=0 (t=s), then δ=1, δ=2, ...
    # This means iterating the svp in REVERSE order (newest first)
    for t_idx_reversed in range(len(vertex.svp)):
        t_idx = last_idx - t_idx_reversed
        t = vertex.svp[t_idx]
        delta = t_idx_reversed  # δ = distance from s (the last element)

        _compute_vote_for_stage(vertex, t, delta, s, voting_set_s, n, d_s,
                                graph, leader_stream)


def _compute_vote_for_stage(vertex: Vertex, t: int, delta: int, s: int,
                            vs: set[Vertex], n: int, d_s: int,
                            graph: LamportGraph,
                            leader_stream: dict[int, list[tuple[int, Message]]]) -> None:
    """Compute vertex's vote for a specific stage of the virtual leader election.

    Implements the branching logic of Algorithm 7 (pages 19-20 of the paper).

    Args:
        vertex:        The vertex computing its vote.
        t:             The round number being voted on.
        delta:         The SVP distance (stage type).
        s:             The max round of the SVP.
        vs:            The voting set S (round-s last vertices).
        n:             Total weight of S.
        d_s:           Difficulty for round s.
        graph:         The Lamport graph.
        leader_stream: Dict to update with decided leaders.
    """
    NON_LEADER = None  # ∅ in the paper

    if delta == 0:
        # Stage 0: Initial leader proposal
        # v.vote(t) ← (INITIAL_VOTE(S), ⊥)
        l = initial_vote(vs, graph)
        vertex.vote[t] = Vote(message=l, binary=None)

    elif delta == 1:
        # Stage 1: Leader presorting (gradecast step 1)
        # Read S members' votes at round t (their δ=0 votes, i.e. vote(s))
        # "l ← message with highest round t voting weight in S"
        l = _leader_with_most_weight(vs, t, graph)

        if l is not None:
            l_weight = _vote_weight_for(vs, t, l, None, graph)
            if l_weight > n - d_s:
                vertex.vote[t] = Vote(message=l, binary=None)
            else:
                vertex.vote[t] = Vote(message=NON_LEADER, binary=None)
        else:
            vertex.vote[t] = Vote(message=NON_LEADER, binary=None)

    elif delta == 2:
        # Stage 2: BBA* initialization (gradecast step 2)
        l = _leader_with_most_weight(vs, t, graph)

        if l is not None and l is not NON_LEADER:
            l_weight_undecided = _vote_weight_for(vs, t, l, None, graph)
            if l_weight_undecided > n - d_s:
                vertex.vote[t] = Vote(message=l, binary=0)
            else:
                l_weight_any = _vote_weight_for_message(vs, t, l, graph)
                if l_weight_any > d_s:
                    vertex.vote[t] = Vote(message=l, binary=1)
                else:
                    vertex.vote[t] = Vote(message=NON_LEADER, binary=1)
        else:
            vertex.vote[t] = Vote(message=NON_LEADER, binary=1)

    else:
        # Stage δ ≥ 3: Binary agreement (BBA*)
        coin_stage = delta % 3
        l = _leader_with_most_weight(vs, t, graph)

        if coin_stage == 0:
            _bba_coin_fixed(vertex, t, vs, l, n, d_s, graph,
                            leader_stream, s, fixed_value=0)
        elif coin_stage == 1:
            _bba_coin_fixed(vertex, t, vs, l, n, d_s, graph,
                            leader_stream, s, fixed_value=1)
        else:
            _bba_genuine_coin(vertex, t, vs, l, n, d_s, graph)


def _bba_coin_fixed(vertex: Vertex, t: int, vs: set[Vertex],
                    l: Optional[Message], n: int, d_s: int,
                    graph: LamportGraph,
                    leader_stream: dict[int, list[tuple[int, Message]]],
                    s: int, fixed_value: int) -> None:
    """BBA* stage with coin fixed to 0 or 1."""
    other_value = 1 - fixed_value

    if l is not None:
        weight_for_fixed = _vote_weight_for_binary(vs, t, fixed_value, graph)
        if weight_for_fixed > n - d_s:
            vertex.vote[t] = Vote(message=l, binary=fixed_value)
            # If weight = n, we have agreement: update leader stream
            if weight_for_fixed == n:
                _update_leader_stream(leader_stream, l, s)
            return

        weight_for_other = _vote_weight_for_binary(vs, t, other_value, graph)
        if weight_for_other > n - d_s:
            vertex.vote[t] = Vote(message=l, binary=other_value)
            return

    vertex.vote[t] = Vote(message=l, binary=fixed_value)


def _bba_genuine_coin(vertex: Vertex, t: int, vs: set[Vertex],
                      l: Optional[Message], n: int, d_s: int,
                      graph: LamportGraph) -> None:
    """BBA* stage with genuine coin flip."""
    if l is not None:
        weight_0 = _vote_weight_for_binary(vs, t, 0, graph)
        if weight_0 > n - d_s:
            vertex.vote[t] = Vote(message=l, binary=0)
            return

        weight_1 = _vote_weight_for_binary(vs, t, 1, graph)
        if weight_1 > n - d_s:
            vertex.vote[t] = Vote(message=l, binary=1)
            return

    # Genuine coin flip: use LSB of hash of heaviest vertex's message
    if vs:
        heaviest = max(vs, key=lambda v: graph.vertex_weight(v))
        h = heaviest.m.compute_digest()
        b_coin = least_significant_bit(h)
        vertex.vote[t] = Vote(message=l, binary=b_coin)
    else:
        vertex.vote[t] = Vote(message=l, binary=0)


# ---------------------------------------------------------------------------
# Helper functions for vote weight computation
# ---------------------------------------------------------------------------

def _highest_weight_message(vs: set[Vertex], graph: LamportGraph) -> Optional[Message]:
    """Find the message with the highest voting weight in a set."""
    if not vs:
        return None
    best = max(vs, key=lambda v: graph.vertex_weight(v))
    return best.m


def _leader_with_most_weight(vs: set[Vertex], round_t: int,
                             graph: LamportGraph) -> Optional[Message]:
    """Find the leader message l that received the most voting weight at round t.

    Looks at x.vote(t) for all x ∈ vs, groups by the leader message,
    and returns the one with the highest total weight.
    Falls back to the highest-weight vertex's message if no votes exist.
    """
    # Tally weight per leader message
    leader_weights: dict[bytes, tuple[int, Message]] = {}
    has_any_vote = False

    for v in vs:
        vote = v.vote.get(round_t)
        if vote is None:
            continue
        has_any_vote = True
        if vote.message is not None:
            key = vote.message.compute_digest()
            w = graph.vertex_weight(v)
            if key in leader_weights:
                old_w, msg = leader_weights[key]
                leader_weights[key] = (graph.weight_system.weight_sum(old_w, w), msg)
            else:
                leader_weights[key] = (w, vote.message)

    if leader_weights:
        _, best_msg = max(leader_weights.values(), key=lambda x: x[0])
        return best_msg

    # No votes yet: fall back to highest weight vertex's message
    if not has_any_vote:
        return _highest_weight_message(vs, graph)

    return None


def _vote_weight_for(vs: set[Vertex], round_t: int,
                     target_msg: Optional[Message], target_binary: Optional[int],
                     graph: LamportGraph) -> int:
    """Compute total voting weight for a specific vote (l, b) in a voting set.

    w(S_v(s,k), t, (l,b)) := w({x ∈ S | x.vote(t) = (l, b)})
    """
    total = 0
    for v in vs:
        vote = v.vote.get(round_t)
        if vote is None:
            continue
        msg_match = (vote.message is None and target_msg is None) or \
                    (vote.message is not None and target_msg is not None and
                     vote.message.compute_digest() == target_msg.compute_digest())
        bin_match = vote.binary == target_binary
        if msg_match and bin_match:
            total = graph.weight_system.weight_sum(total, graph.vertex_weight(v))
    return total


def _vote_weight_for_message(vs: set[Vertex], round_t: int,
                             target_msg: Message,
                             graph: LamportGraph) -> int:
    """Compute total weight for any vote with a given leader message, any binary.

    Used in the gradecast stage to check if l received any significant weight,
    regardless of the binary part.
    """
    total = 0
    target_digest = target_msg.compute_digest()
    for v in vs:
        vote = v.vote.get(round_t)
        if vote is None or vote.message is None:
            continue
        if vote.message.compute_digest() == target_digest:
            total = graph.weight_system.weight_sum(total, graph.vertex_weight(v))
    return total


def _vote_weight_for_binary(vs: set[Vertex], round_t: int,
                            target_binary: int,
                            graph: LamportGraph) -> int:
    """Compute total voting weight for a specific binary value in a voting set."""
    total = 0
    for v in vs:
        vote = v.vote.get(round_t)
        if vote is not None and vote.binary == target_binary:
            total = graph.weight_system.weight_sum(total, graph.vertex_weight(v))
    return total


# ---------------------------------------------------------------------------
# Algorithm 8: Longest Chain Rule (Section 5.8)
# ---------------------------------------------------------------------------

def _update_leader_stream(leader_stream: dict[int, list[tuple[int, Message]]],
                          message: Message, round_number: int) -> None:
    """Algorithm 8: update the leader stream with a new leader candidate.

    The longest chain rule keeps only the chain with the highest deciding
    round for each round leader.  When a new round leader is decided at a
    higher deciding round, previous entries with lower deciding rounds are
    replaced.

    Pseudocode:
        1: procedure LONG_CHAIN(set{(uint,MESSAGE)}:S, MESSAGE:m, uint:s)
        2:   if there is no (l, t) ∈ S with t > s then
        3:       S <- {(l, t) ∈ S | t < s} ∪ (s, m)
        4:   end if
        5:   return S
        6: end procedure
    """
    if round_number not in leader_stream:
        leader_stream[round_number] = []

    entries = leader_stream[round_number]

    # Check if there's already an entry with a higher deciding round
    has_higher = any(t > round_number for (t, _) in entries)
    if has_higher:
        return

    # Remove entries with lower deciding rounds, add new one
    leader_stream[round_number] = [
        (t, m) for (t, m) in entries if t < round_number
    ] + [(round_number, message)]
