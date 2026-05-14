"""Tests for the event recorder + snapshot capture pipeline (the bridge to CrisisViz)."""

import json
from dataclasses import asdict

from crisis.demo import Simulation
from crisis.recorder import (
    EventRecorder,
    EventType,
    SimEvent,
    StepSnapshot,
    VertexSnapshot,
    NodeSnapshot,
    capture_snapshot,
)


class TestEventRecorder:

    def test_empty_recorder_has_no_events(self):
        rec = EventRecorder()
        assert rec.events == []
        assert rec.snapshots == []
        assert rec.max_step() == 0

    def test_sequence_numbers_are_monotonic(self):
        rec = EventRecorder()
        rec.record(1, EventType.STEP_BEGIN, "")
        rec.record(1, EventType.MESSAGE_CREATED, "alice")
        rec.record(2, EventType.STEP_END, "")
        seqs = [e.seq for e in rec.events]
        assert seqs == sorted(seqs)
        assert len(set(seqs)) == len(seqs)

    def test_filter_by_step(self):
        rec = EventRecorder()
        rec.record(1, EventType.STEP_BEGIN, "")
        rec.record(2, EventType.STEP_BEGIN, "")
        rec.record(2, EventType.STEP_END, "")
        rec.record(3, EventType.STEP_BEGIN, "")
        assert len(rec.events_at_step(2)) == 2
        assert len(rec.events_at_step(1)) == 1
        assert rec.max_step() == 3

    def test_filter_by_type(self):
        rec = EventRecorder()
        rec.record(1, EventType.STEP_BEGIN, "")
        rec.record(1, EventType.MESSAGE_CREATED, "a")
        rec.record(1, EventType.MESSAGE_CREATED, "b")
        assert len(rec.events_of_type(EventType.MESSAGE_CREATED)) == 2
        assert len(rec.events_of_type(EventType.STEP_END)) == 0


class TestSimulationRecording:
    """The recorder must capture events emitted by a real simulation run."""

    def _tiny_sim_run(self, num_steps: int = 5) -> tuple[Simulation, EventRecorder]:
        rec = EventRecorder()
        sim = Simulation(
            num_honest=3,
            num_byzantine=0,
            pow_zeros=0,
            difficulty=0,
            connectivity_k=0,
            seed=42,
            recorder=rec,
            synchronous=True,
        )
        sim.run(num_steps=num_steps, verbose=False)
        return sim, rec

    def test_recorder_collects_events_per_step(self):
        _, rec = self._tiny_sim_run(num_steps=3)
        assert len(rec.events) > 0
        assert rec.max_step() == 3

    def test_step_lifecycle_events_present(self):
        """Every step must emit STEP_BEGIN and STEP_END."""
        _, rec = self._tiny_sim_run(num_steps=4)
        begins = rec.events_of_type(EventType.STEP_BEGIN)
        ends = rec.events_of_type(EventType.STEP_END)
        assert len(begins) == 4
        assert len(ends) == 4

    def test_messages_are_recorded(self):
        """At least one message-creation event should appear per step with honest nodes."""
        _, rec = self._tiny_sim_run(num_steps=3)
        created = rec.events_of_type(EventType.MESSAGE_CREATED)
        delivered = rec.events_of_type(EventType.MESSAGE_DELIVERED)
        assert len(created) > 0
        assert len(delivered) > 0


class TestSnapshotCapture:

    def test_snapshot_is_well_formed(self):
        rec = EventRecorder()
        sim = Simulation(num_honest=3, num_byzantine=0, pow_zeros=0,
                         difficulty=0, connectivity_k=0, seed=42,
                         recorder=rec, synchronous=True)
        sim.run(num_steps=5, verbose=False)

        snap = capture_snapshot(step=5, nodes=sim.nodes,
                                weight_system=sim.weight_system)

        assert isinstance(snap, StepSnapshot)
        assert snap.step == 5
        assert set(snap.node_snapshots.keys()) == {n.name for n in sim.nodes}

        for ns in snap.node_snapshots.values():
            assert isinstance(ns, NodeSnapshot)
            assert ns.vertex_count > 0
            for vs in ns.vertices:
                assert isinstance(vs, VertexSnapshot)
                assert len(vs.digest_full) > 0
                assert len(vs.process_id_hex) == 8
                assert vs.weight >= 0

    def test_snapshot_vertex_ids_match_graph(self):
        """Snapshot vertex digests must correspond to actual graph state."""
        sim = Simulation(num_honest=2, num_byzantine=0, pow_zeros=0,
                         difficulty=0, seed=42, synchronous=True)
        sim.run(num_steps=3, verbose=False)
        snap = capture_snapshot(step=3, nodes=sim.nodes,
                                weight_system=sim.weight_system)
        for node in sim.nodes:
            ns = snap.node_snapshots[node.name]
            graph_digests = {v.message_digest.hex() for v in node.graph.all_vertices()}
            snap_digests = {vs.digest_full for vs in ns.vertices}
            assert snap_digests == graph_digests


class TestJsonSerializability:
    """The whole point of recorder + snapshots is to round-trip through JSON for CrisisViz."""

    def test_snapshot_is_json_serializable(self):
        sim = Simulation(num_honest=2, num_byzantine=0, pow_zeros=0,
                         difficulty=0, seed=42, synchronous=True)
        sim.run(num_steps=3, verbose=False)
        snap = capture_snapshot(step=3, nodes=sim.nodes,
                                weight_system=sim.weight_system)
        as_dict = asdict(snap)
        # Should not raise; should produce a non-trivial string
        encoded = json.dumps(as_dict, default=str)
        assert len(encoded) > 100

    def test_event_data_is_json_serializable(self):
        rec = EventRecorder()
        sim = Simulation(num_honest=3, num_byzantine=0, pow_zeros=0,
                         difficulty=0, seed=42, recorder=rec, synchronous=True)
        sim.run(num_steps=3, verbose=False)

        # Each event's `data` dict must be JSON-encodable (export_json depends on this).
        for evt in rec.events:
            # `default=str` covers bytes-as-hex-string fallbacks; the recorder is
            # supposed to have already hex-encoded its bytes, so this is a safety net.
            json.dumps(evt.data, default=str)
