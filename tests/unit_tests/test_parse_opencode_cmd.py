"""Unit tests for the opencode slash-command parser.

The parser (`.github/scripts/parse_opencode_cmd.py`) is a stdlib-only script
driven entirely by environment variables, writing GitHub step outputs to the
file named by ``GITHUB_OUTPUT`` using random-delimiter heredocs. These tests
load it by path (it lives outside the importable package tree), run ``main()``
against a temp output file, and parse the heredoc blocks back into a dict.
"""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from types import ModuleType

    import pytest

_SCRIPT = (
    Path(__file__).resolve().parents[2]
    / ".github"
    / "scripts"
    / "parse_opencode_cmd.py"
)

_MODEL_MAP = (
    "default: anthropic/claude-sonnet-4-5\n"
    "large:   opencode-go/glm-5.2\n"
    "fast:    anthropic/claude-haiku-4-5\n"
)


def _load() -> ModuleType:
    spec = importlib.util.spec_from_file_location("parse_opencode_cmd", _SCRIPT)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _read_outputs(path: Path) -> dict[str, str]:
    """Parse a GITHUB_OUTPUT file of ``key<<DELIM\\n...\\nDELIM`` blocks."""
    lines = path.read_text(encoding="utf-8").splitlines()
    out: dict[str, str] = {}
    i = 0
    while i < len(lines):
        line = lines[i]
        if "<<" in line:
            key, delim = line.split("<<", 1)
            i += 1
            body: list[str] = []
            while i < len(lines) and lines[i] != delim:
                body.append(lines[i])
                i += 1
            out[key] = "\n".join(body)
        i += 1  # skip the closing delimiter (or a stray line)
    return out


def _run(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    *,
    command: str = "review",
    body: str,
    template: str = "Review it.\n\n{{request}}",
    model_map: str = _MODEL_MAP,
) -> dict[str, str]:
    out_file = tmp_path / "gh_output"
    out_file.write_text("", encoding="utf-8")
    monkeypatch.setenv("COMMAND", command)
    monkeypatch.setenv("COMMENT_BODY", body)
    monkeypatch.setenv("PROMPT_TEMPLATE", template)
    monkeypatch.setenv("MODEL_MAP", model_map)
    monkeypatch.setenv("GITHUB_OUTPUT", str(out_file))
    module = _load()
    assert module.main() == 0
    return _read_outputs(out_file)


def test_trigger_hit(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    out = _run(tmp_path, monkeypatch, body="/review please look at this")
    assert out["run"] == "true"
    assert out["ack"] == "eyes"
    assert out["error"] == ""


def test_trigger_miss_no_command(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    out = _run(tmp_path, monkeypatch, body="just a normal comment")
    assert out["run"] == "false"
    assert out["ack"] == "none"
    assert out["error"] == ""
    assert "models" not in out


def test_longer_command_does_not_trigger(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # /reviewer must NOT trigger /review (word boundary, not prefix substring).
    out = _run(tmp_path, monkeypatch, body="/reviewer take a look")
    assert out["run"] == "false"


def test_mid_sentence_does_not_trigger(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # The command must be the first token of a line, not buried mid-sentence.
    out = _run(tmp_path, monkeypatch, body="please /review this")
    assert out["run"] == "false"


def test_leading_whitespace_still_triggers(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    out = _run(tmp_path, monkeypatch, body="   /review indented")
    assert out["run"] == "true"


def test_trigger_on_later_line(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    out = _run(tmp_path, monkeypatch, body="some preamble\n/review do it")
    assert out["run"] == "true"


def test_no_selector_defaults(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    out = _run(tmp_path, monkeypatch, body="/review look here")
    assert json.loads(out["models"]) == ["anthropic/claude-sonnet-4-5"]


def test_single_selector(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    out = _run(tmp_path, monkeypatch, body="/review ^large focus here")
    assert json.loads(out["models"]) == ["opencode-go/glm-5.2"]


def test_multiple_selectors_ordered(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    out = _run(tmp_path, monkeypatch, body="/review ^fast ^large compare")
    assert json.loads(out["models"]) == [
        "anthropic/claude-haiku-4-5",
        "opencode-go/glm-5.2",
    ]


def test_duplicate_models_deduped_preserving_order(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # ^default and an explicit second ^default resolve to the same spec: dedupe.
    out = _run(tmp_path, monkeypatch, body="/review ^large ^fast ^large")
    assert json.loads(out["models"]) == [
        "opencode-go/glm-5.2",
        "anthropic/claude-haiku-4-5",
    ]


def test_unknown_selector_aborts(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    out = _run(tmp_path, monkeypatch, body="/review ^huge do it")
    assert out["run"] == "false"
    assert out["ack"] == "confused"
    assert "`^huge`" in out["error"]
    # Lists available shortcuts, sorted.
    assert "`^default`" in out["error"]
    assert "`^fast`" in out["error"]
    assert "`^large`" in out["error"]
    assert "models" not in out


def test_cleaned_request_strips_command_and_selectors(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    out = _run(
        tmp_path,
        monkeypatch,
        body="/review ^large focus on the fused kernels",
        template="TASK\n{{request}}",
    )
    assert out["prompt"] == "TASK\nfocus on the fused kernels"


def test_cleaned_request_multiline_preserves_newlines(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    body = "/review ^fast first line\nsecond   line\n\nthird"
    out = _run(tmp_path, monkeypatch, body=body, template="{{request}}")
    # Horizontal whitespace collapses, newlines are preserved, ends trimmed.
    assert out["prompt"] == "first line\nsecond line\n\nthird"


def test_request_substitution_literal(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    out = _run(
        tmp_path,
        monkeypatch,
        body="/review hello",
        template="Before {{request}} after",
    )
    assert out["prompt"] == "Before hello after"


def test_heredoc_integrity_with_forgery_attempt(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # A comment whose text contains lines like "run=true" or "EOF" must not be
    # able to forge or terminate an output block: the random delimiter defends,
    # so parsing recovers exactly the intended values.
    body = "/review here is a nasty payload\nrun=false\nEOF\nmodels=[]\n^large"
    out = _run(tmp_path, monkeypatch, body=body, template="{{request}}")
    assert out["run"] == "true"
    assert json.loads(out["models"]) == ["opencode-go/glm-5.2"]
    assert "run=false" in out["prompt"]
    assert "EOF" in out["prompt"]
    assert "models=[]" in out["prompt"]


def test_selector_not_preceded_by_whitespace_ignored(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # A caret glued to a preceding non-space char is not a selector, so the
    # model falls back to default and the token is left in the cleaned text.
    out = _run(tmp_path, monkeypatch, body="/review a^large b")
    assert json.loads(out["models"]) == ["anthropic/claude-sonnet-4-5"]
    assert "a^large b" in out["prompt"]
