# Slice B tasks — Full type-coverage matrix

## Phase 0 — ADR for the library CPP dependency

- [x] Add `docs/adr/0004-fortran-cpp-templates.md` (Nygard format):
      `-cpp` + `#include` templates on the library target.

## Phase 1 — Field write/read overload matrix

- [x] Rename `m_preserf.f90` → `m_preserf.F90`; add `-cpp
      -ffree-line-length-none` to the library CMake target.
- [x] Template files: `preserf_write_field.inc`, `preserf_read_field.inc`,
      logical variants, `preserf_read_field_perturb.inc`,
      `preserf_apply_perturb.inc`.
- [x] Instantiate all 25 `{logical, int32, int64, real32, real64}` ×
      `{0D..4D}` write + 25 read overloads; extend both generic interfaces.
- [x] 0-D support: `active_dims_c_order` accepts the all-zero tuple
      (zero-length `dims`, scalar variable); `ensure_dims` /
      `ensure_variable` handle rank 0.
- [x] Extend read-perturb to `real32` (10 perturb overloads + 10
      `apply_perturb` helpers, ranks 0–4 × `real32`/`real64`).
- [x] Native `type-matrix` ctest scenario: per-dtype 1D round-trip, 0-D
      scalar, 4-D field, real32 perturb.

## Phase 2 — Array-metainfo overloads

- [x] `put_typed_array_attr` / `check_typed_array_attr` (vector attribute
      + array-TypeID shadow; read-mode validation of length, values, tag).
- [x] 1D-array overloads of `fs_add_savepoint_metainfo` /
      `fs_add_serializer_metainfo` for `logical / int32 / int64 / real32 /
      real64`; registered in both interfaces.
- [x] Native round-trip of array metainfo on root + savepoint
      (`type-matrix` scenario).
- [ ] `_s_1d` (array STRING metainfo, `NC_STRING`): **deferred to Slice
      B′** — the F90 `nf90_put_att` API has no clean vector-of-strings
      path (storage_mapping.md §1 note).

## Phase 3 — Parametrised cross-language matrix

- [x] `wire-matrix` Fortran scenario writes one field per `(dtype, rank)`
      plus array metainfo.
- [x] `test_fortran_wire_compat.py` parametrised over all 25
      `(rank, dtype)`: asserts on-disk netCDF type + registry `type_id`
      against `storage_mapping.md` §1, plus shape/value round-trip.
- [x] Parametrised array-metainfo TypeID + value check (subsumes the PR #4
      "metainfo coverage limited to int32/real64" review note).

## Phase 4 — Bookkeeping

- [x] `CHANGELOG.md` entry under `0.2.0-dev`.
- [x] Flip Slice B row in `specs/README.md` (`planned` → `shipped`).
- [x] This `tasks.md`.
