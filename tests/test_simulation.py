"""Integration test: run the full simulation and verify basic properties."""

from crisis.demo import Simulation


class TestSimulation:

    def test_simulation_runs(self):
        """The simulation should complete without errors."""
        sim = Simulation(num_honest=3, num_byzantine=0, seed=42)
        results = sim.run(num_steps=5, verbose=False)
        assert len(results) == 5

    def test_graphs_grow(self):
        """Each step should add messages to the graphs."""
        sim = Simulation(num_honest=2, seed=42)
        sim.run(num_steps=3, verbose=False)
        for node in sim.nodes:
            assert node.graph.vertex_count() > 0

    def test_honest_nodes_same_graph_size(self):
        """All honest nodes should have the same number of vertices
        (since all messages are delivered to all nodes)."""
        sim = Simulation(num_honest=3, seed=42)
        sim.run(num_steps=5, verbose=False)
        sizes = [n.graph.vertex_count() for n in sim.nodes]
        assert all(s == sizes[0] for s in sizes)

    def test_rounds_are_computed(self):
        """After running, vertices should have round numbers."""
        sim = Simulation(num_honest=3, seed=42)
        sim.run(num_steps=5, verbose=False)
        for node in sim.nodes:
            for v in node.graph.all_vertices():
                assert v.round is not None

    def test_with_byzantine_node(self):
        """Simulation should handle byzantine nodes without crashing."""
        sim = Simulation(num_honest=3, num_byzantine=1, seed=42)
        results = sim.run(num_steps=5, verbose=False)
        assert len(results) == 5

    def test_deterministic_with_seed(self):
        """Same seed should produce the same results."""
        sim1 = Simulation(num_honest=3, seed=123)
        r1 = sim1.run(num_steps=3, verbose=False)

        sim2 = Simulation(num_honest=3, seed=123)
        r2 = sim2.run(num_steps=3, verbose=False)

        # Same number of messages at each step
        for s1, s2 in zip(r1, r2):
            assert len(s1["new_messages"]) == len(s2["new_messages"])
            for ns1, ns2 in zip(s1["node_states"], s2["node_states"]):
                assert ns1["vertices"] == ns2["vertices"]
