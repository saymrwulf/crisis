"""
live_agent.py — Real Claude sub-agent driven by the Anthropic API.

LiveClaudeAgent makes a single Anthropic API call per `next_turn()` invocation,
asking Claude to fact-check the scenario's statements against the reference
document. The response is expected to be a JSON array of Claim-shaped objects;
we parse and validate.

For the demo's byzantine slot we deliberately keep `MockByzantineAgent` even
in --live mode: the byzantine's behavior must be *reliably* equivocating to
make the demo legibly show the alarm. Asking an LLM to produce deterministic
equivocation requires multiple API calls per turn (one per peer subset) and
isn't worth the complexity for a PoC. The narrative is still honest: real
Claude agents adjudicate fact-checks; a misbehaving (mocked) peer joins;
Crisis catches the equivocation.

Dependency: `anthropic` SDK. Install via `pip install -e ".[live]"`.
"""

from __future__ import annotations

import json
import os
import textwrap
from typing import Optional

from crisis_agents.agent import AgentTurn, CrisisAgent
from crisis_agents.claim import Claim


# Default model — Haiku 4.5 is fast and cheap enough for this kind of
# structured-output adjudication. Override via --model.
DEFAULT_MODEL = "claude-haiku-4-5-20251001"


class LiveClaudeAgent(CrisisAgent):
    """A CrisisAgent backed by a real Claude API invocation per turn.

    On each `next_turn()`:
      1. Render a structured prompt with the reference doc, the statements
         to adjudicate, and the peer claims observed so far.
      2. Call the Anthropic Messages API.
      3. Parse the response as a JSON array of Claim objects.
      4. Wrap into AgentTurns and return.

    Errors during parsing fall back to emitting nothing for that turn — the
    agent stays alive but contributes nothing this round, which is more
    forgiving than crashing the whole demo.
    """

    def __init__(self,
                 name: str,
                 *,
                 reference_doc: str,
                 statements: list[dict],
                 model: str = DEFAULT_MODEL,
                 client=None,
                 system_prompt: Optional[str] = None):
        """
        Args:
            name:           Stable agent name (drives the Crisis process_id).
            reference_doc:  Full reference document text passed in every prompt.
            statements:     [{"id": "s01", "text": "..."}] — what to adjudicate.
            model:          Anthropic model id. Default: claude-haiku-4-5.
            client:         Optional pre-built `anthropic.Anthropic()`. If None,
                            constructed lazily on first use (requires ANTHROPIC_API_KEY).
            system_prompt:  Optional override. If None, the default honest
                            fact-checking system prompt is used.
        """
        super().__init__(name)
        self._reference_doc = reference_doc
        self._statements = statements
        self._model = model
        self._client = client
        self._system_prompt = system_prompt or self._default_system_prompt()
        self._invocations = 0
        self._already_adjudicated: set[str] = set()

    @staticmethod
    def _default_system_prompt() -> str:
        return textwrap.dedent("""
            You are one of several AI agents on a fact-checking team. You read a
            reference document and adjudicate factual statements about it. You
            answer honestly based on the reference doc alone — you do not invoke
            outside knowledge.

            For every statement you have not yet adjudicated this run, you output
            one JSON object with this exact schema:
              {
                "statement_id": "...",   # the id of the statement
                "verdict": "true" | "false" | "unknown",
                "confidence": 0.0..1.0,
                "evidence": "short justification grounded in the reference doc"
              }

            You output a JSON array of these objects, nothing else — no prose
            around it, no markdown fences, no preamble. Evidence must be at most
            280 characters.
        """).strip()

    def _get_client(self):
        """Lazy-import anthropic so the SDK isn't a hard dependency."""
        if self._client is not None:
            return self._client
        try:
            import anthropic  # type: ignore[import-not-found]
        except ImportError as e:
            raise RuntimeError(
                "live mode requires the anthropic SDK: pip install -e \".[live]\""
            ) from e
        if not os.environ.get("ANTHROPIC_API_KEY"):
            raise RuntimeError(
                "live mode requires ANTHROPIC_API_KEY in the environment"
            )
        self._client = anthropic.Anthropic()
        return self._client

    def next_turn(self, turn: int, received_claims: list[Claim]) -> list[AgentTurn]:
        """Issue one API call, parse, return Claims as AgentTurns."""
        self._invocations += 1

        # Which statements still need a verdict from me?
        pending = [s for s in self._statements
                   if s["id"] not in self._already_adjudicated]
        if not pending:
            return []

        user_message = self._render_user_message(pending, received_claims)

        client = self._get_client()
        response = client.messages.create(
            model=self._model,
            max_tokens=2048,
            system=self._system_prompt,
            messages=[{"role": "user", "content": user_message}],
        )

        text = "".join(
            block.text for block in response.content
            if getattr(block, "type", None) == "text"
        )
        claims = self._parse_response(text)

        out: list[AgentTurn] = []
        for c in claims:
            self._already_adjudicated.add(c.statement_id)
            out.append(AgentTurn(claim=c))
        return out

    def _render_user_message(self, pending_statements: list[dict],
                              received_claims: list[Claim]) -> str:
        statements_block = "\n".join(
            f"  {s['id']}: {s['text']}" for s in pending_statements
        )
        if received_claims:
            peer_block = "\n".join(
                f"  - {c.statement_id}: peer claims {c.verdict!r} (conf {c.confidence:.2f}) — {c.evidence}"
                for c in received_claims[-12:]
            )
        else:
            peer_block = "  (no peer claims yet — you're going first)"

        return textwrap.dedent(f"""\
            === REFERENCE DOCUMENT ===
            {self._reference_doc}

            === STATEMENTS TO ADJUDICATE ===
            {statements_block}

            === CLAIMS FROM PEERS SO FAR ===
            {peer_block}

            Output your verdicts now as a JSON array.
        """)

    def _parse_response(self, text: str) -> list[Claim]:
        """Tolerantly extract the JSON array from the response."""
        text = text.strip()

        # Strip markdown fences if Claude added them despite instructions
        if text.startswith("```"):
            lines = text.splitlines()
            if lines[0].startswith("```"):
                lines = lines[1:]
            if lines and lines[-1].startswith("```"):
                lines = lines[:-1]
            text = "\n".join(lines).strip()

        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            return []

        if not isinstance(data, list):
            return []

        claims: list[Claim] = []
        for item in data:
            if not isinstance(item, dict):
                continue
            try:
                claims.append(Claim(
                    statement_id=str(item.get("statement_id", "")),
                    verdict=item.get("verdict", "unknown"),
                    confidence=float(item.get("confidence", 0.5)),
                    evidence=str(item.get("evidence", ""))[:Claim.EVIDENCE_MAX_LEN],
                    timestamp_logical=self._invocations - 1,
                ))
            except (ValueError, TypeError):
                continue
        return claims
