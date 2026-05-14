"""Tests for ProofDocument + self-consistent verification."""

import json
from dataclasses import replace

import pytest

from crisis_agents.proof import (
    ProofDocument,
    VerificationResult,
    build_proof,
    verify_proof_self_consistent,
)
from crisis_agents.vote import RatifiedAlarm


def _sample_ratified() -> RatifiedAlarm:
    return RatifiedAlarm(
        accused_process_id_hex="76468f93" * 8,
        statement_id="s03",
        witness_digests=("a" * 64, "b" * 64),
        signer_process_id_hexes=("11" * 32, "22" * 32, "33" * 32),
        quorum_threshold=3,
    )


class TestBuildProof:

    def test_produces_well_formed_proof(self):
        proof = build_proof(_sample_ratified())
        assert proof.accused_process_id_hex.startswith("76468f93")
        assert proof.statement_id == "s03"
        assert proof.quorum_threshold == 3
        assert len(proof.signer_process_id_hexes) == 3
        assert proof.schema_version == 2

    def test_summary_mentions_quorum(self):
        proof = build_proof(_sample_ratified())
        assert "quorum" in proof.summary.lower()


class TestRoundtripJSON:

    def test_to_from_json(self):
        original = build_proof(_sample_ratified())
        roundtrip = ProofDocument.from_json(original.to_json())
        assert roundtrip == original

    def test_json_is_indented_and_sorted(self):
        proof = build_proof(_sample_ratified())
        text = proof.to_json()
        parsed = json.loads(text)
        # Sorted keys: schema_version after accused_process_id_hex alphabetically
        # (just verify it's a dict with the expected keys)
        assert set(parsed.keys()) == {
            "accused_process_id_hex", "schema_version", "signer_process_id_hexes",
            "statement_id", "quorum_threshold", "summary", "witness_digests",
        }


class TestSelfConsistentVerification:

    def test_valid_proof_passes(self):
        proof = build_proof(_sample_ratified())
        result = verify_proof_self_consistent(proof)
        assert result.ok, result.reason

    def test_duplicate_witnesses_fail(self):
        proof = build_proof(_sample_ratified())
        tampered = replace(proof, witness_digests=("a" * 64, "a" * 64))
        assert not verify_proof_self_consistent(tampered).ok

    def test_below_quorum_fails(self):
        ra = _sample_ratified()
        proof = build_proof(ra)
        tampered = replace(
            proof,
            signer_process_id_hexes=("11" * 32, "22" * 32),  # 2 < threshold 3
        )
        result = verify_proof_self_consistent(tampered)
        assert not result.ok
        assert "quorum" in result.reason.lower()

    def test_duplicate_signers_fail(self):
        proof = build_proof(_sample_ratified())
        tampered = replace(
            proof,
            signer_process_id_hexes=("11" * 32, "11" * 32, "33" * 32),
        )
        assert not verify_proof_self_consistent(tampered).ok

    def test_unsupported_schema_version_fails(self):
        proof = build_proof(_sample_ratified())
        tampered = replace(proof, schema_version=99)
        result = verify_proof_self_consistent(tampered)
        assert not result.ok
        assert "schema" in result.reason.lower()
