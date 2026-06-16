# 6. Code comments describe the code, not the review process

## Status

Accepted

## Context

The codebase accumulated review- and release-process prose in code comments
and docstrings: internal `Slice X` / `Phase N` slice labels (the units the
work was cut into for review), `v0.x` release-scope notes ("the v0.1
behaviour"), and "out of scope for the minimal v0.1 helper". A sweep found 41
such occurrences across the Fortran helper and the test suite.

These describe the _development process_, not the code. The process moves on —
the next change ships, the slice is merged, the version bumps — but the comment
stays, so it is stale the moment it lands. Worse, a reader cannot tell which
comments describe the code's behaviour (and must be trusted) and which are
leftover review notes (and must be ignored). The scope or rationale a process
comment gestures at almost always has a durable home already — an issue, an
ADR, the spec — that the comment fails to reference.

`docs/style.md` had no comment guidance, and no linter or test inspected
comment _content_, so this prose passed review unchallenged. The open question:
is documenting the policy enough, or does it need an automated gate? Guidance
alone had already failed (the prose was merged under the existing review
process), so prevention has to be deterministic.

## Decision

**Comments and docstrings describe the code. Review/release-process notes do
not belong in source** — they go in the PR description, an issue, an ADR, or
the spec, and are _referenced_ from the code (e.g. `(ADR 0003 §4a)` instead of
`(Slice C / ADR 0003 §4a)`).

This is enforced in the existing `pixi run verify` gate (run by the Stop hook
and CI), so it cannot be merged around:

- **ruff `ERA`** bans commented-out code; **ruff `FIX`** bans leftover
  `TODO`/`FIXME`/`XXX`/`HACK` markers (`pyproject.toml`). Both had zero existing
  violations.
- **A pytest guard**, `tests/unit_tests/test_comment_hygiene.py`, fails on
  review/release-process phrasing in comments and docstrings — `Slice X` /
  `Phase N`, `v0.x` / `v1.x` release-scope, `out of scope for`, `for now`,
  `WIP`, "follow-up PR", and similar. It inspects **comments and docstrings
  only, never string literals**, so wire-format names (`_preserf_*` attributes,
  savepoint groups) and error messages that legitimately contain these words
  are untouched. The pattern list is deliberately high-precision: judgment
  calls prone to false positives (bare "temporary", "currently", "placeholder")
  are left to review, not the gate.

The prose policy is documented in `docs/style.md` ("Comments"), restated in an
auto-loaded path-scoped rule (`.claude/rules/comments.md`) so a coding agent
sees it exactly when editing source, and folded into the `reviewer` and
`developer` subagent instructions.

## Consequences

- **Positive.** Process prose cannot be merged again; comments stay about the
  code, and scope/rationale lives where it can be maintained and linked. The
  same gate also keeps out commented-out code and TODO markers.
- **Negative.** The guard is a curated phrase list, so a legitimate future use
  of a banned phrase in a comment needs a reword or a tightened pattern — a
  small, intentional maintenance cost (e.g. `out of scope` was narrowed to
  `out of scope for` so it would not flag a variable that "goes out of scope").
  Process prose smuggled into a string literal would slip past the gate; that
  is acceptable, since the literal is data and the human/agent reviewer covers
  the judgment cases the regex deliberately omits.
- **Revisiting.** Extend the pattern list or the rule as new process-prose
  patterns appear; supersede this ADR if the enforcement mechanism changes.
