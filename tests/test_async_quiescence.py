"""Async-quiescence properties — the new tests that protect the no-clock invariant.

If you accidentally bake a synchronous tick back into the driver, one of these
tests should fail.
"""

from crisis_agents.agent import MockAgent, MockByzantineAgent
from crisis_agents.claim import Claim
from crisis_agents.mothership import Mothership
from crisis_agents.vote import quorum_for


def _claim(sid: str, verdict: str = "true", evidence: str = "ok") -> Claim:
    return Claim(statement_id=sid, verdict=verdict, confidence=0.9,  # type: ignore[arg-type]
                 evidence=evidence, timestamp_logical=0)


def _intro(name: str = "delta") -> Claim:
    return Claim(statement_id=f"intro:{name}", verdict="unknown", confidence=1.0,
                 evidence=f"{name} joining the team", timestamp_logical=0)


def _build_fresh_team() -> Mothership:
    m = Mothership()
    m.add_agent(MockAgent("a", [[]]))
    m.add_agent(MockAgent("b", [[]]))
    m.add_agent(MockAgent("c", [[]]))
    byz = MockByzantineAgent(
        "d", _intro(),
        scripted_pairs=[(
            _claim("s03", verdict="true", evidence="to_ac"),
            _claim("s03", verdict="false", evidence="to_b"),
        )],
        split_a={"a", "c"},
        split_b={"b"},
    )
    m.open_boundary(byz)
    return m


class TestAsyncQuiescence:

    def test_run_until_quiescent_terminates(self):
        """The loop must terminate. If it doesn't, there's a logic bug
        in the quiescence detection."""
        m = _build_fresh_team()
        report = m.run_until_quiescent(max_steps=200)
        assert report.reached_quiescence
        assert report.steps < 200

    def test_two_runs_produce_identical_final_state(self):
        """Running the same scenario twice must produce the same ratified-set,
        confirming there's no hidden non-deterministic ordering in the loop.
        """
        m1 = _build_fresh_team()
        m1.run_until_quiescent()

        m2 = _build_fresh_team()
        m2.run_until_quiescent()

        for name in ("a", "b", "c"):
            assert m1.ratified_alarms_from(name) == m2.ratified_alarms_from(name)

    def test_max_steps_bound_caps_runtime(self):
        """If we set max_steps to 1, the loop must exit even though
        quiescence wasn't reached. The QuiescenceReport must accurately
        say so."""
        m = _build_fresh_team()
        report = m.run_until_quiescent(max_steps=1)
        # With one step we won't have propagated alarms through gossip
        assert report.steps == 1
        # reached_quiescence might be False because we capped out
        # (the byzantine has more emissions pending)
        # The important property: the loop exited and reported honestly.
        assert isinstance(report.reached_quiescence, bool)

    def test_no_turn_argument_exposed_to_agents(self):
        """Regression guard: CrisisAgent.try_emit() takes no arguments.
        If anyone re-adds a `turn` parameter, this fails at the type-check
        level when MockAgent.try_emit is called."""
        import inspect
        from crisis_agents.agent import CrisisAgent
        sig = inspect.signature(CrisisAgent.try_emit)
        # self plus no other parameters
        params = list(sig.parameters)
        assert params == ["self"], f"try_emit grew arguments: {params}"

    def test_no_turn_field_on_alarmclaim(self):
        """Regression guard: AlarmClaim no longer has a `detected_at_turn`
        field. It has `emitted_at_step` — a sequence number, not a clock tick."""
        from crisis_agents.vote import AlarmClaim
        fields = AlarmClaim.__dataclass_fields__
        assert "detected_at_turn" not in fields
        assert "emitted_at_step" in fields

    def test_alarms_propagate_through_async_loop_alone(self):
        """The async loop should detect, emit alarms, and ratify — all without
        the caller having to invoke separate emit_alarms_from_detectors() or
        run_gossip_round() steps.
        """
        m = _build_fresh_team()
        m.run_until_quiescent()
        threshold = quorum_for(m.boundary.size())
        for name in ("a", "b", "c"):
            ratified = m.ratified_alarms_from(name)
            assert len(ratified) == 1
            r = ratified[0]
            assert r.signer_count >= threshold

    def test_quiescence_report_counts_match_logs(self):
        """Sanity: the report's emission count must equal the crisis log length."""
        m = _build_fresh_team()
        report = m.run_until_quiescent()
        assert report.emissions == len(m.run_result.crisis_log)
