"""
Lamport Graphs (Section 3.2)

Lamport graphs represent the causal partial order between messages as a
directed acyclic graph.  They are the central data structure of the Crisis
protocol -- all consensus state is derived from the graph structure.

Definition 3.5 (Lamport Graph):
    Let V ⊂ VERTEX be a finite set of vertices, such that all vertices
    v_hat with v_hat ≤ v for all v ∈ V are in V, but no two vertices in V
    are equivalent.  Then the graph G = (V, A) with (v, v_hat) ∈ A if and
    only if v -> v_hat is called a *Lamport graph*.

Key properties:
    - Directed and acyclic (Proposition 3.6)
    - The past of a vertex is invariant across Lamport graphs (Theorem 3.7)
    - No two equivalent vertices exist in the same graph

This module implements:
    - Algorithm 1: Message generation
    - Algorithm 2: Message integrity checking and graph extension
    - Causality queries (past, future, timelike, spacelike)
"""

from __future__ import annotations

import os
from typing import Optional

from crisis.crypto import digest
from crisis.message import Message, Vertex, Vote, ID_LENGTH, NONCE_LENGTH
from crisis.weight import ProofOfWorkWeight, WeightSystem


class LamportGraph:
    """A Lamport graph: a DAG of vertices connected by causal acknowledgement.

    The graph is stored as:
        - vertices:     dict mapping message digest -> Vertex
        - edges:        dict mapping digest -> set of digests it references
                        (i.e. v -> v_hat means v acknowledges v_hat)

    Invariants maintained:
        - No two vertices have the same underlying message (no equivalence)
        - All referenced digests either exist in the graph or are the empty digest
        - The graph is acyclic (guaranteed by hash function properties)
    """

    def __init__(self, weight_system: WeightSystem | None = None):
        self.weight_system: WeightSystem = weight_system or ProofOfWorkWeight(min_leading_zeros=0)

        # digest -> Vertex
        self.vertices: dict[bytes, Vertex] = {}

        # digest -> set of digests this vertex references (outgoing causal edges)
        # An edge v -> v_hat means "v acknowledges v_hat" i.e. H(v_hat.m) ∈ v.m.digests
        self.edges: dict[bytes, set[bytes]] = {}

        # Reverse edges for efficient "future" queries
        # digest -> set of digests that reference this vertex
        self.reverse_edges: dict[bytes, set[bytes]] = {}

    # ------------------------------------------------------------------
    # Graph queries
    # ------------------------------------------------------------------

    def __len__(self) -> int:
        return len(self.vertices)

    def __contains__(self, digest_or_vertex) -> bool:
        if isinstance(digest_or_vertex, Vertex):
            return digest_or_vertex.message_digest in self.vertices
        return digest_or_vertex in self.vertices

    def get_vertex(self, msg_digest: bytes) -> Optional[Vertex]:
        return self.vertices.get(msg_digest)

    def all_vertices(self) -> list[Vertex]:
        return list(self.vertices.values())

    def vertex_count(self) -> int:
        return len(self.vertices)

    # ------------------------------------------------------------------
    # Causality (Definition 3.2)
    # ------------------------------------------------------------------
    # m -> m_hat (m happens before m_hat) iff:
    #   - m = m_hat, OR
    #   - there is a chain m -> m1 -> ... -> mk -> m_hat
    # In our DAG: v has an edge to v_hat means v acknowledges v_hat.
    # So v is in the *future* of v_hat, and v_hat is in the *past* of v.

    def direct_causes(self, v: Vertex) -> list[Vertex]:
        """Return the direct causes of v (vertices that v acknowledges).

        These are the vertices whose digests appear in v.m.digests.
        In graph terms: the outgoing neighbors of v.
        """
        result = []
        for d in self.edges.get(v.message_digest, set()):
            vertex = self.vertices.get(d)
            if vertex is not None:
                result.append(vertex)
        return result

    def direct_effects(self, v: Vertex) -> list[Vertex]:
        """Return the direct effects of v (vertices that acknowledge v).

        In graph terms: the incoming neighbors of v (who references v).
        """
        result = []
        for d in self.reverse_edges.get(v.message_digest, set()):
            vertex = self.vertices.get(d)
            if vertex is not None:
                result.append(vertex)
        return result

    def past(self, v: Vertex) -> set[Vertex]:
        """G_v: the subgraph of G containing all causes of v.

        Definition 3.5: "the subgraph G_v of G that contains all causes
        of v is called the *past* of v".

        Returns the set of all vertices that are causally before v
        (including v itself -- reflexivity).
        """
        visited: set[bytes] = set()
        stack = [v.message_digest]

        while stack:
            current = stack.pop()
            if current in visited:
                continue
            visited.add(current)
            for neighbor in self.edges.get(current, set()):
                if neighbor in self.vertices and neighbor not in visited:
                    stack.append(neighbor)

        return {self.vertices[d] for d in visited if d in self.vertices}

    def future(self, v: Vertex) -> set[Vertex]:
        """All vertices that are causally after v (including v itself)."""
        visited: set[bytes] = set()
        stack = [v.message_digest]

        while stack:
            current = stack.pop()
            if current in visited:
                continue
            visited.add(current)
            for neighbor in self.reverse_edges.get(current, set()):
                if neighbor in self.vertices and neighbor not in visited:
                    stack.append(neighbor)

        return {self.vertices[d] for d in visited if d in self.vertices}

    def is_cause_of(self, v: Vertex, v_hat: Vertex) -> bool:
        """Check if v ≤ v_hat (v is in the past of v_hat).

        Definition 3.4: v is said to happen before v_hat (v ≤ v_hat)
        if there is a causality chain from v to v_hat.
        """
        if v == v_hat:
            return True
        return v in self.past(v_hat)

    def are_timelike(self, v: Vertex, v_hat: Vertex) -> bool:
        """Check if v and v_hat are timelike (comparable / causally related)."""
        return self.is_cause_of(v, v_hat) or self.is_cause_of(v_hat, v)

    def are_spacelike(self, v: Vertex, v_hat: Vertex) -> bool:
        """Check if v and v_hat are spacelike (incomparable / no causal relation).

        Spacelike vertices are the ones that need the total order protocol
        to become comparable.  The protocol extends the timelike partial
        order to cover spacelike vertices as well.
        """
        return not self.are_timelike(v, v_hat)

    # ------------------------------------------------------------------
    # Mutations (Definition 4.2)
    # ------------------------------------------------------------------

    def find_mutations(self, vertex_id: bytes) -> list[list[Vertex]]:
        """Find mutations: vertices with the same id that are spacelike.

        Definition 4.2: Two vertices v and v_hat in G are called a *mutation*
        of a virtual process if they have the same id and are spacelike,
        i.e. neither v ≤ v_hat nor v_hat ≤ v holds.

        Mutations are the virtual voting equivalent of equivocation -- a
        byzantine actor sending different votes to different processes.

        Returns a list of groups of mutually spacelike same-id vertices.
        """
        # Group vertices by id
        by_id: dict[bytes, list[Vertex]] = {}
        for v in self.vertices.values():
            by_id.setdefault(v.id, []).append(v)

        mutations = []
        for vid, group in by_id.items():
            if vid != vertex_id:
                continue
            # Find spacelike pairs within the group
            spacelike_group = []
            for i, v1 in enumerate(group):
                for v2 in group[i + 1:]:
                    if self.are_spacelike(v1, v2):
                        if v1 not in spacelike_group:
                            spacelike_group.append(v1)
                        if v2 not in spacelike_group:
                            spacelike_group.append(v2)
            if spacelike_group:
                mutations.append(spacelike_group)
        return mutations

    # ------------------------------------------------------------------
    # Byte-level correctness (part of Algorithm 2)
    # ------------------------------------------------------------------

    def _bytelevel_correctness(self, message: Message) -> bool:
        """BYTELEVEL_CORRECTNESS: basic structural validation of a message.

        Checks that the message has valid field lengths and is well-formed.
        """
        if len(message.nonce) != NONCE_LENGTH:
            return False
        if len(message.id) != ID_LENGTH:
            return False
        for d in message.digests:
            if len(d) != 32:  # DIGEST_LENGTH
                return False
        return True

    def _payload_correctness(self, message: Message) -> bool:
        """PAYLOAD_CORRECTNESS: validate the payload against system rules.

        In this PoC, any payload is accepted.  A real system would enforce
        application-specific validation here.
        """
        return True

    # ------------------------------------------------------------------
    # Algorithm 2: Message integrity (Section 4.2)
    # ------------------------------------------------------------------

    def message_integrity(self, message: Message) -> bool:
        """Check whether a message can be validly added to this Lamport graph.

        Algorithm 2 from the paper:

        1. Check BYTELEVEL_CORRECTNESS(m)
        2. Check w(m) > c_min  (weight threshold)
        3. Check PAYLOAD_CORRECTNESS(m.payload)
        4. Check no equivalent vertex exists (no vertex with same digest)
        5. For each digest in m.digests:
           - It must reference a vertex in G
           - All referenced vertices must have different id's
        6. If there is a vertex v in G with v.id = m.id:
           - One of m.digests must reference v (or a vertex in v's past)
           Ensures the virtual process forms a chain, not a tree.

        Returns True if the message passes integrity checks.
        """
        # Step 1: byte-level structure
        if not self._bytelevel_correctness(message):
            return False

        # Step 2: weight threshold
        if not self.weight_system.is_valid_weight(message):
            return False

        # Step 3: payload rules
        if not self._payload_correctness(message):
            return False

        msg_digest = message.compute_digest()

        # Step 4: no duplicate (no equivalent vertex)
        if msg_digest in self.vertices:
            return False

        # Step 5: all referenced digests must exist in G
        # and all referenced vertices must have different ids
        referenced_ids: set[bytes] = set()
        for ref_digest in message.digests:
            if ref_digest not in self.vertices:
                return False
            ref_vertex = self.vertices[ref_digest]
            if ref_vertex.id in referenced_ids:
                return False  # Two references to same id
            referenced_ids.add(ref_vertex.id)

        # Step 6: if same id exists, must reference it (chain constraint)
        # Find the "last vertex" with this id (not referenced by any other
        # vertex with the same id)
        same_id_vertices = [v for v in self.vertices.values() if v.id == message.id]
        if same_id_vertices:
            # Check that at least one digest references a same-id vertex
            referenced_digests = set(message.digests)
            found_chain_link = False
            for v in same_id_vertices:
                if v.message_digest in referenced_digests:
                    found_chain_link = True
                    break
            if not found_chain_link:
                return False

        return True

    # ------------------------------------------------------------------
    # Lamport graph extension (Section 4.2)
    # ------------------------------------------------------------------

    def extend(self, message: Message) -> Optional[Vertex]:
        """Attempt to extend the Lamport graph with a new message.

        If the message passes integrity checks (Algorithm 2), create a new
        vertex and add it to the graph with appropriate edges.

        Proposition 4.1 guarantees that the extension of a Lamport graph
        by a valid message is itself a Lamport graph.

        Returns the new Vertex if successful, None if integrity check fails.
        """
        if not self.message_integrity(message):
            return None

        vertex = Vertex(m=message)
        msg_digest = message.compute_digest()

        # Add vertex
        self.vertices[msg_digest] = vertex

        # Add edges: this vertex -> each referenced vertex
        self.edges[msg_digest] = set()
        for ref_digest in message.digests:
            self.edges[msg_digest].add(ref_digest)
            # Reverse edge
            if ref_digest not in self.reverse_edges:
                self.reverse_edges[ref_digest] = set()
            self.reverse_edges[ref_digest].add(msg_digest)

        # Initialize reverse_edges entry for this vertex
        if msg_digest not in self.reverse_edges:
            self.reverse_edges[msg_digest] = set()

        return vertex

    # ------------------------------------------------------------------
    # Algorithm 1: Message generation (Section 4.1)
    # ------------------------------------------------------------------

    def generate_message(self, process_id: bytes, payload: bytes,
                         weight_system: WeightSystem | None = None) -> Message:
        """Generate a valid message for a given virtual process id.

        Algorithm 1 from the paper:
        1. Find the last vertex v with v.id = id in G
        2. Choose S ⊂ {v.m | v ∈ G ∧ v ∉ G_v} such that all have different ids
        3. Return message with digests = {H(v.m)} ∪ {H(m) | m ∈ S ∪ {v.m}}

        The nonce is chosen so that w(m) > c_min (via mining if PoW).
        """
        ws = weight_system or self.weight_system

        # Find the last vertex with this process id
        last_vertex = self._find_last_vertex(process_id)

        # Collect digests: last same-id vertex + a sample of other vertices
        digests_list: list[bytes] = []

        if last_vertex is not None:
            # Must reference the last vertex with same id
            digests_list.append(last_vertex.message_digest)

            # Add cross-references to vertices NOT in last_vertex's past
            past_digests = {v.message_digest for v in self.past(last_vertex)}
            candidates = [
                v for d, v in self.vertices.items()
                if d not in past_digests
                and v.id != process_id
                and d != last_vertex.message_digest
            ]

            # Include candidates with different ids
            seen_ids: set[bytes] = {process_id}
            for candidate in candidates:
                if candidate.id not in seen_ids:
                    digests_list.append(candidate.message_digest)
                    seen_ids.add(candidate.id)
        else:
            # First message for this id: reference a sample of existing vertices
            seen_ids = {process_id}
            for v in self.vertices.values():
                if v.id not in seen_ids:
                    digests_list.append(v.message_digest)
                    seen_ids.add(v.id)

        digests_tuple = tuple(digests_list)

        # Mine a valid nonce (or just find one that meets threshold)
        if isinstance(ws, ProofOfWorkWeight):
            message = ws.mine_nonce(process_id, digests_tuple, payload)
        else:
            # For non-PoW systems, use a random nonce
            nonce = os.urandom(NONCE_LENGTH)
            message = Message(nonce=nonce, id=process_id, digests=digests_tuple, payload=payload)

        return message

    def _find_last_vertex(self, process_id: bytes) -> Optional[Vertex]:
        """Find the last vertex with a given process id.

        A vertex is "last" for an id if no other vertex with the same id
        references it (i.e. it has no same-id successor).
        """
        same_id = [v for v in self.vertices.values() if v.id == process_id]
        if not same_id:
            return None

        # Find the one that is not referenced by any other same-id vertex
        referenced_by_same_id: set[bytes] = set()
        for v in same_id:
            for d in v.digests:
                ref = self.vertices.get(d)
                if ref is not None and ref.id == process_id:
                    referenced_by_same_id.add(d)

        for v in same_id:
            if v.message_digest not in referenced_by_same_id:
                return v

        # Fallback: return the one added most recently (by convention)
        return same_id[-1]

    # ------------------------------------------------------------------
    # Vertices by id (for virtual process queries)
    # ------------------------------------------------------------------

    def vertices_by_id(self, process_id: bytes) -> list[Vertex]:
        """Return all vertices belonging to a given virtual process id."""
        return [v for v in self.vertices.values() if v.id == process_id]

    def all_process_ids(self) -> set[bytes]:
        """Return all unique virtual process ids in this graph."""
        return {v.id for v in self.vertices.values()}

    def last_vertices_by_id(self) -> dict[bytes, Vertex]:
        """Return the last vertex for each virtual process id."""
        result = {}
        for pid in self.all_process_ids():
            last = self._find_last_vertex(pid)
            if last is not None:
                result[pid] = last
        return result

    # ------------------------------------------------------------------
    # Weight queries
    # ------------------------------------------------------------------

    def vertex_weight(self, v: Vertex) -> int:
        """w(v) = w(v.m): the weight of a vertex is the weight of its message."""
        return self.weight_system.weight(v.m)

    def set_weight(self, vertices: set[Vertex] | list[Vertex]) -> int:
        """w(M) := ⊕_{m ∈ M} w(m): the combined weight of a set of vertices."""
        total = 0
        for v in vertices:
            total = self.weight_system.weight_sum(total, self.vertex_weight(v))
        return total

    # ------------------------------------------------------------------
    # Display
    # ------------------------------------------------------------------

    def __repr__(self) -> str:
        return f"LamportGraph(vertices={len(self.vertices)}, ids={len(self.all_process_ids())})"
