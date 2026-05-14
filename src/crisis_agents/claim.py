"""
Claim — the structured payload an agent emits.

A Claim is what gets JSON-serialized into a Crisis Message's `payload`
field. The Message itself carries the agent's stable process id (the
identity Crisis uses for mutation detection) and the causal digests;
the Claim carries the application-layer semantics of *what* the agent
is asserting.

Claim is intentionally narrow: a verdict on a statement with confidence
and free-text evidence. Anything richer (multi-claim batches, attached
artifacts) should be modeled by emitting multiple Claims that share a
correlation id, not by widening this struct.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from typing import ClassVar, Literal


Verdict = Literal["true", "false", "unknown"]


@dataclass(frozen=True)
class Claim:
    """A single adjudication an agent makes about one statement.

    Attributes:
        statement_id:       The scenario-defined identifier of the statement
                            being adjudicated (e.g. "s03"). Stable across
                            agents — that's how equivocation is detected.
        verdict:            "true" | "false" | "unknown".
        confidence:         Self-reported confidence in [0.0, 1.0].
        evidence:           Free-text justification, capped at 280 chars so
                            payloads stay bounded and visualizable later.
        timestamp_logical:  The emitting agent's local turn counter. Not
                            authoritative for Crisis ordering — Crisis derives
                            order from the DAG — but useful for debugging.
        schema_version:     Forward-compat bump if Claim's shape changes.
    """
    statement_id: str
    verdict: Verdict
    confidence: float
    evidence: str
    timestamp_logical: int
    schema_version: int = 1

    # Class constant, not a dataclass field — must be ClassVar so asdict()
    # doesn't serialize it into every payload.
    EVIDENCE_MAX_LEN: ClassVar[int] = 280

    def __post_init__(self):
        if not self.statement_id:
            raise ValueError("statement_id must be non-empty")
        if self.verdict not in ("true", "false", "unknown"):
            raise ValueError(f"verdict must be true/false/unknown, got {self.verdict!r}")
        if not 0.0 <= self.confidence <= 1.0:
            raise ValueError(f"confidence must be in [0, 1], got {self.confidence}")
        if len(self.evidence) > self.EVIDENCE_MAX_LEN:
            raise ValueError(
                f"evidence too long: {len(self.evidence)} > {self.EVIDENCE_MAX_LEN}"
            )
        if self.timestamp_logical < 0:
            raise ValueError(f"timestamp_logical must be >= 0, got {self.timestamp_logical}")

    def to_payload(self) -> bytes:
        """Serialize to bytes suitable for `Message.payload`.

        Uses sort_keys=True so two byte strings for the same logical claim
        are identical — which matters for equivocation detection: two
        equivocating claims that happen to have identical payloads aren't
        the same fault, they're an accidental duplicate.
        """
        return json.dumps(asdict(self), sort_keys=True, separators=(",", ":")).encode("utf-8")

    @classmethod
    def from_payload(cls, payload: bytes) -> "Claim":
        """Inverse of `to_payload`. Raises on malformed input."""
        try:
            obj = json.loads(payload.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as e:
            raise ValueError(f"payload is not valid Claim JSON: {e}") from e
        return cls(**obj)

    def to_dict(self) -> dict:
        return asdict(self)
