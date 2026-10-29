# Tasks

## 1. Measurement prerequisites (fail first)

- [ ] 1.1 Add a perf-smoke fixture writing a representative large field through both backends for the default-off baseline, asserting file size and read wall-time; the compressed "after" measurement is netcdf4-only until the nczarr codec follow-up (#111) lands
- [ ] 1.2 Add a perturb-mode timing fixture large enough that per-element versus batched drawing is distinguishable

## 2. Storage layout (opt-in)

- [ ] 2.1 Draft `dev/adr/0013-opt-in-store-compression.md` recording the storage-layout decision
- [ ] 2.2 Thread the store-wide compression request (`ppser_initialize` keyword + `PRESERF_COMPRESSION` env var) through `ensure_variable` (`m_preserf.F90:3582-3597`), default off, with a chunk shape derived from the registered dims and bounded (not whole-variable; no chunk may exceed the HDF5 4 GiB per-chunk limit); keep the per-field registration-API override as an explicit follow-up
- [ ] 2.3 Add native ctest scenarios asserting default stores remain contiguous, scalar fields stay contiguous under compression, compressed stores carry a bounded (not whole-variable) chunk shape, and compressed stores round-trip through the Python support reader

## 3. Perturb RNG batching

- [ ] 3.1 Rework `preserf_apply_perturb.inc:29-66` to draw in bounded chunks (one `random_number(chunk)` per chunk) while preserving the documented formula and bounds
- [ ] 3.2 Add a ctest scenario asserting batched drawing preserves the multiplicative bounds

## 4. Verification

- [ ] 4.1 Add the CHANGELOG bullet under `[Unreleased]`
- [ ] 4.2 Run `pixi run verify` and confirm it is green
