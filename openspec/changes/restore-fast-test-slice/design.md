# Design

## Context

The `consumer` marker already solves exactly this problem for the
external-consumer builds: deselected from the default run via
`addopts = "-m 'not consumer'"`, re-selected by `pixi run test-consumer`
with `-m consumer`, and kept out of `verify` (which runs plain pytest and
inherits the deselection). The packaging artifact-build tests are the
same kind of slow, integration-layer work, so the same pattern fits —
deselect from the default run and re-select in a dedicated lane. Note
the strict lane (`test-py-with-fortran`) also inherits `addopts`, so the
packaging tests must be re-selected by their own lane rather than
relying on `verify`'s existing dependencies. The boundary tests pin
current behavior: empty files pass through with the prefix header, CRLF
is handled by the line splitter, and non-UTF-8 either processes or
diagnoses. The speed claims need correcting to measured numbers rather
than aspirational ones.

## Goals / Non-Goals

**Goals:**

- The default `pixi run test-py` slice contains no artifact
  construction; wheel/sdist builds run in their own lane.
- The documented speed claims match measured reality.
- The CLI's degenerate-input behavior is pinned so refactors cannot
  silently introduce tracebacks.

**Non-Goals:**

- Making the unit slice itself sub-second (the agent-config tests shell
  out to real scripts by design).
- Fortran ctest changes, new CI lanes, and performance optimizations.

## Decisions

- Add a `packaging` marker to the pytest configuration mirroring
  `consumer`, and extend the default deselection to
  `-m 'not consumer and not packaging'` (the conjunction form; the
  space-separated shorthand is not valid pytest syntax).
- Mark the wheel/sdist construction tests with the new marker, add a
  dedicated `test-packaging` pixi lane (`pytest -m packaging`), and wire
  it into `verify`'s depends-on so the artifact-build tests stay gated
  end to end.
- Boundary tests pin current behavior with parametrized cases rather
  than inventing new semantics: empty file, CRLF, and non-UTF-8 each
  get a defined outcome asserted.
- Correct the docs to measured numbers (17.9 s default slice, 6.8 s
  unit slice) rather than deleting the claims.

## Risks / Trade-offs

- Deselecting packaging builds from the default run could let a
  packaging regression land between lane runs; mitigated by wiring the
  dedicated lane into `verify`, closing the gap the deselection opens.
