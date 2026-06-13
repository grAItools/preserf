# Testing strategy

## What the agent runs

- **Pre-claim-done gate:** `pixi run verify` — fmt-check + lint +
  typecheck + `test-py-with-fortran` (which chains `build-fortran` and
  `test-fortran` and then runs pytest strictly, so a missing Fortran
  binary fails the gate instead of silently skipping the wire-compat
  test). Also what the Claude Code `Stop` hook runs. On a cold tree the
  Fortran configure+build adds ~15s; warm runs settle at <6s.
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
- **External-consumer / find_package:** `pixi run test-consumer` — tests
  that compile a real project against the bundled runtime via
  `find_package`. Deselected from `verify` (slow) but run in CI as a
  separate step with `PRESERF_REQUIRE_FORTRAN=1`. Also included in
  `test-all`.
- **Everything-at-once (slow, not in `verify`):** `pixi run test-all` —
  `test-py-with-fortran` + `test-examples` + `test-consumer`. Pixi's
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
- `tests/integration_tests/` — five cross-language and packaging tests:
  - `test_fortran_wire_compat.py` — builds a store with the Fortran
    helper and reads it back with `tests/_support/storage.py`. Skips
    with `pytest.skip` when the Fortran test binary hasn't been built;
    the `fortran_binary` fixture in `tests/conftest.py` probes
    `build/preserf-fortran/unit/m_preserf/` plus the per-config subdirs
    that multi-config CMake generators produce.
  - `test_preprocessor_e2e.py` — end-to-end preprocessor pipeline test.
  - `test_packaging_distribution.py` — asserts the wheel ships the
    Fortran runtime sources and CMake helper.
  - `test_external_consumer.py` / `test_install_find_package.py` —
    `@pytest.mark.consumer` tests that compile a real project against the
    bundled runtime; deselected from `verify` but run by `test-consumer`
    and in CI.
- `tests-fortran/unit/m_preserf/` — native Fortran via CMake/ctest.
  `test_minimal.f90` covers ~50 ctest scenarios: lifecycle, savepoint
  creation, the full type-coverage matrix (logical / i32 / i64 / f32 /
  f64, 0D–4D), scalar and array metainfo, tracer I/O, k-buffer writes,
  `fs_Option`, both backends, and negative scenarios (bad backend,
  duplicate field, zero-extent dims, write-to-read-only).

`tests/_support/` is shared fixtures: `storage.py` (the preserf
NetCDF4/Zarr V2 reader-writer used to round-trip stores in pure Python),
`serialbox.py` (a re-implementation of the legacy Serialbox dump format,
used to validate schema mapping — note: validated only by self-round-trip,
see issue #68), and `consumer.py` (helper for the external-consumer build
tests).

## CI mode

`PRESERF_REQUIRE_FORTRAN=1` (set by the `test-py-with-fortran` task,
which `verify` and `test-all` both depend on) turns the wire-compat
fixture's `pytest.skip` into a hard `pytest.fail` — a broken Fortran
build cannot let the suite pass by silently skipping the cross-language
test. `xfail` is deliberately _not_ used because an xfailed test still
lets the suite pass. CI also belt-and-suspenders the env var at the
`Run full verify gate` step in
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

CI also runs `pixi run test-examples` and `pixi run test-consumer`
(with `PRESERF_REQUIRE_FORTRAN=1`) as dedicated steps after `verify`,
so broken examples and a broken install/`find_package` chain both fail
CI even though neither is part of `verify`.

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
