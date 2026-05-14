"""Tests for LiveClaudeAgent — uses a fake Anthropic client (no real API calls)."""

from dataclasses import dataclass
from typing import Any

import pytest

from crisis_agents.claim import Claim
from crisis_agents.live_agent import LiveClaudeAgent


# ---------------------------------------------------------------------------
# Fakes — we never hit the real Anthropic API in CI.
# ---------------------------------------------------------------------------

@dataclass
class _FakeContentBlock:
    type: str
    text: str


@dataclass
class _FakeResponse:
    content: list[_FakeContentBlock]


class _FakeAnthropicClient:
    """Stand-in for anthropic.Anthropic that returns whatever JSON we hand it."""

    def __init__(self, scripted_responses: list[str]):
        self._responses = list(scripted_responses)
        self.calls: list[dict[str, Any]] = []

        # The real SDK exposes .messages.create; mirror that.
        outer = self

        class _MessagesProxy:
            def create(self_inner, **kwargs):
                outer.calls.append(kwargs)
                text = outer._responses.pop(0) if outer._responses else "[]"
                return _FakeResponse(content=[_FakeContentBlock("text", text)])

        self.messages = _MessagesProxy()


# ---------------------------------------------------------------------------
# The statements + reference doc fixture
# ---------------------------------------------------------------------------

_STATEMENTS = [
    {"id": "s01", "text": "Water boils at 100C at standard pressure."},
    {"id": "s02", "text": "Pluto is still classified as a planet by the IAU."},
]
_REF = "Water boils at 100C. Pluto was reclassified to a dwarf planet in 2006."


class TestLiveClaudeAgent:

    def test_parses_clean_json_response(self):
        response = (
            '[{"statement_id":"s01","verdict":"true","confidence":0.95,"evidence":"per ref"},'
            ' {"statement_id":"s02","verdict":"false","confidence":0.9,"evidence":"per ref"}]'
        )
        client = _FakeAnthropicClient([response])
        agent = LiveClaudeAgent(
            "agent_alpha", reference_doc=_REF,
            statements=_STATEMENTS, client=client,
        )
        turns = agent.try_emit()
        assert len(turns) == 2
        assert {t.claim.statement_id for t in turns} == {"s01", "s02"}
        verdicts = {t.claim.statement_id: t.claim.verdict for t in turns}
        assert verdicts == {"s01": "true", "s02": "false"}

    def test_strips_markdown_fences(self):
        """Claude sometimes wraps JSON in ```json fences despite instructions."""
        response = (
            "```json\n"
            '[{"statement_id":"s01","verdict":"true","confidence":0.9,"evidence":"ok"}]\n'
            "```\n"
        )
        client = _FakeAnthropicClient([response])
        agent = LiveClaudeAgent(
            "agent_alpha", reference_doc=_REF,
            statements=_STATEMENTS, client=client,
        )
        turns = agent.try_emit()
        assert len(turns) == 1
        assert turns[0].claim.statement_id == "s01"

    def test_returns_empty_on_malformed_response(self):
        client = _FakeAnthropicClient(["not json at all"])
        agent = LiveClaudeAgent(
            "agent_alpha", reference_doc=_REF,
            statements=_STATEMENTS, client=client,
        )
        turns = agent.try_emit()
        assert turns == []

    def test_skips_invalid_claim_objects_in_response(self):
        response = (
            '[{"statement_id":"s01","verdict":"true","confidence":0.9,"evidence":"ok"},'
            ' "not a dict",'
            ' {"statement_id":"s02","verdict":"bogus","confidence":0.5,"evidence":"x"}]'
        )
        client = _FakeAnthropicClient([response])
        agent = LiveClaudeAgent(
            "agent_alpha", reference_doc=_REF,
            statements=_STATEMENTS, client=client,
        )
        turns = agent.try_emit()
        # Only the first item passes validation: bogus verdict and non-dict get skipped.
        assert len(turns) == 1
        assert turns[0].claim.statement_id == "s01"

    def test_already_adjudicated_statements_are_skipped(self):
        response_1 = '[{"statement_id":"s01","verdict":"true","confidence":0.9,"evidence":"ok"}]'
        response_2 = '[{"statement_id":"s02","verdict":"false","confidence":0.9,"evidence":"ok"}]'
        client = _FakeAnthropicClient([response_1, response_2])
        agent = LiveClaudeAgent(
            "agent_alpha", reference_doc=_REF,
            statements=_STATEMENTS, client=client,
        )
        # First call adjudicates s01
        first = agent.try_emit()
        assert {t.claim.statement_id for t in first} == {"s01"}

        # Second call should only ask about s02 (s01 is already done)
        second = agent.try_emit()
        assert {t.claim.statement_id for t in second} == {"s02"}

        # The prompt sent for the second call should NOT mention s01
        second_call = client.calls[1]
        user_msg = second_call["messages"][0]["content"]
        assert "s02:" in user_msg
        # s01 was previously adjudicated; it should not appear in the
        # "STATEMENTS TO ADJUDICATE" block of the second prompt.
        statements_section = user_msg.split("=== STATEMENTS TO ADJUDICATE ===")[1]
        next_section_start = statements_section.find("===")
        statements_only = statements_section[:next_section_start]
        assert "s01:" not in statements_only

    def test_evidence_length_is_truncated(self):
        long_evidence = "x" * 500
        response = (
            f'[{{"statement_id":"s01","verdict":"true","confidence":0.9,'
            f'"evidence":"{long_evidence}"}}]'
        )
        client = _FakeAnthropicClient([response])
        agent = LiveClaudeAgent(
            "agent_alpha", reference_doc=_REF,
            statements=_STATEMENTS, client=client,
        )
        turns = agent.try_emit()
        assert len(turns) == 1
        assert len(turns[0].claim.evidence) == Claim.EVIDENCE_MAX_LEN
