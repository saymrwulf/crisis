"""
Crisis Agents: a coordination layer for AI agent teams on top of the
Crisis consensus protocol.

The protocol implementation in `crisis` reaches total order on messages
between machines. This package lifts that one level up: it treats each
participating agent as a Crisis node and uses the Lamport graph as an
immutable, replayable ledger of what every agent said and when.

Use case: a team of agents coordinated by a *mothership* (orchestrator)
normally talks freely; when the team's boundary opens to outside agents
of unknown trust, the mothership activates the Crisis layer so that any
byzantine equivocation can be detected (`LamportGraph.find_mutations`)
and a cryptographic proof of malfeasance can be produced.

Key modules:
    - claim:       structured statement an agent makes (a Crisis payload)
    - boundary:    closed-set tracking + open() trigger
    - agent:       CrisisAgent abstract + MockAgent + MockByzantineAgent
    - mothership:  orchestrator that drives Crisis rounds
    - alarm:       wraps mutation detection into AlarmEvent
    - proof:       emits replayable proof-of-malfeasance JSON
    - scenarios:   demo scripts (fact_check)
    - cli:         `crisis-agents` command-line entry point
"""

from crisis_agents.claim import Claim

__all__ = ["Claim"]
__version__ = "0.1.0"
