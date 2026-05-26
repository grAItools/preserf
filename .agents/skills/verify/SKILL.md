---
name: verify
description: |
  Run the project's verification gate. Use this skill whenever the user says
  "verify", "is this ready", "ready to commit", "check this", or after any
  non-trivial code change. Runs `pixi run verify`, summarises failures with
  file:line evidence, and proposes the smallest fix that would make the next
  run pass. Never silently skips or disables a failing test.
---

# verify

## When to invoke

- After any non-trivial edit, before claiming a task is done.
- When the user signals readiness ("verify", "ready", "ship it").
- Before opening or updating a pull request.

## What to do

1. Run `pixi run verify` in the repository root. Capture both stdout and exit code.
2. If exit code is 0 — summarise what changed since the last verify, the
   tests that ran, and stop. Do not run additional checks.
3. If exit code is non-zero — parse the output, group errors by file, and
   propose the smallest fix that would make the next run pass. Cite each
   error as `path/to/file.ext:LINE`.
4. If a test must be skipped to proceed (rare), draft an ADR explaining why
   and ask the user to confirm. Never silently `@pytest.mark.skip`,
   `it.skip(...)`, or `#[ignore]` a failing test.

## Gotchas

- The `Stop` hook in `.claude/settings.json` already runs `pixi run verify`.
  This skill is for the _interactive_ case where the user wants verification
  before the agent's natural stop.
- `pixi run verify` exits with the failing task's code (typically 1). The
  Stop hook maps any non-zero exit to 2 via `|| exit 2` — both mean "fix it".
- On slow machines `pixi run verify` may exceed 60s. If that becomes
  routine, open an ADR to move slow suites to
  `pixi run test-all` / CI.
