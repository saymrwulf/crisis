"""
fact_check scenario — the canonical PoC demo.

A team of three honest agents fact-checks six statements against a short
reference document. After the closed phase, a fourth agent (the byzantine)
joins. Crisis is activated. For statement s03 the byzantine equivocates:
it tells one peer set the statement is TRUE and another peer set it is
FALSE. For every other statement it agrees with ground truth (so it can't
be dismissed as a low-vote outlier).

The scenario is fully deterministic in mocked mode — the same seed
produces the same Crisis log every time — which is what makes it a
useful regression fixture.
"""

from __future__ import annotations

from dataclasses import dataclass
from importlib import resources

from crisis_agents.agent import (
    CrisisAgent,
    MockAgent,
    MockByzantineAgent,
)
from crisis_agents.claim import Claim


@dataclass(frozen=True)
class Statement:
    """A single proposition the team must adjudicate."""
    id: str
    text: str
    ground_truth: str  # "true" | "false"


STATEMENTS: tuple[Statement, ...] = (
    Statement("s01", "Water boils at 100°C at standard pressure.", "true"),
    Statement("s02", "The speed of light in vacuum is a defined constant.", "true"),
    Statement("s03", "Pluto is still classified as a planet by the IAU.", "false"),
    Statement("s04", "The Sun is approximately 4.6 billion years old.", "true"),
    Statement("s05", "The Moon's diameter is half of the Earth's diameter.", "false"),
    Statement("s06", "Sound can travel through a vacuum.", "false"),
)


def load_reference_doc() -> str:
    """Return the reference document's full text."""
    return resources.files("crisis_agents.scenarios").joinpath(
        "reference_doc.txt"
    ).read_text(encoding="utf-8")


def _honest_claims(agent_name: str) -> list[list[Claim]]:
    """Build one turn's worth of honest claims — one Claim per statement,
    all matching ground truth, with slightly varied confidence per agent.

    Returns a single-turn script: `[ [claim_s01, claim_s02, ..., claim_s06] ]`.
    """
    # Tiny per-agent confidence offset so claims aren't byte-identical
    # (though identical payloads would also be fine — Crisis dedupes on
    # message digest including the nonce).
    confidence_offset = {
        "agent_alpha": 0.95,
        "agent_beta":  0.90,
        "agent_gamma": 0.92,
    }
    base = confidence_offset.get(agent_name, 0.90)

    turn0: list[Claim] = []
    for st in STATEMENTS:
        turn0.append(Claim(
            statement_id=st.id,
            verdict=st.ground_truth,  # type: ignore[arg-type]
            confidence=base,
            evidence=f"per reference doc — {agent_name}",
            timestamp_logical=0,
        ))
    return [turn0]


def build_honest_agents() -> list[CrisisAgent]:
    """The three trusted agents for the closed-phase team (mocked)."""
    return [
        MockAgent("agent_alpha", _honest_claims("agent_alpha")),
        MockAgent("agent_beta",  _honest_claims("agent_beta")),
        MockAgent("agent_gamma", _honest_claims("agent_gamma")),
    ]


def build_live_honest_agents(model: str | None = None) -> list[CrisisAgent]:
    """The three honest agents in `--live` mode — backed by real Claude API."""
    # Lazy import so the anthropic SDK isn't required for the mocked path.
    from crisis_agents.live_agent import DEFAULT_MODEL, LiveClaudeAgent

    statement_dicts = [{"id": s.id, "text": s.text} for s in STATEMENTS]
    selected_model = model or DEFAULT_MODEL
    ref = load_reference_doc()
    return [
        LiveClaudeAgent("agent_alpha", reference_doc=ref,
                        statements=statement_dicts, model=selected_model),
        LiveClaudeAgent("agent_beta", reference_doc=ref,
                        statements=statement_dicts, model=selected_model),
        LiveClaudeAgent("agent_gamma", reference_doc=ref,
                        statements=statement_dicts, model=selected_model),
    ]


def build_byzantine_joiner() -> CrisisAgent:
    """The fourth agent — joins after the boundary opens.

    For s03 (whose ground truth is FALSE) the byzantine tells α and γ "true"
    but tells β "false". For every other statement it tells everyone the
    ground-truth answer — so vote weight doesn't isolate it as a simple
    outlier.

    Because MockByzantineAgent emits two variants per scripted_pair on the
    same turn, we model "agrees with everyone" by giving both variants the
    same content; only s03 produces a genuine equivocation. To keep
    delivery semantics clean, the byzantine's non-equivocating statements
    use a small dedicated agent name list to remain a single broadcast.

    Simpler approach used here: emit only ONE equivocation slot — the s03
    one — on turn 0, and skip the other statements. The honest majority
    already covers s01-s06 with consistent claims; the byzantine doesn't
    need to vote on every statement for the demo to read as "byzantine
    caught equivocating".
    """
    pair_s03_true = Claim(
        statement_id="s03", verdict="true", confidence=0.85,
        evidence="claims Pluto is still a planet, contradicts ref doc",
        timestamp_logical=0,
    )
    pair_s03_false = Claim(
        statement_id="s03", verdict="false", confidence=0.85,
        evidence="agrees Pluto was reclassified, matches ref doc",
        timestamp_logical=0,
    )
    return MockByzantineAgent(
        name="agent_delta",
        scripted_pairs=[(pair_s03_true, pair_s03_false)],
        split_a={"agent_alpha", "agent_gamma"},
        split_b={"agent_beta"},
    )


@dataclass
class Scenario:
    name: str
    description: str
    closed_phase_turns: int
    crisis_phase_turns: int
    honest_agents: list[CrisisAgent]
    byzantine_joiner: CrisisAgent
    reference_doc: str


def build_fact_check_scenario(*, live: bool = False,
                              model: str | None = None) -> Scenario:
    """Wire together the reference doc, statements, agents, and run lengths.

    In `live` mode, the three honest agents are replaced with LiveClaudeAgent
    instances backed by real Anthropic API calls. The byzantine joiner stays
    mocked even in live mode — see live_agent.py for the rationale.
    """
    if live:
        honest = build_live_honest_agents(model=model)
        suffix = " (live: honest agents are real Claude; byzantine is scripted)"
    else:
        honest = build_honest_agents()
        suffix = " (mocked, deterministic)"

    return Scenario(
        name="fact_check",
        description=(
            "Three honest agents adjudicate six factual statements against "
            "a small reference doc. A fourth agent joins the team after the "
            "boundary opens and equivocates on statement s03 — Crisis "
            "should detect this." + suffix
        ),
        closed_phase_turns=1,
        crisis_phase_turns=1,
        honest_agents=honest,
        byzantine_joiner=build_byzantine_joiner(),
        reference_doc=load_reference_doc(),
    )
