---
description: Run the project's verification gate (make verify) and summarise the result
---

Run `make verify`.

- If it exits 0: summarise what changed since the last verify (use `git diff
  --stat` and `git log -1`) and stop.
- If it exits non-zero: parse the output, group failures by file, and propose
  the smallest fix that would make the next run pass. Cite each error as
  `path/to/file.ext:LINE`. Do not start applying the fix until the user
  confirms which one to apply (unless it is trivially a syntax error you
  introduced).

Never silently skip, disable, or `@ignore` a failing test. If a test must be
skipped, draft an ADR under `docs/adr/` and ask for confirmation.
