# Testing strategy

## What the agent runs

- **Pre-claim-done gate:** `pixi run verify` — fmt-check + lint +
  typecheck + test. Also what the Claude Code `Stop` hook runs.
- **Fast loop:** `pixi run test` (or `pixi run test-unit` for the Python
  unit slice only) — currently completes in <1s and must stay <60s.
- **Cross-language slice:** `pixi run test-integration` — requires the
  Fortran binary to be built first (`pixi run build-fortran`). Skips
  cleanly without it by default; CI forces a hard failure via the env
  flag described below.
- **Native Fortran:** `pixi run build-fortran` then
  `pixi run test-fortran` (ctest).

## Layering

The test tree was reorganized in [#17](https://github.com/grAItools/preserf/pull/17)
into three layers:

- `tests/unit_tests/` — fast Python tests. Covers the preprocessor
  directive-by-directive (`test_preprocessor.py`), the CLI's three modes
  (`test_cli.py`), and the storage round-trip with all six TypeIDs in
  scalar and array form across both backends
  (`test_storage_round_trip.py`).
- `tests/integration_tests/` — cross-language wire-compat. The single
  test (`test_fortran_wire_compat.py`) builds a store with the Fortran
  helper and reads it back with `tests/_support/storage.py`. Skips
  with `pytest.skip` when the Fortran binary at
  `build/preserf-fortran/` is missing.
- `tests-fortran/unit/m_preserf/` — native Fortran via CMake/ctest.
  `test_minimal.f90` exercises lifecycle, savepoint creation, and the
  shipped write paths (`real64` 1D/2D/3D, scalar metainfo for `int32`
  and `real64`).

`tests/_support/` is shared fixtures: `storage.py` (the preserf
NetCDF4/Zarr V2 reader-writer used to round-trip stores in pure Python)
and `serialbox.py` (the reference reader for the legacy Serialbox dump
format, used to validate the schema mapping).

## CI mode

`.github/workflows/ci.yml:38` exports `PRESERF_REQUIRE_FORTRAN=1` for the
`pixi run verify` step. With that flag set, the wire-compat fixture
turns its `pytest.skip` into a hard `pytest.fail` — a broken Fortran
build cannot let the suite pass by silently skipping the cross-language
test. `xfail` is deliberately _not_ used because an xfailed test still
lets the suite pass.

## Determinism

- Time, randomness, and I/O are injectable: pytest tmpdir for the file
  system, no wall-clock reads in production code, no global RNG state.
- Snapshot fixtures (e.g. the in-memory `SerialboxDump` builder in
  `test_storage_round_trip.py`) are committed, not generated. If a fixture
  diverges from the spec, change the fixture explicitly.
- Flaky tests are bugs; quarantine them in their own target and open
  an issue, don't `@pytest.mark.flaky`-retry them.

## Adding tests

- Pure Python behaviour → `tests/unit_tests/`.
- Anything that crosses the Python ↔ Fortran wire →
  `tests/integration_tests/`; gate on the same Fortran-binary fixture so
  local dev still skips cleanly.
- Anything that exercises the Fortran helper in isolation →
  `tests-fortran/unit/m_preserf/`; wire into ctest via that
  directory's `CMakeLists.txt`.

Coverage is a smoke detector, not a goal — don't write tests just to
hit a number. Do, however, write a failing test before any bug fix.
