# Proposal

## Why

`pixi run test-py` measured 17.9 s (232 passed, 40 skipped), not the
"<1s" the docs claim — `dev/testing.md:12` is stale by roughly an
order of magnitude. The gap is structural: the pytest default collects
everything under `tests/`, so the slowest tests in the "fast" slice
are real `python -m build` wheel and sdist constructions. In addition,
the CLI's file-reading path has no boundary-input tests at all (empty
files, CRLF sources, non-UTF-8 bytes), and a wire-compat docstring
repeats the stale sub-second claim.

## What Changes

- Mirror the existing `consumer` marker with a `packaging` marker so artifact-build tests are deselected from the default run and re-selected in a dedicated lane wired into `verify`
- Correct the speed claims in `dev/testing.md` and the stale docstring to the measured numbers
- Add parametrized boundary-input tests for the CLI file-reading path

## Out of Scope

- Making the unit slice sub-second (agent-config tests shell out to real scripts by design)
- Fortran ctest changes, new CI lanes, and performance optimizations

## Capabilities

### Modified Capabilities

- `cli`: a new boundary-input robustness requirement pins graceful handling of empty, CRLF-terminated, and non-UTF-8 inputs

## Impact

`pyproject.toml` (markers), `pixi.toml` (dedicated packaging lane), `dev/testing.md`, `test_cli.py`, the wire-compat docstring, CHANGELOG.
