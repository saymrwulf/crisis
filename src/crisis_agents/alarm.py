"""
alarm.py — decentralized byzantine detection.

Every agent runs its own `detect_mutations()` against its **own**
LamportGraph. No privileged observer is needed; if gossip has propagated
both equivocating vertices into an honest agent's view, that agent will
see the same-id spacelike pair via `LamportGraph.find_mutations` and
return a `LocalAlarm`.

A `LocalAlarm` is the detector's first-person statement: "I, agent X,
observed agent Y emitting two contradictory vertices that are spacelike
in my graph at this moment." Several agents may independently produce
LocalAlarms about the same accused agent — that's the *point*. The
network gains confidence in an alarm as more honest detectors emit
matching ones.

The next module, `vote.py`, turns local alarms into network-ratified
alarms via gossip + quorum.
"""

from __future__ import annotations

from dataclasses import dataclass

from crisis.graph import LamportGraph
from crisis.message import Vertex

from crisis_agents.claim import Claim


@dataclass(frozen=True)
class LocalAlarm:
    """One agent's first-person observation of a same-id spacelike vertex pair.

    Note: this is the *detector's* perspective. Multiple detectors may emit
    LocalAlarms about the same accused agent; they're combined by the voting
    layer into a `RatifiedAlarm` once quorum is met.

    Attributes:
        detector_name:           Human name of the agent that detected it.
        detector_process_id_hex: 32-byte process_id of the detector (hex).
        accused_process_id_hex:  Process id of the agent the detector accuses.
        statement_id:            The application-layer subject of the equivocation.
        witness_digests:         Tuple of contradictory vertex digests (hex,
                                 sorted lexicographically for canonical
                                 cross-detector comparison).
    """
    detector_name: str
    detector_process_id_hex: str
    accused_process_id_hex: str
    statement_id: str
    witness_digests: tuple[str, str]


def detect_mutations_in_graph(graph: LamportGraph,
                               detector_name: str,
                               detector_process_id: bytes) -> list[LocalAlarm]:
    """Scan `graph` for same-id spacelike vertex groups and emit LocalAlarms.

    Skips the detector's own id (an agent doesn't accuse itself; if it
    finds same-id spacelike vertices in its own emissions it's witnessing
    its own bug, not byzantine behavior — that should be a hard failure
    rather than an alarm).

    For each accused id, if mutations exist, builds one LocalAlarm per
    distinct (statement_id, witness-pair) tuple. Pairs are formed from the
    first two vertices in each spacelike group; if a group has >2 spacelike
    vertices, we still emit just the first pair to keep the proof compact.
    Subsequent pairs can be derived if needed.
    """
    alarms: list[LocalAlarm] = []
    seen_process_ids = graph.all_process_ids()

    for pid in seen_process_ids:
        if pid == detector_process_id:
            continue
        mutation_groups = graph.find_mutations(pid)
        for group in mutation_groups:
            # Group vertices by their parsed statement_id; only equivocations
            # on the same statement count as mutations *for our purposes*. The
            # underlying Crisis graph already requires same-id; we add the
            # application-layer same-statement filter on top.
            by_statement: dict[str, list[Vertex]] = {}
            for v in group:
                try:
                    claim = Claim.from_payload(v.payload)
                except (ValueError, TypeError):
                    continue
                by_statement.setdefault(claim.statement_id, []).append(v)

            for statement_id, vertices in by_statement.items():
                if len(vertices) < 2:
                    continue
                # Canonicalize: sorted hex digests so two detectors who see
                # the same pair emit identical LocalAlarms.
                d1 = vertices[0].message_digest.hex()
                d2 = vertices[1].message_digest.hex()
                pair = tuple(sorted((d1, d2)))
                alarms.append(LocalAlarm(
                    detector_name=detector_name,
                    detector_process_id_hex=detector_process_id.hex(),
                    accused_process_id_hex=pid.hex(),
                    statement_id=statement_id,
                    witness_digests=pair,  # type: ignore[arg-type]
                ))

    return alarms
