"""Tests for proof generation and self-consistent verification."""

import json

from crisis_agents.agent import MockAgent, MockByzantineAgent
from crisis_agents.alarm import scan_for_mutations
from crisis_agents.claim import Claim
from crisis_agents.mothership import Mothership
from crisis_agents.proof import (
    ProofDocument,
    build_proof,
    verify_proof_self_consistent,
)


def _claim(sid: str, verdict: str = "true", evidence: str = "ok") -> Claim:
    return Claim(statement_id=sid, verdict=verdict, confidence=0.9,  # type: ignore[arg-type]
                 evidence=evidence, timestamp_logical=0)


def _equivocating_run() -> tuple[Mothership, list]:
    m = Mothership()
    m.add_agent(MockAgent("a", [[]]))
    m.add_agent(MockAgent("b", [[]]))
    m.add_agent(MockAgent("c", [[]]))
    m.open_boundary(MockByzantineAgent(
        "d",
        scripted_pairs=[(
            _claim("s03", verdict="true", evidence="to_a"),
            _claim("s03", verdict="false", evidence="to_b"),
        )],
        split_a={"a", "c"},
        split_b={"b"},
    ))
    m.run_crisis_phase(num_turns=1)
    alarms = scan_for_mutations(m)
    return m, alarms


class TestBuildProof:

    def test_produces_well_formed_proof(self):
        m, alarms = _equivocating_run()
        assert len(alarms) == 1
        proof = build_proof(m, alarms[0])
        assert proof.accused_agent == "d"
        assert proof.statement_id == "s03"
        assert proof.turn == 0
        assert len(proof.witnesses) == 2
        assert proof.spacelike_verified is True

    def test_dag_witnesses_reference_real_graphs(self):
        m, alarms = _equivocating_run()
        proof = build_proof(m, alarms[0])
        assert len(proof.dag_witnesses) == 2

        # Each dag_witness should name only honest agents (not "d")
        for dw in proof.dag_witnesses:
            assert "d" not in dw.observed_by

        # Each variant should have been observed by at least one honest agent
        # (the variant's delivered-to subset)
        for dw in proof.dag_witnesses:
            assert len(dw.observed_by) >= 1


class TestJsonRoundtrip:

    def test_to_json_is_valid(self):
        m, alarms = _equivocating_run()
        proof = build_proof(m, alarms[0])
        text = proof.to_json()
        parsed = json.loads(text)
        assert parsed["accused_agent"] == "d"
        assert parsed["statement_id"] == "s03"

    def test_from_json_inverts_to_json(self):
        m, alarms = _equivocating_run()
        original = build_proof(m, alarms[0])
        roundtrip = ProofDocument.from_json(original.to_json())
        assert roundtrip.accused_agent == original.accused_agent
        assert roundtrip.statement_id == original.statement_id
        assert roundtrip.turn == original.turn
        assert roundtrip.spacelike_verified == original.spacelike_verified
        assert len(roundtrip.witnesses) == len(original.witnesses)


class TestSelfConsistentVerification:

    def test_valid_proof_passes(self):
        m, alarms = _equivocating_run()
        proof = build_proof(m, alarms[0])
        result = verify_proof_self_consistent(proof)
        assert result.ok, result.reason

    def test_tampered_witness_digest_fails(self):
        """If someone alters a witness digest after-the-fact to make it look
        like a duplicate, self-consistency check catches the lack of distinct
        digests."""
        m, alarms = _equivocating_run()
        proof = build_proof(m, alarms[0])
        # Tamper: make both digests identical
        from dataclasses import replace
        from crisis_agents.alarm import MutationWitness
        w0 = proof.witnesses[0]
        w1 = proof.witnesses[1]
        tampered = ProofDocument(
            schema_version=proof.schema_version,
            accused_agent=proof.accused_agent,
            accused_process_id_hex=proof.accused_process_id_hex,
            statement_id=proof.statement_id,
            turn=proof.turn,
            witnesses=(w0, replace(w1, message_digest_hex=w0.message_digest_hex)),
            dag_witnesses=proof.dag_witnesses,
            spacelike_verified=proof.spacelike_verified,
            proof_summary=proof.proof_summary,
        )
        result = verify_proof_self_consistent(tampered)
        assert not result.ok
        assert "duplicate" in result.reason.lower()

    def test_mismatched_statement_id_fails(self):
        m, alarms = _equivocating_run()
        proof = build_proof(m, alarms[0])
        from dataclasses import replace
        bad = ProofDocument(
            schema_version=proof.schema_version,
            accused_agent=proof.accused_agent,
            accused_process_id_hex=proof.accused_process_id_hex,
            statement_id="DIFFERENT",      # mismatch
            turn=proof.turn,
            witnesses=proof.witnesses,
            dag_witnesses=proof.dag_witnesses,
            spacelike_verified=proof.spacelike_verified,
            proof_summary=proof.proof_summary,
        )
        result = verify_proof_self_consistent(bad)
        assert not result.ok
