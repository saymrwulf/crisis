"""
crisis-agents — command-line entry point.

Subcommands:
    demo    Run a scripted scenario end-to-end. The Crisis phase runs an
            asynchronous event loop to quiescence — no global clock, no
            fixed turn count.
    verify  Re-check a proof JSON for self-consistency.

Examples:
    crisis-agents demo --scenario fact_check
    crisis-agents demo --scenario fact_check --live
    crisis-agents verify proof_<accused>_s03.json
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
    print("--- Phase 1: closed team, no Crisis ---")
    closed_report = mothership.run_closed_phase()
    honest_names = [a.name for a in mothership.agents.values()]
    print(
        f"  driven to quiescence in {closed_report.steps} step(s); "
        f"{closed_report.emissions} claims from "
        f"{len(honest_names)} honest agent(s)."
    )
    print(f"  Per-agent graphs: not yet allocated (Crisis is dormant).\n")

    # ---- Phase 2: boundary opens ----
    print(f"--- Phase 2: boundary opens — {scenario.byzantine_joiner.name} joins ---")
    mothership.open_boundary(scenario.byzantine_joiner)
    print(f"  Trust set is now {mothership.boundary.size()} agents.")
    print(f"  Crisis is now ACTIVE — agents emit asynchronously.\n")

    # ---- Phase 3: async event loop to quiescence ----
    print("--- Phase 3: asynchronous event loop (no clock) ---")
    report = mothership.run_until_quiescent()
    print(
        f"  drove to quiescence in {report.steps} step(s):\n"
        f"    {report.emissions:3d} regular emissions\n"
        f"    {report.gossip_transfers:3d} gossip transfers\n"
        f"    {report.alarm_claims_emitted:3d} alarm claims emitted"
    )
    print(f"  After convergence:")
    for name, agent in mothership.agents.items():
        print(f"    {name:14s} graph: {agent.graph.vertex_count():2d} vertices")
    print()

    # ---- Phase 4: each agent's own detection result ----
    print("--- Phase 4: decentralized detection (each agent's own brain) ---")
    detected_by = []
    for name, agent in mothership.agents.items():
        alarms = agent.detect_mutations()
        marker = "ALARM" if alarms else "ok   "
        suffix = ""
        if alarms:
            detected_by.append(name)
            suffix = (f" — accuses {alarms[0].accused_process_id_hex[:16]}... "
                      f"on {alarms[0].statement_id}")
        print(f"    [{marker}] {name:14s}{suffix}")
    print(f"  {len(detected_by)} of {len(mothership.agents)} agents detected "
          f"byzantine behavior independently.\n")

    # ---- Phase 5: quorum tally ----
    print("--- Phase 5: ratification by quorum ---")
    threshold = quorum_for(mothership.boundary.size())
    print(f"  Quorum threshold = ⌈2*{mothership.boundary.size()}/3⌉ = {threshold}")

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
    marker = "✓" if all_agree else "✗"
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
        description="Crisis-Agents — decentralized async coordination for AI agent teams.",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    demo = sub.add_parser("demo", help="run a scripted scenario end-to-end")
    demo.add_argument("--scenario", default="fact_check",
                      help="which scenario to run (default: fact_check)")
    demo.add_argument("--live", action="store_true",
                      help="back the honest agents with real Claude API calls "
                           "(requires anthropic SDK + ANTHROPIC_API_KEY)")
    demo.add_argument("--model", default=None,
                      help="Anthropic model id for --live")
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
