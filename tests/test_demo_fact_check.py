"""End-to-end test: the fact_check scenario walks the decentralized flow
and produces a quorum-ratified proof."""

import json
from pathlib import Path

from crisis_agents.cli import main as cli_main
from crisis_agents.mothership import Mothership
from crisis_agents.proof import (
    ProofDocument,
    build_proof,
    verify_proof_self_consistent,
)
from crisis_agents.scenarios import build_fact_check_scenario
from crisis_agents.vote import quorum_for


class TestFactCheckEndToEnd:

    def test_scenario_loads(self):
        s = build_fact_check_scenario()
        assert s.name == "fact_check"
        assert len(s.honest_agents) == 3
        assert s.byzantine_joiner.name == "agent_delta"
        assert "Pluto" in s.reference_doc

    def test_runs_through_all_phases(self):
        s = build_fact_check_scenario()
        m = Mothership()
        for a in s.honest_agents:
            m.add_agent(a)
        m.run_closed_phase()
        m.open_boundary(s.byzantine_joiner)
        # One async run, no clock — alarms emit and propagate inside the loop
        report = m.run_until_quiescent()
        assert report.reached_quiescence
        assert report.alarm_claims_emitted >= 3

        threshold = quorum_for(m.boundary.size())
        ratified_sets = [
            m.ratified_alarms_from(name)
            for name in ("agent_alpha", "agent_beta", "agent_gamma")
        ]
        assert ratified_sets[0] == ratified_sets[1] == ratified_sets[2]
        assert len(ratified_sets[0]) == 1
        r = ratified_sets[0][0]
        assert r.statement_id == "s03"
        assert r.quorum_threshold == threshold
        assert r.signer_count >= threshold

    def test_proof_round_trips_through_json(self, tmp_path):
        s = build_fact_check_scenario()
        m = Mothership()
        for a in s.honest_agents:
            m.add_agent(a)
        m.run_closed_phase()
        m.open_boundary(s.byzantine_joiner)
        m.run_until_quiescent()

        r = m.ratified_alarms_from("agent_alpha")[0]
        proof = build_proof(r)
        out = tmp_path / "proof.json"
        out.write_text(proof.to_json())

        reloaded = ProofDocument.from_json(out.read_text())
        assert verify_proof_self_consistent(reloaded).ok


class TestCli:

    def test_cli_demo_runs(self, tmp_path, capsys):
        exit_code = cli_main(["demo", "--scenario", "fact_check",
                              "--out-dir", str(tmp_path)])
        assert exit_code == 0
        captured = capsys.readouterr()

        # The five named phases appear
        for phase in ("Phase 1", "Phase 2", "Phase 3",
                      "Phase 4", "Phase 5", "Phase 6"):
            assert phase in captured.out

        # The chokepoint-free marker prints
        assert "no chokepoint" in captured.out

        # Exactly one proof file written
        proofs = list(tmp_path.glob("proof_*.json"))
        assert len(proofs) == 1
        obj = json.loads(proofs[0].read_text())
        assert obj["statement_id"] == "s03"
        assert len(obj["signer_process_id_hexes"]) >= 3

    def test_cli_verify_passes_on_valid_proof(self, tmp_path, capsys):
        cli_main(["demo", "--scenario", "fact_check", "--out-dir", str(tmp_path)])
        proof_path = next(tmp_path.glob("proof_*.json"))
        capsys.readouterr()

        exit_code = cli_main(["verify", str(proof_path)])
        assert exit_code == 0
        out = capsys.readouterr().out
        assert "self-consistent:    True" in out

    def test_cli_unknown_scenario(self, capsys):
        exit_code = cli_main(["demo", "--scenario", "nonexistent"])
        assert exit_code == 2
