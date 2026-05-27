# Slice E plan: Backend selector + NCZarr URL targets

## Phase 0 — Wait for Slice D

Slice D's `ppser_initialize` widening establishes the keyword
threading pattern this slice extends. Land E after D so the
signature only changes once.

## Phase 1 — Add the `backend` keyword

**Scope.** Plumb `backend='netcdf4' | 'nczarr-v2'` through
`ppser_initialize`.

**Steps.**

1. Add `backend` as an optional argument to `ppser_initialize` with
   default `'netcdf4'`.
2. Store the selected backend in the serializer state for
   `preserf_open_serializer` to read.
3. Use the same `'nczarr-v2'` label the Python reference path
   already uses (`tests/_support/storage.py`).

**Tests.** Covered by Phase 2's open-serializer test.

**Exit criteria.** Helper compiles with the new keyword; default
behaviour unchanged.

## Phase 2 — Rework `preserf_open_serializer`

**Scope.** Construct the right file URL / mode string per backend.

**Steps.**

1. Branch on backend:
   - `netcdf4` → `<directory>/<prefix>.nc` with `NF90_NETCDF4`
     (today's behaviour).
   - `nczarr-v2` →
     `file://<directory>/<prefix>.zarr#mode=nczarr,zarr2` with the
     creation flags NCZarr V2 needs (the netcdf-c URL-mode
     vocabulary handles the rest).
2. Decide whether to keep the URL construction inline or factor it
   into a small helper; document the choice in a source comment.
3. Confirm the netcdf-c build the project depends on has NCZarr
   enabled (already required per ADR 0002's hard build requirement).

**Tests.**

- Native scenario: open with `backend='nczarr-v2'` and write a
  smoke field; assert the `.zarr` directory store appears on disk
  with the right top-level layout.

**Exit criteria.** Native NCZarr V2 round-trip passes; default
NetCDF4 round-trip still passes.

## Phase 3 — Cross-language test

**Scope.** Extend the wire-compat suite to cover Fortran-written
NCZarr V2 stores.

**Steps.**

1. Parametrise
   `tests/integration_tests/test_fortran_wire_compat.py` over
   `(backend ∈ {netcdf4, nczarr-v2})`.
2. The Python-side `test_storage_round_trip.py` already exercises
   both backends from Python — reuse its reader path.

**Tests.** The parametrisation is the test.

**Exit criteria.** Cross-language matrix passes in CI with
`PRESERF_REQUIRE_FORTRAN=1` for both backends. Zarr V3 (NCZarr V3
PR) remains explicitly deferred until the netcdf-c PR lands; the
URL-mode form for V3 will plug into the same code path with no
helper changes.
