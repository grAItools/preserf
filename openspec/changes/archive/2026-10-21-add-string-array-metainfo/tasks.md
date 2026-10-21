# Tasks: add string-array metainfo support

## 1. Runtime overload

- [x] Add an NC_STRING-vector cross-language round-trip test that fails against the current runtime
- [x] Add `fs_add_savepoint_metainfo_s_1d` and `fs_add_serializer_metainfo_s_1d` overloads to `m_preserf.F90`
- [x] Confirm the on-disk encoding matches the `NC_STRING` vector contract already decoded by `tests/_support/storage.py`

## 2. Verification

- [x] Extend the wire-compat test in `tests/integration_tests/test_fortran_wire_compat.py` with the string-array metainfo scenario
- [x] Run `pixi run verify` and confirm it is green
