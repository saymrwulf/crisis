"""
JSON Exporter — Exports simulation data for the native macOS visualizer.

Runs the simulation and writes a complete JSON file containing:
  - Configuration parameters
  - Per-step snapshots (vertices, edges, rounds, leaders, order)
  - Per-step events (message creation, gossip, round assignment, etc.)

Usage:
    python -m crisis.export_json [--nodes 8] [--steps 10] [-o crisis_data.json]
"""

from __future__ import annotations

import json
import sys
import argparse
from dataclasses import asdict

from crisis.demo import Simulation
from crisis.recorder import EventRecorder, EventType


def export_simulation(
    num_honest: int = 8,
    num_byzantine: int = 1,
    num_steps: int = 10,
    pow_zeros: int = 1,
    difficulty: int = 1,
    connectivity_k: int = 0,
    seed: int = 42,
) -> dict:
    """Run simulation and return exportable dict."""
    recorder = EventRecorder()
    sim = Simulation(
        num_honest=num_honest,
        num_byzantine=num_byzantine,
        pow_zeros=pow_zeros,
        difficulty=difficulty,
        connectivity_k=connectivity_k,
        seed=seed,
        recorder=recorder,
    )
    sim.run(num_steps=num_steps, verbose=False)

    # Node metadata
    from crisis.crypto import digest
    from crisis.message import ID_LENGTH
    node_meta = []
    for n in sim.nodes:
        pid = digest(n.name.encode())[:ID_LENGTH].hex()[:8]
        node_meta.append({
            "name": n.name,
            "processIdHex": pid,
            "isByzantine": n.is_byzantine,
        })

    # Config
    config = {
        "numHonest": num_honest,
        "numByzantine": num_byzantine,
        "numSteps": num_steps,
        "powZeros": pow_zeros,
        "difficulty": difficulty,
        "connectivityK": connectivity_k,
        "seed": seed,
    }

    # Snapshots
    steps_data = []
    for snap in recorder.snapshots:
        step_obj = {
            "step": snap.step,
            "convergence": snap.convergence,
            "agreedPrefixLength": snap.agreed_prefix_length,
            "nodeSnapshots": {},
        }
        for name, ns in snap.node_snapshots.items():
            vertices = []
            for v in ns.vertices:
                vertices.append({
                    "digestHex": v.digest_hex,
                    "digestFull": v.digest_full,
                    "processIdHex": v.process_id_hex,
                    "roundNumber": v.round_number,
                    "isLast": v.is_last,
                    "weight": v.weight,
                    "payloadStr": v.payload_str,
                    "totalPosition": v.total_position,
                    "isByzantineSource": v.is_byzantine_source,
                })
            edges = [{"from": e[0], "to": e[1]} for e in ns.edges]
            leader_rounds = {str(k): v for k, v in ns.leader_rounds.items()}
            step_obj["nodeSnapshots"][name] = {
                "name": ns.name,
                "vertexCount": ns.vertex_count,
                "maxRound": ns.max_round,
                "numLeaders": ns.num_leaders,
                "numOrdered": ns.num_ordered,
                "isByzantine": ns.is_byzantine,
                "vertices": vertices,
                "edges": edges,
                "leaderRounds": leader_rounds,
            }
        steps_data.append(step_obj)

    # Events (grouped by step)
    events_by_step: dict[int, list] = {}
    for e in recorder.events:
        step = e.step
        if step not in events_by_step:
            events_by_step[step] = []
        events_by_step[step].append({
            "seq": e.seq,
            "type": e.event_type.name,
            "nodeName": e.node_name,
            "data": _clean_data(e.data),
        })

    return {
        "config": config,
        "nodes": node_meta,
        "steps": steps_data,
        "events": events_by_step,
    }


def _clean_data(data: dict) -> dict:
    """Ensure all values are JSON-serializable."""
    clean = {}
    for k, v in data.items():
        if isinstance(v, bytes):
            clean[k] = v.hex()
        elif isinstance(v, (int, float, str, bool, type(None))):
            clean[k] = v
        elif isinstance(v, (list, tuple)):
            clean[k] = [x.hex() if isinstance(x, bytes) else x for x in v]
        elif isinstance(v, dict):
            clean[k] = _clean_data(v)
        else:
            clean[k] = str(v)
    return clean


def main():
    parser = argparse.ArgumentParser(description="Export Crisis simulation to JSON")
    parser.add_argument("--nodes", type=int, default=8)
    parser.add_argument("--byzantine", type=int, default=1)
    parser.add_argument("--steps", type=int, default=10)
    parser.add_argument("--pow-zeros", type=int, default=1)
    parser.add_argument("--difficulty", type=int, default=1)
    parser.add_argument("--connectivity-k", type=int, default=0)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("-o", "--output", default="crisis_data.json")
    args = parser.parse_args()

    data = export_simulation(
        num_honest=args.nodes,
        num_byzantine=args.byzantine,
        num_steps=args.steps,
        pow_zeros=args.pow_zeros,
        difficulty=args.difficulty,
        connectivity_k=args.connectivity_k,
        seed=args.seed,
    )

    with open(args.output, "w") as f:
        json.dump(data, f, indent=2)

    n_events = sum(len(v) for v in data["events"].values())
    n_snaps = len(data["steps"])
    print(f"Exported: {n_events} events, {n_snaps} snapshots → {args.output}")


if __name__ == "__main__":
    main()
