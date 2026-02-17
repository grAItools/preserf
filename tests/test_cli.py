"""Tests for the preserf CLI."""

import preserf
from preserf.cli import main, parse_args


def test_version_string() -> None:
    assert preserf.__version__ == "0.1.0"


def test_parse_args_defaults() -> None:
    args = parse_args([])
    assert args is not None


def test_main_returns_zero() -> None:
    assert main([]) == 0
