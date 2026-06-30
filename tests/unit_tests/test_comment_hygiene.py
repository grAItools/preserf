"""Guard test: keep review/release-process prose out of code comments.

Comments and docstrings must describe the *code*, not the review or release
process. Labels that name how the work was sliced for review — internal
``Slice``/``Phase`` markers, ``v0.x``-style release-scope notes, "out of scope
for this PR" — go stale the moment the next change lands, because they describe
a process that has already moved on. Scope and rationale belong in the PR
description, an issue, an ADR, or the spec, and are *referenced* from the code.
See ``docs/style.md`` ("Comments") for the policy this test enforces.

The scanner inspects **comments and docstrings only** — never string literals —
so wire-format names (``_preserf_*`` attributes, savepoint group names) and
error messages that legitimately contain these words are never flagged. The
matcher and extractors are importable and unit-tested below, and this file
excludes itself from the repository scan (it necessarily names the very phrases
it bans).
"""

from __future__ import annotations

import ast
import io
import re
import tokenize
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable, Iterator

# tests/unit_tests/<this file> -> repository root is two parents up.
_REPO_ROOT = Path(__file__).resolve().parents[2]
_SELF = Path(__file__).resolve()

# Directories whose committed source is held to the comment policy.
_SCAN_DIRS = ("src/preserf", "tests", "examples")
_FORTRAN_SUFFIXES = frozenset({".f90", ".F90", ".f", ".F", ".inc", ".INC"})
# Fortran template fixtures (compiled at build time) carry a `.f90.in` /
# `.F90.in` double extension, so `Path.suffix` is `.in`; match them by name.
_FORTRAN_TEMPLATE_SUFFIXES = (".f90.in", ".F90.in")

# High-precision patterns. Each names review/release-process scoping that
# describes the development process rather than the code. Kept deliberately
# narrow: judgment calls prone to false positives (bare "currently",
# "temporary", "placeholder", "stub") are left to human/agent review, not this
# gate. Matching is case-insensitive.
_BANNED = tuple(
    re.compile(pattern, re.IGNORECASE)
    for pattern in (
        r"\bslice [a-e]\b",
        r"\bphase \d+\b",
        r"\bv[01]\.\d+\b",  # project release-scope notes: v0.x / v1.x
        r"\bout of scope for\b",  # PR/release sense; not "variable goes out of scope"
        r"(?:in|for) this (?:pr|changeset|commit)\b",
        r"\bfor now\b",
        r"\bfor the moment\b",
        r"\bas of now\b",
        r"\bfirst cut\b",
        r"\binitial (?:version|cut|implementation)\b",
        r"\bmvp\b",
        r"\bminimum viable\b",
        r"\bwip\b",
        r"\bwork in progress\b",
        r"(?:follow[- ]?up|future|later|next) pr\b",
        r"\b(?:will|to) be added\b",
        r"\bnot yet (?:implemented|supported|wired)\b",
    )
)


def match_banned(text: str) -> str | None:
    """Return the first banned process-prose phrase in *text*, or ``None``."""
    for pattern in _BANNED:
        found = pattern.search(text)
        if found:
            return found.group(0)
    return None


def python_prose(source: str) -> Iterator[tuple[int, str]]:
    """Yield ``(lineno, text)`` for every comment and docstring in *source*.

    String literals other than docstrings are excluded, so a banned phrase used
    as data (an error message, a savepoint name) is never reported.
    """
    try:
        tokens = tokenize.generate_tokens(io.StringIO(source).readline)
        for token in tokens:
            if token.type == tokenize.COMMENT:
                yield token.start[0], token.string
    except (tokenize.TokenError, IndentationError, SyntaxError):
        pass  # extraction is best-effort; a malformed file just yields nothing

    try:
        tree = ast.parse(source)
    except SyntaxError:
        return
    doc_owners = (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)
    for node in ast.walk(tree):
        if not isinstance(node, doc_owners):
            continue
        body = getattr(node, "body", None)
        if not body:
            continue
        first = body[0]
        if (
            isinstance(first, ast.Expr)
            and isinstance(first.value, ast.Constant)
            and isinstance(first.value.value, str)
        ):
            yield first.value.lineno, first.value.value


def _fortran_comment(line: str) -> str:
    """Return the ``!`` comment portion of a Fortran *line*, or ``""``.

    Tracks quote state so a ``!`` inside a string literal is not mistaken for
    the start of a comment.
    """
    in_single = in_double = False
    for index, char in enumerate(line):
        if char == "'" and not in_double:
            in_single = not in_single
        elif char == '"' and not in_single:
            in_double = not in_double
        elif char == "!" and not in_single and not in_double:
            return line[index:]
    return ""


def fortran_prose(source: str) -> Iterator[tuple[int, str]]:
    """Yield ``(lineno, text)`` for every ``!`` comment in Fortran *source*."""
    for lineno, line in enumerate(source.splitlines(), start=1):
        comment = _fortran_comment(line)
        if comment:
            yield lineno, comment


def prose_extractor(path: Path) -> Callable[[str], Iterator[tuple[int, str]]] | None:
    """Return the prose extractor for *path*, or ``None`` for a non-source file.

    Fortran template fixtures (``*.f90.in``) keep their Fortran comment syntax,
    so they route to ``fortran_prose`` despite the ``.in`` suffix.
    """
    if path.suffix == ".py":
        return python_prose
    is_fortran = path.suffix in _FORTRAN_SUFFIXES or path.name.endswith(
        _FORTRAN_TEMPLATE_SUFFIXES
    )
    if is_fortran:
        return fortran_prose
    return None  # skip non-source files (bytecode, golden fixtures, …)


def _iter_prose_files() -> Iterator[tuple[Path, int, str]]:
    for directory in _SCAN_DIRS:
        base = _REPO_ROOT / directory
        if not base.exists():
            continue
        for path in sorted(base.rglob("*")):
            if not path.is_file() or path.resolve() == _SELF:
                continue
            extract = prose_extractor(path)
            if extract is None:
                continue
            for lineno, text in extract(path.read_text(encoding="utf-8")):
                yield path, lineno, text


def find_process_prose() -> list[str]:
    """Return ``path:line — phrase: comment`` strings for every violation."""
    violations: list[str] = []
    for path, lineno, text in _iter_prose_files():
        phrase = match_banned(text)
        if phrase is not None:
            rel = path.relative_to(_REPO_ROOT)
            violations.append(f"{rel}:{lineno} — {phrase!r}: {text.strip()}")
    return violations


def test_no_process_prose_in_comments() -> None:
    violations = find_process_prose()
    assert not violations, (
        "Review/release-process prose found in comments or docstrings; describe "
        "the code, not the PR — move scope notes to an issue/ADR/spec. See "
        "docs/style.md (Comments).\n" + "\n".join(violations)
    )


def test_matcher_flags_process_prose() -> None:
    assert match_banned("# out of scope for this PR") is not None
    assert match_banned("! Tracers (Slice C / ADR 0003)") is not None
    assert match_banned("# the v0.1 behaviour, kept as the default") is not None
    assert match_banned("! resume support is deferred to a follow-up PR") is not None


def test_matcher_ignores_clean_comments() -> None:
    assert match_banned("# resolve the savepoint index from the registry") is None
    assert match_banned("! Tracer data is real(real64)") is None
    assert match_banned("# mirror /_fields (ADR 0003 §4a)") is None
    # "out of scope" in the variable-lifetime sense must not be flagged.
    assert match_banned("! or letting it go out of scope / be reallocated") is None


def test_string_literals_are_not_scanned() -> None:
    # A banned phrase as data (e.g. an error message) must not be reported,
    # because only comments and docstrings are inspected.
    as_data = 'raise DirectiveError("feature not yet implemented")\n'
    assert all(match_banned(text) is None for _, text in python_prose(as_data))
    # The same phrase in a comment *is* reported.
    as_comment = "# feature not yet implemented\n"
    assert any(match_banned(text) for _, text in python_prose(as_comment))


def test_fortran_bang_inside_string_is_not_a_comment() -> None:
    assert _fortran_comment("write(*, *) 'no comment! here'") == ""
    assert _fortran_comment("x = 1  ! real comment").strip() == "! real comment"


def test_prose_extractor_routes_by_kind() -> None:
    assert prose_extractor(Path("a.py")) is python_prose
    assert prose_extractor(Path("m.f90")) is fortran_prose
    assert prose_extractor(Path("m.F90")) is fortran_prose
    # Fortran template fixtures keep Fortran comment syntax despite `.in`.
    assert prose_extractor(Path("fixture.f90.in")) is fortran_prose
    # Non-Fortran templates (e.g. CMake config) are not source we scan.
    assert prose_extractor(Path("pkgConfig.cmake.in")) is None
    assert prose_extractor(Path("data.nc")) is None
