"""
crisis-agents — command-line entry point.

Subcommands:
    demo    Run a scripted scenario end-to-end. Walks the four phases:
            closed team → boundary opens → Crisis-active rounds + gossip →
            decentralized detection + alarm voting → proof emission.
    verify  Re-check a proof JSON for self-consistency.

Examples:
    crisis-agents demo --scenario fact_check
    crisis-agents demo --scenario fact_check --live
    crisis-agents verify proof_agent_delta_s03.json
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from crisis_agents.mothership import Mothership
from crisis_agents.proof import (
    ProofDocument,
    build_proof,
    verify_proof_self_consistent,
)
from crisis_agents.scenarios import build_fact_check_scenario
from crisis_agents.vote import quorum_for


SCENARIOS = {
    "fact_check": build_fact_check_scenario,
}


def _run_demo(args: argparse.Namespace) -> int:
    if args.scenario not in SCENARIOS:
        print(f"unknown scenario: {args.scenario}", file=sys.stderr)
        print(f"available: {', '.join(SCENARIOS)}", file=sys.stderr)
        return 2

    builder = SCENARIOS[args.scenario]
    scenario = builder(live=args.live, model=args.model)

    mode = "live" if args.live else "mocked"
    print(f"=== crisis-agents demo: {scenario.name} ({mode}) ===\n")
    print(scenario.description)
    print()

    mothership = Mothership()
    for agent in scenario.honest_agents:
        mothership.add_agent(agent)

    # ---- Phase 1: closed team, no Crisis ----
    print(f"--- Phase 1: closed team, no Crisis ({scenario.closed_phase_turns} turn(s)) ---")
    mothership.run_closed_phase(num_turns=scenario.closed_phase_turns)
    honest_names = [a.name for a in mothership.agents.values()]
    print(
        f"  {len(mothership.run_result.closed_log)} claims from "
        f"{len(honest_names)} honest agent(s): {', '.join(honest_names)}"
    )
    print(f"  Per-agent graphs: not yet allocated (Crisis is dormant).\n")

    # ---- Phase 2: boundary opens ----
    print(f"--- Phase 2: boundary opens — {scenario.byzantine_joiner.name} joins ---")
    mothership.open_boundary(scenario.byzantine_joiner)
    print(f"  Trust set is now {mothership.boundary.size()} agents.")
    print(f"  Crisis is now ACTIVE for every subsequent emission.\n")

    # ---- Phase 3: Crisis-active rounds (emission + gossip) ----
    print(f"--- Phase 3: emission + gossip "
          f"({scenario.crisis_phase_turns} turn(s)) ---")
    mothership.run_crisis_phase(
        num_turns=scenario.crisis_phase_turns,
        gossip_rounds_per_turn=1,
    )
    crisis_log = mothership.run_result.crisis_log
    print(f"  {len(crisis_log)} Crisis messages emitted.")
    print(f"  After gossip:")
    for name, agent in mothership.agents.items():
        print(f"    {name:14s} graph: {agent.graph.vertex_count():2d} vertices")
    print()

    # ---- Phase 4: each agent independently detects ----
    print("--- Phase 4: decentralized detection (each agent's own brain) ---")
    local_alarms = {}
    for name, agent in mothership.agents.items():
        alarms = agent.detect_mutations()
        local_alarms[name] = alarms
        marker = "ALARM" if alarms else "ok   "
        suffix = ""
        if alarms:
            suffix = (f" — accuses {alarms[0].accused_process_id_hex[:16]}... "
                      f"on {alarms[0].statement_id}")
        print(f"    [{marker}] {name:14s}{suffix}")
    detector_count = sum(1 for a in local_alarms.values() if a)
    print(f"  {detector_count} of {len(mothership.agents)} agents independently "
          f"detected byzantine behavior.\n")

    # ---- Phase 5: alarm emission + quorum voting ----
    print("--- Phase 5: alarms emitted + gossiped + ratified by quorum ---")
    mothership.emit_alarms_from_detectors()
    mothership.run_gossip_round()
    threshold = quorum_for(mothership.boundary.size())
    print(f"  Quorum threshold = ⌈2*{mothership.boundary.size()}/3⌉ = {threshold}")

    # All honest agents should agree on the ratified set — show by querying
    # each of them and confirming.
    ratified_per_agent = {
        name: mothership.ratified_alarms_from(name)
        for name in mothership.agents
    }
    canonical = None
    all_agree = True
    for name in honest_names:
        if canonical is None:
            canonical = ratified_per_agent[name]
        elif ratified_per_agent[name] != canonical:
            all_agree = False
    if all_agree:
        marker = "✓"
    else:
        marker = "✗"
    print(f"  {marker} every honest agent's ratified set is identical "
          f"({'no chokepoint' if all_agree else 'DIVERGENCE'}).")

    if not canonical:
        print("  (No alarms ratified.)\n")
        return 0

    for r in canonical:
        print(f"  ⚠ RATIFIED: accused={r.accused_process_id_hex[:16]}... on "
              f"{r.statement_id!r}, signed by "
              f"{r.signer_count}/{mothership.boundary.size()} agents.")
    print()

    # ---- Phase 6: emit proof JSON ----
    print("--- Phase 6: write proofs ---")
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for r in canonical:
        proof = build_proof(r)
        # Use a stable filename based on accused + statement
        accused_short = r.accused_process_id_hex[:16]
        path = out_dir / f"proof_{accused_short}_{r.statement_id}.json"
        path.write_text(proof.to_json())
        print(f"  wrote {path}")
        check = verify_proof_self_consistent(proof)
        marker = "OK" if check.ok else "FAIL"
        print(f"    self-consistency: {marker} — {check.reason}")
    print()
    return 0


def _run_verify(args: argparse.Namespace) -> int:
    path = Path(args.proof_path)
    if not path.exists():
        print(f"file not found: {path}", file=sys.stderr)
        return 2
    proof = ProofDocument.from_json(path.read_text())
    result = verify_proof_self_consistent(proof)
    print(f"proof: {path}")
    print(f"  accused process_id: {proof.accused_process_id_hex[:16]}...")
    print(f"  statement_id:       {proof.statement_id}")
    print(f"  signers:            {len(proof.signer_process_id_hexes)}/"
          f"≥{proof.quorum_threshold}")
    print(f"  self-consistent:    {result.ok}")
    print(f"  reason:             {result.reason}")
    return 0 if result.ok else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="crisis-agents",
        description="Crisis-Agents — decentralized coordination for AI agent teams.",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    demo = sub.add_parser("demo", help="run a scripted scenario end-to-end")
    demo.add_argument("--scenario", default="fact_check",
                      help="which scenario to run (default: fact_check)")
    demo.add_argument("--live", action="store_true",
                      help="back the honest agents with real Claude API calls "
                           "(requires anthropic SDK + ANTHROPIC_API_KEY)")
    demo.add_argument("--model", default=None,
                      help="Anthropic model id for --live (default: "
                           "claude-haiku-4-5-20251001)")
    demo.add_argument("--out-dir", default=".",
                      help="where to write proof JSON files (default: cwd)")

    verify = sub.add_parser("verify", help="check a proof JSON for self-consistency")
    verify.add_argument("proof_path", help="path to a proof JSON file")

    args = parser.parse_args(argv)

    if args.cmd == "demo":
        return _run_demo(args)
    if args.cmd == "verify":
        return _run_verify(args)
    parser.error(f"unknown command: {args.cmd}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
