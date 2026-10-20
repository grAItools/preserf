# Tasks: add string-array metainfo support

## 1. Runtime overload

- [ ] Add an NC_STRING-vector cross-language round-trip test that fails against the current runtime
- [ ] Add `fs_add_savepoint_metainfo_s_1d` and `fs_add_serializer_metainfo_s_1d` overloads to `m_preserf.F90`
- [ ] Confirm the on-disk encoding matches the `NC_STRING` vector contract already decoded by `tests/_support/storage.py`

## 2. Verification

- [ ] Extend the wire-compat test in `tests/integration_tests/test_fortran_wire_compat.py` with the string-array metainfo scenario
- [ ] Run `pixi run verify` and confirm it is green
