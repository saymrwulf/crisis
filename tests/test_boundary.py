"""Tests for the Boundary membership tracker."""

import pytest

from crisis.crypto import digest
from crisis.message import ID_LENGTH
from crisis_agents.boundary import Boundary


def pid(name: str) -> bytes:
    return digest(name.encode())[:ID_LENGTH]


class TestBoundary:

    def test_initially_closed_and_empty(self):
        b = Boundary()
        assert not b.is_open
        assert b.size() == 0

    def test_add_trusted_in_closed_phase(self):
        b = Boundary()
        b.add_trusted(pid("a"))
        b.add_trusted(pid("b"))
        assert b.size() == 2
        assert b.is_trusted(pid("a"))
        assert b.is_trusted(pid("b"))
        assert not b.is_trusted(pid("c"))

    def test_open_flips_flag_and_adds_id(self):
        b = Boundary()
        b.add_trusted(pid("a"))
        b.open(pid("new"))
        assert b.is_open
        assert b.is_trusted(pid("new"))
        assert b.size() == 2

    def test_add_trusted_after_open_rejected(self):
        b = Boundary()
        b.open(pid("a"))
        with pytest.raises(RuntimeError, match="already open"):
            b.add_trusted(pid("b"))

    def test_open_is_idempotent_on_state(self):
        """Calling open() a second time with a new id just adds the id."""
        b = Boundary()
        b.open(pid("first"))
        b.open(pid("second"))
        assert b.is_open
        assert b.size() == 2
