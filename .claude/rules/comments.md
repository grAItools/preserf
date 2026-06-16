---
paths:
  - "src/**/*.py"
  - "src/**/*.f90"
  - "src/**/*.F90"
  - "tests/**/*.py"
  - "examples/**"
---

# Comment hygiene

Comments and docstrings describe the **code**, not the review/release process.
Full policy: `docs/style.md` ("Comments"); rationale: ADR 0006.

- Explain **why**, not what — invariants, constraints, the spec/ADR that
  motivates the shape. Don't restate the next line.
- Keep comments **accurate**: update or delete them in the same change as the
  code they describe. A wrong comment is worse than none.
- **Never** write review/release-process prose in source: no `Slice X` /
  `Phase N` labels, no `v0.x`/`v1.x` release-scope notes, no `out of scope for
  this PR`, `for now`, `WIP`, or "follow-up PR". Put scope, rationale, and
  future work in the PR description, an issue, an ADR, or the spec, and
  **reference** it from the code (e.g. `(ADR 0003 §4a)`).
- No commented-out code; no `TODO`/`FIXME` markers — file an issue instead.
- State a rationale once (at the definition or in an ADR); don't copy it to
  every call site.

`pixi run verify` enforces this (ruff `ERA`/`FIX` +
`tests/unit_tests/test_comment_hygiene.py`); the guard inspects comments and
docstrings only, never string literals, so wire-format names and error
messages are unaffected.
