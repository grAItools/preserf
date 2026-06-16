---
paths:
  - "src/**/*.py"
  - "src/**/*.f90"
  - "src/**/*.F90"
  - "tests/**/*.py"
  - "examples/**"
---

# Comment hygiene

When editing source here, comments and docstrings must describe the **code**,
not the review/release process. This rule exists only to surface the policy at
edit time; the policy itself — with examples — lives in one place:

- Policy: [`docs/style.md` → "Comments"](../../docs/style.md#comments)
- Rationale: [ADR 0006](../../docs/adr/0006-comments-describe-code-not-process.md)

`pixi run verify` enforces it (ruff `ERA`/`FIX` +
`tests/unit_tests/test_comment_hygiene.py`): process prose, commented-out code,
and `TODO`/`FIXME` markers fail the gate.
