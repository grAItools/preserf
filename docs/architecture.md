# Architecture

> One-page overview. Anything longer belongs in an ADR or a dedicated doc.

## High-level

`preserf` is a preprocessor for Fortran data serialization directives.
`!$SER` directives embedded in Fortran source are expanded into explicit
calls into a Fortran runtime API; that API writes to NetCDF4 or NCZarr V2
stores. The project ships both the preprocessor (Python) and the runtime
API (Fortran), so a pp_ser-annotated source can be compiled and run
end-to-end against preserf alone.

## Module map

- `src/preserf/` — Python preprocessor.
  - `preprocessor.py` — two-pass directive expander. **Pass 1** (analysis)
    scans the source to learn which serializer calls will be needed; **pass
    2** (generation) injects the right `USE` imports and rewrites each
    `!$SER` line as a guarded block of Fortran calls. See
    [`development/references/directives_specification.md`](../development/references/directives_specification.md)
    for the directive grammar.
  - `cli.py` — Typer-based CLI. Three modes: single-file
    (`preserf input.f90 -o output.f90`), output-dir
    (`preserf input.f90 -O outdir/`), and recursive
    (`preserf -r src/ -O out/`).
  - `errors.py` — `DirectiveError` carries file/line context.
- `src/preserf-fortran/` — Fortran runtime helper.
  - `m_preserf.f90` — canonical API (`fs_register_field`,
    `fs_create_savepoint`, `fs_add_*_metainfo`, `fs_write_field`,
    `fs_read_field`, enable/disable/status).
  - `utils_preserf.f90` — lifecycle (`ppser_initialize`, `ppser_finalize`,
    `ppser_set_mode`, `ppser_get_mode`) and module-level state
    pp_ser-generated code relies on (`ppser_serializer`,
    `ppser_serializer_ref`, `ppser_savepoint`, type/length constants,
    `ppser_zrperturb`).
  - `m_serialize.f90`, `utils_ppser.f90` — alias modules so legacy
    pp_ser-generated source compiles unchanged against preserf.
  - `CMakeLists.txt` + `preserf_version.f90.in` — CMake 3.20+, pkg-config
    discovery of netcdf-fortran, gfortran `-std=f2008`.

## External dependencies

- `typer` (≥0.12) — CLI parsing.
- `rich` (≥13.0) — CLI output formatting.
- `netcdf-fortran` (≥4.6.0, conda-forge) — the Fortran helper writes via
  `nf90_*`. Introduced by ADR
  [`docs/adr/0002-storage-model-mapping.md`](adr/0002-storage-model-mapping.md);
  the URL/mode string passed to `ppser_initialize` selects NetCDF4 or
  NCZarr V2 at runtime.
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
- **Storage backend.** Both NetCDF4 (`<dir>/<prefix>.nc`) and NCZarr V2
  (`file://<dir>/<prefix>.zarr#mode=nczarr,zarr2`) are reachable through
  the same `nf90_*` code path. Group-per-savepoint layout, with
  `/_fields` registry and `/savepoints/sp_NNNNNN` subgroups. The concrete
  attribute and dtype mapping is in
  [`development/references/storage_mapping.md`](../development/references/storage_mapping.md).

## See also

- ADRs of record: [`adr/`](adr/)
- Style guide: [`style.md`](style.md)
- Testing strategy: [`testing.md`](testing.md)
- Roadmap: [`../development/plans/fortran-helper-roadmap.md`](../development/plans/fortran-helper-roadmap.md)
- v0.1 gap reference: [`../development/references/v0.1-gap-analysis.md`](../development/references/v0.1-gap-analysis.md)
