# Slice B: Full type-coverage matrix (numeric)

## Problem

The Fortran helper's type-coverage matrix is `real64`-only for fields
and scalar-only for metainfo. There are no `bool` / `int32` / `int64`
/ `float32` field overloads, no 0D or 4D field overloads, and no
array-metainfo variants of _any_ type —
`fs_add_savepoint_metainfo` and `fs_add_serializer_metainfo` only
have scalar overloads (`_l` / `_i4` / `_i8` / `_r4` / `_r8` / `_s`).
1D-array metainfo overloads are part of this slice.

## Goal

The Fortran helper supports the full numeric type-coverage matrix
that pp_ser-generated source can emit: every combination of
`logical` / `integer(int32)` / `integer(int64)` / `real(real32)` /
`real(real64)` × 0D / 1D / 2D / 3D / 4D for fields, and 1D-array
overloads of each scalar type for metainfo.

## Non-goals

- **String data fields** (Serialbox `TypeID::String`) are explicitly
  deferred to a separate slice (B′). `storage_mapping.md` §9 says
  `TypeID::String` data lands as `NF90_STRING` variables under the
  same group-per-savepoint layout, with no schema-version bump
  expected, but the Python reference reader
  (`numpy_dtype_for` in `tests/_support/serialbox.py`) currently
  rejects the type and there's no `NF90_STRING` write path in
  `fs_write_field`. Bundling strings into this slice would expand
  scope; tracking it separately keeps the primary numeric matrix
  tractable.
- Read-mode resolve+validate for the new overloads (Slice A-1
  territory); this slice trusts A-1's validation shape.
- **Array string metainfo** (`_s_1d`, on-disk `NC_STRING`) is deferred to
  Slice B′ alongside string data fields: the netcdf-fortran F90
  `nf90_put_att` API has no clean vector-of-strings path
  (`storage_mapping.md` §1 note). The five numeric array-metainfo
  overloads (`logical / int32 / int64 / real32 / real64`) ship in this
  slice; the scalar `_s` string overload is unaffected.

## Success criteria

- Field write/read overloads exist for every (rank ∈ {0,1,2,3,4}) ×
  (dtype ∈ {logical, int32, int64, real32, real64}) combination.
- 1D-array metainfo overloads exist for `fs_add_savepoint_metainfo`
  and `fs_add_serializer_metainfo` for each scalar type per Serialbox
  `MetainfoValue::Array`.
- The cross-language test
  `tests/integration_tests/test_fortran_wire_compat.py` grows a
  parametrised matrix that, for each (rank, dtype), asserts the raw
  netCDF type via `Dataset[…].dtype` matches the TypeID → netCDF-type
  table in `storage_mapping.md` §1.
- `fs_register_field` already takes a generic `type` string, so its
  registry side remains unchanged; only the field-write/read
  overloads and array-metainfo overloads grow.
