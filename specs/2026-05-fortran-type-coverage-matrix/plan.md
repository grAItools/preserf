# Slice B plan: Full type-coverage matrix

## Phase 1 — Field write/read overload matrix

**Scope.** Fill out `fs_write_field` and `fs_read_field` overloads
for the full `{logical, int32, int64, real32, real64}` × `{0D, 1D, 2D,
3D, 4D}` combination.

**Steps.**

1. Generate the overload skeletons (likely a CPP `#define` or a small
   code-generation step — pick one and document the choice in a
   source comment).
2. Wire each overload to the existing `nf90_put_var` / `nf90_get_var`
   path with the correct kind constant.
3. Confirm `fs_register_field` still works unchanged for every new
   dtype (it already takes a generic `type` string).

**Tests.**

- Extend `tests-fortran/unit/m_preserf/test_minimal.f90` with at
  least one write+read round-trip per dtype × 1D scenario (full
  rank coverage is in cross-language test).

**Exit criteria.** All 25 (5 dtype × 5 rank) field write/read paths
compile and round-trip on a smoke fixture.

## Phase 2 — Array-metainfo overloads

**Scope.** 1D-array overloads of `fs_add_savepoint_metainfo` and
`fs_add_serializer_metainfo` for each scalar type per Serialbox
`MetainfoValue::Array`.

**Steps.**

1. Add `_l_1d` / `_i4_1d` / `_i8_1d` / `_r4_1d` / `_r8_1d` /
   `_s_1d` overloads for both metainfo helpers.
2. Wire to `nf90_put_att` (which is natively vector-valued in both
   NetCDF4 and NCZarr backends — no new wire format needed).

**Tests.**

- Native Fortran scenario per overload — write metainfo, read back
  with `nf90_get_att`, assert array content matches.

**Exit criteria.** All array-metainfo overloads compile, round-trip,
and surface the right netCDF attribute shape.

## Phase 3 — Parametrised cross-language matrix

**Scope.** Grow `test_fortran_wire_compat.py` from a single
`real64` 3D scenario into a parametrised matrix.

**Steps.**

1. Parametrise the cross-language test over `(rank, dtype)` for all
   25 combinations.
2. For each `(rank, dtype)`, assert the raw netCDF type via
   `Dataset[…].dtype` matches the TypeID → netCDF-type table in
   `storage_mapping.md` §1.
3. Add a parametrised case for 1D-array metainfo per scalar type.
4. Close the PR #4 review-note observation that "savepoint-metainfo
   native test coverage is limited to int32 and real64" — the
   parametrised matrix subsumes it.

**Tests.** The parametrisation is the test.

**Exit criteria.** CI green with `PRESERF_REQUIRE_FORTRAN=1`; the
TypeID-table assertion fires on every (rank, dtype).

## Out of scope (Slice B′ — string data fields)

String data fields land in a follow-up slice once the Python
reference reader gains `NF90_STRING` support and `fs_write_field` /
`fs_read_field` get string overloads. Deferred per the roadmap's
v1.0 DoD note.
