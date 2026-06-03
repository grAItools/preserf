# Testing strategy

## What the agent runs

- **Pre-claim-done gate:** `pixi run verify` — fmt-check + lint +
  typecheck + `test-py`. Also what the Claude Code `Stop` hook runs.
- **Fast loop:** `pixi run test-py` (or `pixi run test-py-unit` for the
  Python unit slice only) — currently completes in <1s and must stay <60s.
- **Cross-language slice:** `pixi run test-py-integration` — requires the
  Fortran binary to be built first (`pixi run build-fortran`). Skips
  cleanly without it by default; CI forces a hard failure via the env
  flag described below.
- **Native Fortran:** `pixi run test-fortran` (ctest; chains
  `build-fortran` automatically).
- **Strict pytest (no skips):** `pixi run test-py-with-fortran` — sets
  `PRESERF_REQUIRE_FORTRAN=1` and serializes after `test-fortran`, so
  the wire-compat test fails (instead of skipping) when the Fortran
  binary is missing.
- **Everything-at-once (slow, not in `verify`):** `pixi run test-all` —
  `test-py-with-fortran` + every example under `examples/`. Pixi's
  `depends-on` siblings may run in parallel, so `test-all` deliberately
  chains through `test-py-with-fortran` (which itself depends on
  `test-fortran`) rather than listing the build/ctest/pytest tasks as
  parallel siblings — otherwise pytest could start before the Fortran
  binary exists.

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
  with `pytest.skip` when the Fortran test binary hasn't been built —
  the `fortran_binary` fixture in `tests/conftest.py` probes
  `build/preserf-fortran/unit/m_preserf/` plus the per-config subdirs
  that multi-config CMake generators produce.
- `tests-fortran/unit/m_preserf/` — native Fortran via CMake/ctest.
  `test_minimal.f90` exercises lifecycle, savepoint creation, the
  shipped `real64` 1D/2D/3D field write paths, scalar serializer
  metainfo across `character` / `int32` / `logical` / `int64` /
  `real32`, and scalar savepoint metainfo for `int32` / `real64`. (The
  logical / int64 / real32 / character savepoint overloads are
  exercised only by the Python wire-compat test today — tracked as
  tech debt on the roadmap.)

`tests/_support/` is shared fixtures: `storage.py` (the preserf
NetCDF4/Zarr V2 reader-writer used to round-trip stores in pure Python)
and `serialbox.py` (the reference reader for the legacy Serialbox dump
format, used to validate the schema mapping).

## CI mode

The "Run full verify gate" step in
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) exports
`PRESERF_REQUIRE_FORTRAN=1` when invoking `pixi run verify`. With that
flag set, the wire-compat fixture turns its `pytest.skip` into a hard
`pytest.fail` — a broken Fortran build cannot let the suite pass by
silently skipping the cross-language test. `xfail` is deliberately
_not_ used because an xfailed test still lets the suite pass.

CI also runs `pixi run test-examples` as its own step after `verify`,
so every example under `examples/` is built and executed on every PR.
This is deliberately a separate step (not part of `verify`) so the
local `pixi run verify` loop stays fast while a broken example still
breaks CI.

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
