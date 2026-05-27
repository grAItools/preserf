# Slice E: Backend selector + NCZarr URL targets

## Problem

`preserf_open_serializer` in `src/preserf-fortran/utils_preserf.f90`
hardcodes `<directory>/<prefix>.nc` and passes `NF90_NETCDF4`. There
is no backend selector at the `ppser_initialize` boundary, so NCZarr
V2 / Zarr URL targets — which ADR
[`docs/adr/0002-storage-model-mapping.md`](../../docs/adr/0002-storage-model-mapping.md)
explicitly designs the schema for, and which the Python reference
path (`tests/_support/storage.py`) already supports — are
unreachable from the Fortran helper.

## Goal

`ppser_initialize` accepts a `backend` keyword that selects between
NetCDF4 and NCZarr V2 stores; the Fortran helper produces either
without touching the rest of the helper code.

## Non-goals

- Zarr V3 (NCZarr V3). Explicitly deferred until the netcdf-c
  Zarr V3 PR lands; see ADR 0002.
- Reworking the schema. The same group-per-savepoint layout serves
  both backends; that's the whole point of the unified-via-NCZarr
  decision in ADR 0002.

## Dependencies

**Depends on Slice D** (`ppser_initialize` widening). The `backend`
keyword threads through the same signature as Slice D's other
keywords; landing E before D would require touching the same
signature twice.

## Success criteria

- `ppser_initialize` accepts `backend='netcdf4' | 'nczarr-v2'` (the
  `nczarr-v2` label matches the selector already used by
  `tests/_support/storage.py`). Default is `'netcdf4'` for backward
  compatibility.
- `preserf_open_serializer` constructs the correct file URL / mode
  string per backend:
  - `netcdf4`: `<directory>/<prefix>.nc` with `NF90_NETCDF4` (today's
    behaviour).
  - `nczarr-v2`: `file://<directory>/<prefix>.zarr#mode=nczarr,zarr2`
    with appropriate creation flags.
- Cross-language test extends
  `tests/integration_tests/test_fortran_wire_compat.py` to also
  accept Fortran-written NCZarr V2 stores. The Python-side
  round-trip in `tests/unit_tests/test_storage_round_trip.py`
  already covers both backends; this slice adds Fortran-written
  input as another covered shape.
- No regression on existing NetCDF4 paths.
