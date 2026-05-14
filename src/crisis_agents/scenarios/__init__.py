"""Demo scenarios for the crisis-agents CLI.

A scenario is a self-contained recipe: a reference document, a set of
statements to adjudicate, scripted Claims for each honest agent, and a
byzantine pair designed to trigger one equivocation alarm.
"""

from crisis_agents.scenarios.fact_check import build_fact_check_scenario

__all__ = ["build_fact_check_scenario"]
