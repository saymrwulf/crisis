"""
Boundary — the membership set whose closure determines whether Crisis is active.

The mental model: agents inside the boundary are trusted (we vouch for their
intent). Crisis is overhead in this phase. When a new agent joins from outside
— `open(new_id)` — the boundary becomes "open" and from that moment Crisis is
activated for all subsequent claim emission.

Reopening is one-shot in this PoC: once open, the boundary stays open for the
remainder of the run. Re-closing would mean exiling agents and resetting trust
assumptions; that's a separate decision the mothership would make, not a
Boundary primitive.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class Boundary:
    """Membership tracker + Crisis-activation flag.

    Attributes:
        trusted_ids: set of 32-byte process_ids inside the trusted closure.
        is_open:     True once `open()` has been called at least once.
    """
    trusted_ids: set[bytes] = field(default_factory=set)
    is_open: bool = False

    def add_trusted(self, process_id: bytes) -> None:
        """Add an agent that's trusted from the start (closed-phase population)."""
        if self.is_open:
            raise RuntimeError(
                "boundary is already open — use open() to add agents now"
            )
        self.trusted_ids.add(process_id)

    def open(self, new_process_id: bytes) -> None:
        """The trigger: a new agent of unknown trust joins.

        After this call, `is_open` is True and any further agents are added
        via the same method. The new id is added to `trusted_ids` because
        Crisis's mutation detection works for *any* id with vertices in the
        graph — the boundary doesn't gate participation, it gates whether
        we bother running Crisis at all.
        """
        self.trusted_ids.add(new_process_id)
        self.is_open = True

    def is_trusted(self, process_id: bytes) -> bool:
        return process_id in self.trusted_ids

    def size(self) -> int:
        return len(self.trusted_ids)
