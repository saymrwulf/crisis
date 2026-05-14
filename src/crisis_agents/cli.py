"""
crisis-agents — command-line entry point.

Subcommands:
    demo    Run a scripted scenario end-to-end (closed phase → boundary
            opens → Crisis phase → alarm detection → proof emission).
    verify  Re-check a proof JSON for self-consistency. (Phase 6, may be
            a stub for now.)

Examples:
    crisis-agents demo --scenario fact_check
    crisis-agents demo --scenario fact_check --live
    crisis-agents verify proof_agent_delta_s03.json
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from crisis_agents.alarm import scan_for_mutations
from crisis_agents.mothership import Mothership
from crisis_agents.proof import (
    ProofDocument,
    build_proof,
    verify_proof_self_consistent,
)
from crisis_agents.scenarios import build_fact_check_scenario


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
    print(f"Reference document:")
    for line in scenario.reference_doc.splitlines():
        print(f"  {line}")
    print()

    mothership = Mothership()
    for agent in scenario.honest_agents:
        mothership.add_agent(agent)

    # Phase 1: closed
    print(f"--- Phase 1: closed team, no Crisis ({scenario.closed_phase_turns} turn(s)) ---")
    mothership.run_closed_phase(num_turns=scenario.closed_phase_turns)
    print(
        f"  {len(mothership.run_result.closed_log)} claims collected from "
        f"{len(mothership.agents)} honest agent(s) — consensus reached "
        f"without Crisis.\n"
    )

    # Phase 2: boundary opens
    print(f"--- Phase 2: boundary opens — {scenario.byzantine_joiner.name} joins ---")
    print("  Crisis activated for all subsequent claims.\n")
    mothership.open_boundary(scenario.byzantine_joiner)

    # Phase 3: Crisis-active turns
    print(f"--- Phase 3: Crisis-active run ({scenario.crisis_phase_turns} turn(s)) ---")
    mothership.run_crisis_phase(num_turns=scenario.crisis_phase_turns)
    print(
        f"  {len(mothership.run_result.crisis_log)} Crisis messages emitted; "
        f"{len(mothership.agents)} per-agent LamportGraphs maintained.\n"
    )

    # Phase 4: alarm
    print("--- Phase 4: scan for byzantine equivocation ---")
    alarms = scan_for_mutations(mothership)
    if not alarms:
        print("  ✓ No mutations detected — network is honest.\n")
        return 0

    print(f"  ⚠ {len(alarms)} alarm(s) raised:")
    for a in alarms:
        verdicts = ", ".join(
            f"{w.payload_claim['verdict']}->{','.join(w.delivered_to)}"
            for w in a.witnesses
        )
        print(
            f"    - agent {a.accused_agent!r} (id={a.accused_process_id_hex[:16]}...) "
            f"equivocated on {a.statement_id} at turn {a.turn}: {verdicts}"
        )
    print()

    # Phase 5: proof emission
    print("--- Phase 5: emit proof-of-malfeasance ---")
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for a in alarms:
        proof = build_proof(mothership, a)
        path = out_dir / f"proof_{a.accused_agent}_{a.statement_id}.json"
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
    print(f"  accused agent:   {proof.accused_agent}")
    print(f"  statement_id:    {proof.statement_id}")
    print(f"  turn:            {proof.turn}")
    print(f"  spacelike:       {proof.spacelike_verified}")
    print(f"  self-consistent: {result.ok}")
    print(f"  reason:          {result.reason}")
    return 0 if result.ok else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="crisis-agents",
        description="Crisis-Agents — coordination layer for AI agent teams.",
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
