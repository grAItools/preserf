# Changelog

All notable changes to `preserf` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Slice plan and gap reference live in
[`development/plans/fortran-helper-roadmap.md`](development/plans/fortran-helper-roadmap.md)
and
[`development/references/v0.1-gap-analysis.md`](development/references/v0.1-gap-analysis.md).

## [0.2.0-dev] — post-v0.1.0 main, unreleased

### Added

- `src/preserf/preprocessor.py`: typed, two-pass reimplementation of
  `pp_ser.py` expanding every `!$SER` directive — covers Slice D core
  (`ppser_initialize` widening + end-to-end test still open) ([#6](https://github.com/grAItools/preserf/pull/6)).
- `src/preserf/cli.py`: `preserf` CLI with single-file, output-dir, and
  recursive modes ([#6](https://github.com/grAItools/preserf/pull/6)).
- `src/preserf/errors.py`: `DirectiveError` carries file/line context
  ([#6](https://github.com/grAItools/preserf/pull/6)).
- `.github/workflows/ci.yml`: Fortran CI gate — builds the helper,
  runs ctest, then runs `pixi run verify` with
  `PRESERF_REQUIRE_FORTRAN=1` so a broken Fortran build cannot pass by
  silently skipping the wire-compat test. Closes roadmap Slice F
  ([#14](https://github.com/grAItools/preserf/pull/14), [#15](https://github.com/grAItools/preserf/pull/15)).
- `.devcontainer/`: pixi-based dev container ([#10](https://github.com/grAItools/preserf/pull/10), [#12](https://github.com/grAItools/preserf/pull/12)).

### Changed

- Test layout reorganized into `tests/unit_tests/`,
  `tests/integration_tests/`, and `tests-fortran/unit/m_preserf/`
  ([#17](https://github.com/grAItools/preserf/pull/17)).
- Build harness consolidated onto pixi tasks; legacy
  Makefile/scripts removed ([#13](https://github.com/grAItools/preserf/pull/13)).
- Agent harness scaffolded via the
  `grAItools/harness-copier-template` ([#8](https://github.com/grAItools/preserf/pull/8), [#9](https://github.com/grAItools/preserf/pull/9)).

### Fixed

- `require_fits_int32` guard in `active_dims_c_order` / `put_halo_attr`
  closes a latent truncation on very large dim sizes / halo extents
  ([#16](https://github.com/grAItools/preserf/pull/16)).

## [0.1.0] — 2026-05

Initial usable preview: storage mapping decision + minimal Fortran helper
that pp_ser-generated source can link against in write mode for the most
common shapes.

### Added

- Storage mapping ADR and reference: Serialbox data model mapped onto
  NetCDF4 and Zarr V2 via NCZarr, with `tests/_support/storage.py` and
  `tests/_support/serialbox.py` reference readers and a Python
  round-trip test ([#3](https://github.com/grAItools/preserf/pull/3)).
- Minimal Fortran helper (`src/preserf-fortran/`):
  - `utils_preserf.f90` — lifecycle (`ppser_initialize`,
    `ppser_finalize`, `ppser_set_mode`, `ppser_get_mode`) plus the
    module-level state pp_ser-emitted code uses (`ppser_serializer`,
    `ppser_serializer_ref`, `ppser_savepoint`, `ppser_intlength`,
    `ppser_reallength`, `ppser_realtype`, `ppser_zrperturb`).
  - `m_preserf.f90` — `fs_register_field`, `fs_create_savepoint`,
    scalar `fs_add_savepoint_metainfo` / `fs_add_serializer_metainfo`
    (`logical` / `int32` / `int64` / `real32` / `real64` /
    `character`), `fs_write_field` / `fs_read_field` for `real64` 1D/2D/3D
    (4-arg and compile-only 5-arg perturb form),
    `fs_enable_serialization` / `fs_disable_serialization` /
    `fs_serialization_status`.
  - `m_serialize` / `utils_ppser` alias modules so pp_ser-generated
    source using the historical Serialbox module names compiles
    unchanged.
  - CMake 3.20+ build (`src/preserf-fortran/CMakeLists.txt`,
    `tests-fortran/CMakeLists.txt`); pkg-config discovery of
    `netcdf-fortran`; gfortran `-std=f2008`.
  - Native Fortran test (`tests-fortran/unit/m_preserf/test_minimal.f90`)
    plus cross-language wire-compat test
    (`tests/integration_tests/test_fortran_wire_compat.py`) that skips
    when the Fortran binary is absent ([#4](https://github.com/grAItools/preserf/pull/4)).
- Directive specification extracted from `pp_ser.py` as a reference
  document; initial project scaffolding (Python ≥3.12, pixi, MIT
  license) ([#1](https://github.com/grAItools/preserf/pull/1), [#2](https://github.com/grAItools/preserf/pull/2), [#5](https://github.com/grAItools/preserf/pull/5)).

[Unreleased]: https://github.com/grAItools/preserf/compare/v0.2.0-dev...HEAD
[0.2.0-dev]: https://github.com/grAItools/preserf/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/grAItools/preserf/releases/tag/v0.1.0
