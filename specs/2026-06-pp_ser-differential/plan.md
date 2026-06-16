# Plan — pp_ser differential test

## Phase 1 — reference harness (`tests/_support/ppser_reference.py`)

- Load `vendor/pp_ser.py` by path via `importlib` (it is not a package), once at
  module import, suppressing its Python-2-era `SyntaxWarning`s.
- `expand_with_ppser(source, *, real="ireals") -> str`: write `source` to a temp
  file, run `PpSer(infile, outfile=..., real=...).preprocess()`, return the
  expanded text. Default `real="ireals"` to match preserf's `Options` default
  (upstream's `__main__` hard-codes `wp`; the `PpSer` class default is `ireals`).
- `extract_runtime_calls(expanded) -> list[str]`: join Fortran `&` continuations,
  then capture each `call <name>(...)` line, whitespace-normalized, in order.
  Shared by both tools so the comparison is symmetric.

**Test for phase 1:** covered implicitly by phase 2 (the harness is exercised by
every parametrized case); plus a smoke assertion that `extract_runtime_calls`
joins continuations and drops comments.

## Phase 2 — differential test (`tests/unit_tests/test_pp_ser_differential.py`)

- `test_preserf_matches_upstream_pp_ser` — parametrized over the agreement
  corpus; asserts `preserf_calls == ppser_calls`.
- `test_subscript_arithmetic_diverges_from_upstream` — parametrized over
  `arr(i-1)`, `arr(i+1)`, `arr(2*i)`, `a(i)%b(j-1)`; asserts both write the
  field, preserf reads it back, upstream does not.
- Build the agreement corpus empirically: start from the directives known to
  agree and run the test; if a case diverges for a _benign_ reason, either
  normalize it away in the harness (documented) or move it to a pinned-divergence
  assertion. Do **not** loosen the comparison to paper over a real difference.

**Test for phase 2:** the tests are the deliverable; `pixi run test-py-unit`
green, with both new tests collected and passing.

## Phase 3 — docs

- `CHANGELOG.md`: Added entry under Unreleased.
- `docs/testing.md`: one line noting preserf's expansion is now differentially
  tested against the vendored upstream `pp_ser`.
- Keep `specs/2026-06-pp_ser-differential/` as the design record.

## Verification

`pixi run verify` (fmt-check, lint, typecheck, full test suite) green. The new
test runs in the default `dev` environment with no Fortran binary and no network.
