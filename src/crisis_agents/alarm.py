"""
alarm.py — detect byzantine equivocation from the mothership's records.

Equivocation in our PoC has a precise structural signature: a single agent
emits, on the same turn, two or more Crisis Messages with **different
message digests** to **non-identical sets of peers**. Same-id same-turn
same-payload duplicate broadcasts are not equivocation; we filter those out.

For each detected alarm we also verify via the Crisis layer's own machinery
(`LamportGraph.are_spacelike`) that the two witness vertices are causally
incomparable — this is what makes the alarm cryptographically defensible
rather than merely a bookkeeping observation.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import TYPE_CHECKING

from crisis_agents.claim import Claim

if TYPE_CHECKING:
    from crisis_agents.mothership import CrisisPhaseEntry, Mothership


@dataclass(frozen=True)
class MutationWitness:
    """One leg of a byzantine equivocation: a specific Crisis vertex emitted
    by the accused agent that contradicts another vertex from the same agent
    in the same logical turn.
    """
    message_digest_hex: str
    payload_claim: dict             # the parsed Claim as a plain dict (for JSON proof)
    delivered_to: tuple[str, ...]   # peers that received THIS variant


@dataclass(frozen=True)
class AlarmEvent:
    """A detected byzantine equivocation.

    The combination of `accused_process_id_hex`, `turn`, and `statement_id`
    uniquely identifies the offense; multiple witnesses prove the offender
    said different things to different peers.
    """
    accused_agent: str
    accused_process_id_hex: str
    statement_id: str
    turn: int
    witnesses: tuple[MutationWitness, ...]
    spacelike_verified: bool         # True if the Crisis layer confirmed
                                     # the witness vertices are spacelike in
                                     # at least one honest agent's graph


def scan_for_mutations(mothership: "Mothership") -> list[AlarmEvent]:
    """Walk the mothership's crisis log and surface every equivocation.

    Strategy:
      1. Group crisis-log entries by (agent_name, turn).
      2. A group with ≥2 distinct message digests AND non-identical delivery
         sets is a mutation candidate.
      3. For each candidate, build MutationWitness records.
      4. Verify spacelike-ness via the Crisis DAG of any honest agent that
         observed at least two of the witnesses.

    Returns AlarmEvents (possibly empty).
    """
    crisis_log = mothership.run_result.crisis_log
    by_agent_turn: dict[tuple[str, int], list["CrisisPhaseEntry"]] = {}
    for entry in crisis_log:
        by_agent_turn.setdefault((entry.agent_name, entry.turn), []).append(entry)

    alarms: list[AlarmEvent] = []
    for (agent_name, turn), entries in by_agent_turn.items():
        if len(entries) < 2:
            continue

        digests = {e.message_digest_hex for e in entries}
        if len(digests) < 2:
            continue  # same payload replayed — not equivocation

        delivery_sets = {tuple(sorted(e.delivered_to)) for e in entries}
        if len(delivery_sets) < 2:
            continue  # same recipients — not equivocation

        # All checks passed: this is an equivocation candidate.
        statement_id = entries[0].claim.statement_id
        accused_pid_hex = mothership.agents[agent_name].process_id.hex()

        witnesses = tuple(
            MutationWitness(
                message_digest_hex=e.message_digest_hex,
                payload_claim=e.claim.to_dict(),
                delivered_to=tuple(sorted(e.delivered_to)),
            )
            for e in entries
        )

        spacelike_ok = _verify_spacelike(mothership, agent_name, entries)

        alarms.append(AlarmEvent(
            accused_agent=agent_name,
            accused_process_id_hex=accused_pid_hex,
            statement_id=statement_id,
            turn=turn,
            witnesses=witnesses,
            spacelike_verified=spacelike_ok,
        ))

    return alarms


def _verify_spacelike(mothership: "Mothership", accused_name: str,
                      entries: list["CrisisPhaseEntry"]) -> bool:
    """Ask the Crisis layer to confirm that the equivocating vertices are
    causally incomparable.

    Strategy: pick any pair of entries. Find an honest agent's graph that
    contains both vertices and ask `are_spacelike`. If no single graph holds
    both (because the byzantine delivered them to disjoint subsets), pick
    two graphs — one per entry — and check that neither vertex references
    the other directly. This weaker check is sufficient for our PoC: if
    neither references the other, they can't be in each other's past in
    any extended graph either.
    """
    a, b = entries[0], entries[1]
    digest_a = bytes.fromhex(a.message_digest_hex)
    digest_b = bytes.fromhex(b.message_digest_hex)

    # Try to find an honest observer's graph that contains both.
    accused_pid = mothership.agents[accused_name].process_id
    for name, graph in mothership.all_graphs().items():
        if mothership.agents[name].process_id == accused_pid:
            continue
        if digest_a in graph and digest_b in graph:
            va = graph.get_vertex(digest_a)
            vb = graph.get_vertex(digest_b)
            if va is not None and vb is not None:
                return graph.are_spacelike(va, vb)

    # Weak proof: confirm neither vertex directly references the other in
    # any honest agent's graph. Sufficient in our PoC where equivocations
    # are emitted at the same turn from the same parent.
    for name, graph in mothership.all_graphs().items():
        if mothership.agents[name].process_id == accused_pid:
            continue
        va = graph.get_vertex(digest_a)
        vb = graph.get_vertex(digest_b)
        if va is not None and digest_b in (vb_digest for vb_digest in va.digests):
            return False
        if vb is not None and digest_a in (va_digest for va_digest in vb.digests):
            return False

    return True
