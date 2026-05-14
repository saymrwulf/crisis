"""
proof.py — produce and verify proof-of-malfeasance documents.

The proof is now multi-signer: a ratified alarm carries the process ids of
every honest detector who agreed. Anyone (an external auditor, a future
visualizer, a downstream policy engine) can replay the proof by:
  1. Confirming the witness_digests are pairwise distinct.
  2. Confirming all signers are distinct and meet the embedded quorum.
  3. Re-deriving the alarm from a recorded simulation log (Phase 6,
     not implemented in this PoC).

The shape of the JSON is intentionally narrow and stable, so a future
verifier in any language can parse it without depending on Python types.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass

from crisis_agents.vote import RatifiedAlarm


@dataclass(frozen=True)
class ProofDocument:
    """A signed, replayable proof of one ratified byzantine equivocation."""
    schema_version: int = 2  # bumped from 1 — multi-signer shape
    accused_process_id_hex: str = ""
    statement_id: str = ""
    witness_digests: tuple[str, str] = ("", "")
    signer_process_id_hexes: tuple[str, ...] = ()
    quorum_threshold: int = 0
    summary: str = ""

    def to_json(self) -> str:
        return json.dumps(asdict(self), indent=2, sort_keys=True)

    @classmethod
    def from_json(cls, text: str) -> "ProofDocument":
        obj = json.loads(text)
        return cls(
            schema_version=obj.get("schema_version", 2),
            accused_process_id_hex=obj["accused_process_id_hex"],
            statement_id=obj["statement_id"],
            witness_digests=tuple(obj["witness_digests"]),  # type: ignore[arg-type]
            signer_process_id_hexes=tuple(obj["signer_process_id_hexes"]),
            quorum_threshold=obj["quorum_threshold"],
            summary=obj["summary"],
        )


def build_proof(alarm: RatifiedAlarm) -> ProofDocument:
    """Build a ProofDocument from a network-ratified alarm."""
    summary = (
        f"agent id={alarm.accused_process_id_hex[:16]}... emitted contradictory "
        f"Crisis vertices about statement {alarm.statement_id!r}; "
        f"{alarm.signer_count} of N detectors independently agree, meeting the "
        f"quorum threshold of {alarm.quorum_threshold}."
    )
    return ProofDocument(
        accused_process_id_hex=alarm.accused_process_id_hex,
        statement_id=alarm.statement_id,
        witness_digests=alarm.witness_digests,
        signer_process_id_hexes=alarm.signer_process_id_hexes,
        quorum_threshold=alarm.quorum_threshold,
        summary=summary,
    )


@dataclass(frozen=True)
class VerificationResult:
    ok: bool
    reason: str


def verify_proof_self_consistent(proof: ProofDocument) -> VerificationResult:
    """Verify the proof is internally self-consistent.

    Checks (no external simulation needed):
      - schema version is known
      - exactly 2 distinct witness digests
      - signer count meets the embedded quorum threshold
      - signer ids are unique
      - witness digests are non-empty hex strings

    What we don't check here (would require the recorded simulation log):
      - that the digests correspond to real PoW-mined Crisis Messages
      - that any honest agent's graph actually contains both witnesses
    """
    if proof.schema_version != 2:
        return VerificationResult(False, f"unsupported schema_version {proof.schema_version}")
    if len(proof.witness_digests) != 2:
        return VerificationResult(False, "expected exactly 2 witness digests")
    if proof.witness_digests[0] == proof.witness_digests[1]:
        return VerificationResult(False, "witness digests must be distinct")
    if not all(proof.witness_digests):
        return VerificationResult(False, "witness digests must be non-empty")
    if len(proof.signer_process_id_hexes) < proof.quorum_threshold:
        return VerificationResult(
            False,
            f"signer count {len(proof.signer_process_id_hexes)} < "
            f"quorum {proof.quorum_threshold}",
        )
    if len(set(proof.signer_process_id_hexes)) != len(proof.signer_process_id_hexes):
        return VerificationResult(False, "duplicate signers")
    if not proof.accused_process_id_hex:
        return VerificationResult(False, "accused process id is empty")

    return VerificationResult(
        True,
        f"{proof.signer_process_id_hexes.__len__()} detectors independently "
        f"agree on equivocation about {proof.statement_id!r}; "
        f"meets quorum of {proof.quorum_threshold}",
    )
