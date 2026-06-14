# Architecture

## High-level

`preserf` is a preprocessor for Fortran data serialization directives.
`!$SER` directives embedded in Fortran source are expanded into explicit
calls into a Fortran runtime API; that API writes to NetCDF4 stores
(default) or NCZarr V2 stores, both using the same `nf90_*` code path
as designed by ADR 0002. The project ships both the preprocessor
(Python) and the runtime API (Fortran), so a pp_ser-annotated source
can be compiled and run end-to-end against preserf alone.

## Module map

- `src/preserf/` — Python preprocessor.
  - `preprocessor.py` — two-pass directive expander. **Pass 1** (analysis)
    scans the source to learn which serializer calls will be needed; **pass
    2** (generation) injects the right `USE` imports and rewrites each
    `!$SER` line as a guarded block of Fortran calls. See
    [`docs/references/directives_specification.md`](references/directives_specification.md)
    for the directive grammar.
  - `cli.py` — Typer-based CLI. Three modes: single-file
    (`preserf input.f90 -o output.f90`), output-dir
    (`preserf input.f90 -d outdir/`), and recursive
    (`preserf -r -d out/ src/`, where `--recursive` requires
    `--output-dir`).
  - `errors.py` — `DirectiveError` carries file/line context.
  - `fortran_dist.py` — exposes `get_fortran_dir()` / `get_cmake_helper()`
    (numpy `get_include()` pattern) so build systems can locate the
    bundled runtime without knowing install internals. Also surfaced as
    `preserf --fortran-dir` / `--cmake-helper` CLI flags.
- `src/preserf/fortran/` — Fortran runtime (shipped inside the wheel as
  package data).
  - `m_preserf.F90` — canonical API: `fs_register_field`,
    `fs_create_savepoint`, `fs_add_*_metainfo`, `fs_write_field`,
    `fs_read_field` (full type-coverage matrix: bool / i32 / i64 / f32 /
    f64, 0D–4D), `fs_write_kbuff` (`!$SER DATA_KBUFF`), tracer write API
    (`fs_RegisterAllTracers`, `ppser_write_tracer_*`), `fs_Option`, and
    enable/disable/status.
  - `utils_preserf.f90` — lifecycle (`ppser_initialize`, `ppser_finalize`,
    `ppser_set_mode`, `ppser_get_mode`) and module-level state
    pp_ser-generated code relies on (`ppser_serializer`,
    `ppser_serializer_ref`, `ppser_savepoint`, type/length constants,
    `ppser_zrperturb`).
  - `m_serialize.f90`, `utils_ppser.f90` — alias modules so legacy
    pp_ser-generated source compiles unchanged against preserf.
  - `cmake/PreserfFortran.cmake` — CMake helper providing
    `preserf_add_fortran_target()` / `preserf_fortran_library()`.
  - `CMakeLists.txt` + `preserf_version.f90.in` — CMake 3.20+, pkg-config
    discovery of netcdf-fortran, gfortran `-std=f2008`.

## External dependencies

- `typer` (≥0.12) — CLI parsing.
- `rich` (≥13.0) — CLI output formatting.
- `netcdf-fortran` (≥4.6.0, conda-forge) — the Fortran helper writes via
  `nf90_*`. Introduced by ADR
  [`docs/adr/0002-storage-model-mapping.md`](adr/0002-storage-model-mapping.md);
  both the NetCDF4 and NCZarr V2 paths are wired up, selected by the
  `backend` keyword on `ppser_initialize` or the `PRESERF_BACKEND` env var.
- Dev-only: `ruff`, `mypy`, `pytest`, `dprint`, `fprettify`, `cmake`,
  `fortran-compiler` (conda-forge). All managed via `pixi.toml`.

## Boundaries

- **CLI surface.** `preserf [OPTIONS] FILE_OR_DIR` — entry point declared
  as `preserf = "preserf.cli:app"` in `pyproject.toml`. No daemon, no
  network, no background workers.
- **Fortran runtime API.** Public symbols are the `fs_*`, `ppser_*`, and
  `preserf_*` routines exported from `m_preserf` / `utils_preserf`.
  pp_ser-generated source binds to those by `USE m_serialize` /
  `USE utils_ppser` (the alias modules).
- **Storage backend.** The Fortran helper supports two backends, both
  using the same `nf90_*` code path as designed by ADR
  [`docs/adr/0002-storage-model-mapping.md`](adr/0002-storage-model-mapping.md):
  - `netcdf4` (default) — writes `<dir>/<prefix>.nc`.
  - `nczarr-v2` — writes `<dir>/<prefix>.zarr` as an NCZarr V2 directory
    store via the `file://<path>#mode=nczarr,zarr2` URL.
    The backend is selected by the `backend=` keyword on `ppser_initialize`,
    overridable at runtime by the `PRESERF_BACKEND` environment variable.
    Either backend uses the same group-per-savepoint layout, with
    `/_fields` registry and `/savepoints/sp_NNNNNN` subgroups; the concrete
    attribute and dtype mapping is in
    [`docs/references/storage_mapping.md`](references/storage_mapping.md).
    Zarr V3 stays forward-compatible but is deferred until netcdf-c's NCZarr V3
    support lands.

## See also

- ADRs of record: [`adr/`](adr/)
- Style guide: [`style.md`](style.md)
- Testing strategy: [`testing.md`](testing.md)
- Per-slice specs (and overview): [`../specs/README.md`](../specs/README.md)
