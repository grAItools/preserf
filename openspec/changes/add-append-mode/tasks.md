# Tasks: add append mode

## 1. Runtime behavior

- [ ] Add an append-mode native test that writes, closes, re-opens with `mode='a'`, appends, and reads back
- [ ] Implement group enumeration to scan existing `sp_NNNNNN` savepoint groups in `utils_preserf.f90`
- [ ] Resume `next_sp_index` from the scanned maximum and validate contiguity
- [ ] Sanity-check `_preserf_*` housekeeping attributes on open and abort on disagreement
- [ ] Replace the `mode='a'` rejection in `preserf_open_serializer` with the append path

## 2. Verification

- [ ] Update the known-limitations list in `src/preserf/fortran/README.md`
- [ ] Run `pixi run verify` and confirm it is green
