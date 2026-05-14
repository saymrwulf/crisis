"""
vote.py — turn local alarms into ratified alarms via gossip + quorum.

Design:
  1. An honest agent that detects a mutation emits an `AlarmClaim` —
     a special payload structured like a Crisis Claim but with `kind="alarm"`
     and the accused/witnesses encoded in fields. AlarmClaims are wrapped
     into ordinary Crisis Messages with the *detector's* process id, so they
     gossip through the network like everything else.

  2. After enough gossip, every honest agent's graph contains AlarmClaim
     vertices from every other honest detector. Tallying happens locally:
     `count_alarm_votes(graph, accused, statement_id)` counts unique signer
     ids and returns the set of detectors who have weighed in.

  3. A `RatifiedAlarm` is produced when ≥ quorum_threshold detectors agree
     on the same (accused, statement_id, witness_digests) tuple.

The quorum threshold is `ceil(2 * N_trusted / 3)` where N_trusted is the
size of the boundary set at the moment of ratification. In the canonical
fact_check scenario: N=4 (3 honest + 1 byzantine), 2/3 rounded up = 3. So
all three honest detectors must concur — exactly the protection we want
against a single byzantine accuser ostracizing an honest agent.
"""

from __future__ import annotations

import json
import math
from dataclasses import asdict, dataclass, field

from crisis.graph import LamportGraph

from crisis_agents.alarm import LocalAlarm


ALARM_KIND = "alarm"


@dataclass(frozen=True)
class AlarmClaim:
    """An on-the-wire alarm — the detector's statement, signed via the
    Crisis message wrapping (process_id + PoW nonce).

    Serializes to JSON for the Crisis Message payload. Recognizable by
    `kind == "alarm"`, distinguishing it from a regular `Claim` payload
    (which has `kind` absent or != "alarm" by convention).
    """
    accused_process_id_hex: str
    statement_id: str
    witness_digests: tuple[str, str]
    detected_at_turn: int
    kind: str = ALARM_KIND

    def to_payload(self) -> bytes:
        return json.dumps(asdict(self), sort_keys=True, separators=(",", ":")).encode("utf-8")

    @classmethod
    def from_payload(cls, payload: bytes) -> "AlarmClaim":
        obj = json.loads(payload.decode("utf-8"))
        if obj.get("kind") != ALARM_KIND:
            raise ValueError("not an AlarmClaim payload")
        return cls(
            accused_process_id_hex=obj["accused_process_id_hex"],
            statement_id=obj["statement_id"],
            witness_digests=tuple(obj["witness_digests"]),  # type: ignore[arg-type]
            detected_at_turn=obj["detected_at_turn"],
        )

    @classmethod
    def from_local_alarm(cls, alarm: LocalAlarm, detected_at_turn: int) -> "AlarmClaim":
        return cls(
            accused_process_id_hex=alarm.accused_process_id_hex,
            statement_id=alarm.statement_id,
            witness_digests=alarm.witness_digests,
            detected_at_turn=detected_at_turn,
        )


@dataclass(frozen=True)
class RatifiedAlarm:
    """Network-level consensus on a byzantine equivocation.

    Produced by `tally_alarms()` when ≥ quorum signers have emitted matching
    AlarmClaims into a graph.
    """
    accused_process_id_hex: str
    statement_id: str
    witness_digests: tuple[str, str]
    signer_process_id_hexes: tuple[str, ...]   # sorted, unique
    quorum_threshold: int

    @property
    def signer_count(self) -> int:
        return len(self.signer_process_id_hexes)


def quorum_for(n_trusted: int) -> int:
    """Quorum threshold: ceil(2 * n / 3)."""
    return math.ceil(2 * n_trusted / 3)


def collect_alarm_claims(graph: LamportGraph) -> list[tuple[bytes, AlarmClaim]]:
    """Walk `graph` and return every (signer_process_id, AlarmClaim) pair.

    Vertices that aren't AlarmClaim-payloaded are skipped silently. The
    signer's process id is the vertex's `id` field — that's the Crisis-layer
    cryptographic signature of who emitted the claim.
    """
    out: list[tuple[bytes, AlarmClaim]] = []
    for v in graph.all_vertices():
        try:
            claim = AlarmClaim.from_payload(v.payload)
        except (ValueError, TypeError):
            continue
        out.append((v.id, claim))
    return out


def tally_alarms(graph: LamportGraph, *, quorum_threshold: int) -> list[RatifiedAlarm]:
    """Count AlarmClaims in `graph` and emit RatifiedAlarms for groups that
    meet quorum.

    Groups by (accused, statement_id, witness_digests). Counts unique signer
    process_ids per group. If the count meets or exceeds `quorum_threshold`,
    the group ratifies.

    The same agent's graph being scanned multiple times produces identical
    results — there's no implicit ordering or non-determinism. Two agents'
    graphs that have converged via gossip produce the same RatifiedAlarms.
    """
    by_group: dict[tuple[str, str, tuple[str, str]], set[bytes]] = {}
    for signer_pid, claim in collect_alarm_claims(graph):
        key = (claim.accused_process_id_hex, claim.statement_id, claim.witness_digests)
        by_group.setdefault(key, set()).add(signer_pid)

    ratified: list[RatifiedAlarm] = []
    for (accused, statement_id, witnesses), signers in by_group.items():
        if len(signers) >= quorum_threshold:
            ratified.append(RatifiedAlarm(
                accused_process_id_hex=accused,
                statement_id=statement_id,
                witness_digests=witnesses,
                signer_process_id_hexes=tuple(sorted(s.hex() for s in signers)),
                quorum_threshold=quorum_threshold,
            ))
    # Stable ordering so equal graphs produce equal lists
    ratified.sort(key=lambda r: (r.accused_process_id_hex, r.statement_id))
    return ratified
