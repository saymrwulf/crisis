"""Tests for the Claim payload dataclass."""

import json

import pytest

from crisis_agents.claim import Claim


class TestClaimConstruction:

    def test_basic_claim_roundtrip(self):
        c = Claim(
            statement_id="s01",
            verdict="true",
            confidence=0.95,
            evidence="The reference doc states this directly in paragraph 2.",
            timestamp_logical=3,
        )
        assert c.statement_id == "s01"
        assert c.verdict == "true"
        assert c.confidence == pytest.approx(0.95)
        assert c.schema_version == 1

    def test_unknown_verdict_accepted(self):
        c = Claim(statement_id="s02", verdict="unknown", confidence=0.5,
                  evidence="no signal", timestamp_logical=0)
        assert c.verdict == "unknown"


class TestClaimValidation:

    def test_empty_statement_id_rejected(self):
        with pytest.raises(ValueError, match="statement_id"):
            Claim(statement_id="", verdict="true", confidence=0.9,
                  evidence="x", timestamp_logical=0)

    def test_invalid_verdict_rejected(self):
        with pytest.raises(ValueError, match="verdict"):
            Claim(statement_id="s01", verdict="maybe",  # type: ignore[arg-type]
                  confidence=0.9, evidence="x", timestamp_logical=0)

    def test_confidence_out_of_range(self):
        with pytest.raises(ValueError, match="confidence"):
            Claim(statement_id="s01", verdict="true", confidence=1.5,
                  evidence="x", timestamp_logical=0)
        with pytest.raises(ValueError, match="confidence"):
            Claim(statement_id="s01", verdict="true", confidence=-0.1,
                  evidence="x", timestamp_logical=0)

    def test_evidence_too_long(self):
        with pytest.raises(ValueError, match="evidence too long"):
            Claim(statement_id="s01", verdict="true", confidence=0.9,
                  evidence="x" * 500, timestamp_logical=0)

    def test_negative_timestamp_rejected(self):
        with pytest.raises(ValueError, match="timestamp"):
            Claim(statement_id="s01", verdict="true", confidence=0.9,
                  evidence="x", timestamp_logical=-1)


class TestPayloadRoundtrip:

    def test_to_payload_returns_bytes(self):
        c = Claim(statement_id="s01", verdict="true", confidence=0.9,
                  evidence="ok", timestamp_logical=2)
        b = c.to_payload()
        assert isinstance(b, bytes)
        # Valid JSON
        obj = json.loads(b.decode("utf-8"))
        assert obj["statement_id"] == "s01"

    def test_from_payload_inverts_to_payload(self):
        original = Claim(statement_id="s04", verdict="false", confidence=0.72,
                         evidence="contradicted by para 3", timestamp_logical=7)
        roundtrip = Claim.from_payload(original.to_payload())
        assert roundtrip == original

    def test_payload_is_deterministic(self):
        """Same logical claim must produce identical bytes — required so two
        equivocating-but-payload-identical messages can be detected as the
        same payload (vs. different payload = real equivocation)."""
        c1 = Claim(statement_id="s01", verdict="true", confidence=0.9,
                   evidence="evidence here", timestamp_logical=1)
        c2 = Claim(statement_id="s01", verdict="true", confidence=0.9,
                   evidence="evidence here", timestamp_logical=1)
        assert c1.to_payload() == c2.to_payload()

    def test_from_payload_rejects_garbage(self):
        with pytest.raises(ValueError, match="Claim JSON"):
            Claim.from_payload(b"not json")

    def test_from_payload_rejects_missing_fields(self):
        with pytest.raises(TypeError):
            # Missing required statement_id
            Claim.from_payload(b'{"verdict":"true","confidence":0.9,"evidence":"x","timestamp_logical":0}')

    def test_payload_size_is_bounded(self):
        """Confirms the EVIDENCE_MAX_LEN cap keeps payload under a sane size."""
        c = Claim(statement_id="s99", verdict="true", confidence=1.0,
                  evidence="x" * 280, timestamp_logical=999)
        b = c.to_payload()
        # JSON overhead + 280 evidence + small fields ~= < 400 bytes
        assert len(b) < 500
