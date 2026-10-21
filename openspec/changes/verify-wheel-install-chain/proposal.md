# Proposal

## Why

The wheel-to-install-to-consume chain is never executed: the
external-consumer and `find_package` tests run against the editable
in-tree install (`pixi.toml:11-12`), so only content inspection
verifies the shipped layout — a layout regression would pass both
gates while breaking real `pip install` users. Related gaps: `twine
check` is a permanent skip (twine is in no environment,
`test_packaging_distribution.py:132-148`); the version-metadata chain
is asserted nowhere; `py.typed` and the runtime README are missing
from the expected-files slice; and the shipped README's links dangle
from `site-packages`.

## What Changes

- A `consumer`-marked test that installs the built wheel into a clean venv and drives the CMake recipe from that install
- Add `twine` to the dev dependencies; assert the wheel's `METADATA` `Version:` equals `preserf.__version__`
- Extend the expected-files slice with `py.typed` and the runtime README; state the POSIX-only prerequisite; fix the shipped README's links

## Out of Scope

- Release/publish automation (deferred until 0.2.0), new CI lanes, and runtime portability work
- No ADR for `twine`: test-scoped dev dependency, not a runtime dependency

## Capabilities

### Modified Capabilities

- `packaging-distribution`: wheel contents gains the extended slice; distribution metadata gains an executed twine gate and version assertion; a new requirement pins the consumption recipe from `site-packages`

## Impact

`pixi.toml`, `test_packaging_distribution.py`, both READMEs, CHANGELOG. Sequences after `restore-fast-test-slice` (shared marker).
