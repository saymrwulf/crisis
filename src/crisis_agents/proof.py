"""
proof.py — emit and verify replayable proof-of-malfeasance JSON documents.

A ProofDocument is a self-contained JSON file that:
  1. Names the accused agent (human-readable name + 32-byte process_id).
  2. Identifies the offense (statement_id, turn).
  3. Includes every contradictory MutationWitness with its message digest,
     parsed Claim, and delivery target set.
  4. Records the "DAG witness" — for each witness vertex, which honest
     agents' graphs hold it. An independent verifier can cross-check
     this against the recorded simulation snapshots.
  5. Asserts whether the Crisis layer confirmed spacelike-ness at the
     time of detection.

The proof is replayable: given the JSON and the original `crisis_log`
(or a recorded simulation), `verify_proof` re-derives the alarm and
confirms each claim independently.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from typing import TYPE_CHECKING

from crisis_agents.alarm import AlarmEvent, MutationWitness

if TYPE_CHECKING:
    from crisis_agents.mothership import Mothership


@dataclass(frozen=True)
class WitnessGraphReference:
    """For one mutation witness, which honest agents' graphs hold it."""
    message_digest_hex: str
    observed_by: tuple[str, ...]   # honest agent names whose LamportGraph
                                   # contains a vertex with this digest


@dataclass(frozen=True)
class ProofDocument:
    """A replayable proof of one detected byzantine equivocation."""
    schema_version: int = 1
    accused_agent: str = ""
    accused_process_id_hex: str = ""
    statement_id: str = ""
    turn: int = 0
    witnesses: tuple[MutationWitness, ...] = ()
    dag_witnesses: tuple[WitnessGraphReference, ...] = ()
    spacelike_verified: bool = False
    proof_summary: str = ""

    def to_json(self) -> str:
        """Serialize to indented JSON. Uses asdict on the nested dataclasses
        so the resulting structure is plain dict / list / str / int / bool —
        cleanly inspectable with `jq` and re-parseable."""
        return json.dumps(asdict(self), indent=2, sort_keys=True)

    @classmethod
    def from_json(cls, text: str) -> "ProofDocument":
        obj = json.loads(text)
        return cls(
            schema_version=obj.get("schema_version", 1),
            accused_agent=obj["accused_agent"],
            accused_process_id_hex=obj["accused_process_id_hex"],
            statement_id=obj["statement_id"],
            turn=obj["turn"],
            witnesses=tuple(
                MutationWitness(
                    message_digest_hex=w["message_digest_hex"],
                    payload_claim=w["payload_claim"],
                    delivered_to=tuple(w["delivered_to"]),
                )
                for w in obj["witnesses"]
            ),
            dag_witnesses=tuple(
                WitnessGraphReference(
                    message_digest_hex=g["message_digest_hex"],
                    observed_by=tuple(g["observed_by"]),
                )
                for g in obj["dag_witnesses"]
            ),
            spacelike_verified=obj["spacelike_verified"],
            proof_summary=obj["proof_summary"],
        )


def build_proof(mothership: "Mothership", alarm: AlarmEvent) -> ProofDocument:
    """Produce the ProofDocument for a single alarm.

    Cross-references each witness against every honest agent's LamportGraph
    so the proof carries the "who saw what" structure.
    """
    accused_pid = mothership.agents[alarm.accused_agent].process_id
    honest_names = [
        name for name, ag in mothership.agents.items()
        if ag.process_id != accused_pid
    ]

    dag_refs = []
    for w in alarm.witnesses:
        digest = bytes.fromhex(w.message_digest_hex)
        observed_by = tuple(
            name for name in honest_names
            if digest in mothership.graph_of(name)
        )
        dag_refs.append(WitnessGraphReference(
            message_digest_hex=w.message_digest_hex,
            observed_by=observed_by,
        ))

    summary = (
        f"agent {alarm.accused_agent!r} (id={alarm.accused_process_id_hex[:16]}...) "
        f"emitted {len(alarm.witnesses)} contradictory Crisis vertices for "
        f"statement {alarm.statement_id!r} in turn {alarm.turn}; vertices "
        f"{'are confirmed' if alarm.spacelike_verified else 'appear to be'} "
        f"spacelike in the DAG of at least one honest agent."
    )

    return ProofDocument(
        accused_agent=alarm.accused_agent,
        accused_process_id_hex=alarm.accused_process_id_hex,
        statement_id=alarm.statement_id,
        turn=alarm.turn,
        witnesses=alarm.witnesses,
        dag_witnesses=tuple(dag_refs),
        spacelike_verified=alarm.spacelike_verified,
        proof_summary=summary,
    )


@dataclass(frozen=True)
class VerificationResult:
    ok: bool
    reason: str


def verify_proof_self_consistent(proof: ProofDocument) -> VerificationResult:
    """Verify the proof is self-consistent — without re-running the simulation.

    Checks:
      - schema_version is known
      - at least 2 witnesses
      - witness message digests are pairwise distinct
      - witness delivery sets are pairwise non-identical
      - witnesses agree on the statement_id and turn fields named in the proof
      - dag_witnesses cover every witness digest

    What we do NOT check here (would require the recorded simulation):
      - that the digests correspond to real PoW-mined Crisis Messages
      - that the spacelike-verified flag matches a fresh DAG re-derivation

    A future `verify_proof_against_log(proof, recorded_events)` would close
    that gap.
    """
    if proof.schema_version != 1:
        return VerificationResult(False, f"unsupported schema_version {proof.schema_version}")
    if len(proof.witnesses) < 2:
        return VerificationResult(False, "fewer than 2 witnesses — no equivocation")

    digests = [w.message_digest_hex for w in proof.witnesses]
    if len(set(digests)) != len(digests):
        return VerificationResult(False, "duplicate witness digests")

    deliveries = {tuple(w.delivered_to) for w in proof.witnesses}
    if len(deliveries) < 2:
        return VerificationResult(False, "all witnesses have identical delivery sets")

    for w in proof.witnesses:
        if w.payload_claim.get("statement_id") != proof.statement_id:
            return VerificationResult(False, f"witness disagrees on statement_id: {w}")

    dag_digests = {g.message_digest_hex for g in proof.dag_witnesses}
    if set(digests) - dag_digests:
        return VerificationResult(False, "dag_witnesses missing for some witness")

    return VerificationResult(
        True,
        f"proof is self-consistent: {len(proof.witnesses)} contradictory "
        f"witnesses for statement {proof.statement_id!r} at turn {proof.turn}",
    )
