# Tasks: add string-array-metainfo support

## 1. Runtime overload

- [ ] Add `fs_add_savepoint_metainfo_s_1d` and
      `fs_add_serializer_metainfo_s_1d` overloads to `m_preserf.F90`
- [ ] Choose and document the on-disk encoding in
      `docs/references/storage_mapping.md`

## 2. Round-trip support

- [ ] Teach `tests/_support/storage.py` to surface 1D string metainfo
- [ ] Add a native Fortran scenario writing a 2-element string-array metainfo

## 3. Verification

- [ ] Cross-language round-trip test in
      `tests/integration_tests/test_fortran_wire_compat.py`
- [ ] `pixi run verify` green
