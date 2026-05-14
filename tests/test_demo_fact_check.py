"""End-to-end test: fact_check scenario runs cleanly and emits a valid proof."""

import json
from pathlib import Path

from crisis_agents.alarm import scan_for_mutations
from crisis_agents.cli import main as cli_main
from crisis_agents.mothership import Mothership
from crisis_agents.proof import (
    build_proof,
    verify_proof_self_consistent,
)
from crisis_agents.scenarios import build_fact_check_scenario


class TestFactCheckEndToEnd:

    def test_scenario_loads(self):
        s = build_fact_check_scenario()
        assert s.name == "fact_check"
        assert len(s.honest_agents) == 3
        assert s.byzantine_joiner.name == "agent_delta"
        assert "Pluto" in s.reference_doc

    def test_runs_through_both_phases_and_raises_one_alarm(self):
        s = build_fact_check_scenario()
        m = Mothership()
        for agent in s.honest_agents:
            m.add_agent(agent)

        m.run_closed_phase(num_turns=s.closed_phase_turns)
        assert len(m.run_result.closed_log) == 3 * 6  # 3 agents × 6 statements
        assert m.all_graphs() == {}                   # no DAG in closed phase

        m.open_boundary(s.byzantine_joiner)
        m.run_crisis_phase(num_turns=s.crisis_phase_turns)

        # The byzantine emitted two contradictory variants of s03;
        # honest agents emitted nothing in the Crisis phase (their script
        # was exhausted in the closed phase).
        assert len(m.run_result.crisis_log) == 2

        alarms = scan_for_mutations(m)
        assert len(alarms) == 1
        a = alarms[0]
        assert a.accused_agent == "agent_delta"
        assert a.statement_id == "s03"
        assert a.spacelike_verified is True

    def test_proof_is_self_consistent_and_round_trips(self, tmp_path):
        s = build_fact_check_scenario()
        m = Mothership()
        for agent in s.honest_agents:
            m.add_agent(agent)
        m.run_closed_phase(num_turns=s.closed_phase_turns)
        m.open_boundary(s.byzantine_joiner)
        m.run_crisis_phase(num_turns=s.crisis_phase_turns)

        alarm = scan_for_mutations(m)[0]
        proof = build_proof(m, alarm)
        out = tmp_path / "proof.json"
        out.write_text(proof.to_json())

        # Reload, re-verify
        from crisis_agents.proof import ProofDocument
        reloaded = ProofDocument.from_json(out.read_text())
        assert verify_proof_self_consistent(reloaded).ok


class TestCli:

    def test_cli_demo_runs(self, tmp_path, capsys):
        exit_code = cli_main(["demo", "--scenario", "fact_check",
                              "--out-dir", str(tmp_path)])
        assert exit_code == 0
        captured = capsys.readouterr()
        assert "crisis-agents demo" in captured.out
        assert "Phase 1" in captured.out
        assert "Phase 2" in captured.out
        assert "alarm" in captured.out.lower()
        # A proof file landed
        proofs = list(tmp_path.glob("proof_*.json"))
        assert len(proofs) == 1
        # The proof file is valid JSON
        obj = json.loads(proofs[0].read_text())
        assert obj["accused_agent"] == "agent_delta"

    def test_cli_verify_passes_on_valid_proof(self, tmp_path, capsys):
        # First produce a proof via the demo
        cli_main(["demo", "--scenario", "fact_check", "--out-dir", str(tmp_path)])
        proof_path = next(tmp_path.glob("proof_*.json"))
        capsys.readouterr()    # drain demo output

        exit_code = cli_main(["verify", str(proof_path)])
        assert exit_code == 0
        out = capsys.readouterr().out
        assert "self-consistent: True" in out

    def test_cli_unknown_scenario(self, capsys):
        exit_code = cli_main(["demo", "--scenario", "nonexistent"])
        assert exit_code == 2
