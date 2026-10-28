# Tasks

## 1. Decision record

- [ ] 1.1 Draft `dev/adr/0014-cross-savepoint-dedup.md` recording the storage-model decision (dictionary-encoding chosen; content-addressed blob pool as the recorded fallback)

## 2. Storage layout (opt-in)

- [ ] 2.1 Thread a dedup request from `ppser_initialize` through the write path (`m_preserf.F90`), default off
- [ ] 2.2 Implement the dictionary index inside the store; per-savepoint references resolve through it
- [ ] 2.3 Add native ctest scenarios asserting default stores stay one-dataset-per-write and dedup stores collapse identical payloads

## 3. Reader support

- [ ] 3.1 Teach `tests/_support/storage.py` to resolve per-savepoint dictionary references
- [ ] 3.2 Add a wire-compat scenario asserting a deduplicated store round-trips through the Python reader with identical values

## 4. Verification

- [ ] 4.1 Update `dev/references/storage_mapping.md` with the dedup layout
- [ ] 4.2 Add the CHANGELOG bullet under `[Unreleased]`
- [ ] 4.3 Run `pixi run verify` and confirm it is green
