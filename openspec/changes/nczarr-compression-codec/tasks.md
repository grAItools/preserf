# Tasks

Blocked on the NCZarr codec-plugin availability (see the
proposal's Blocked section). Tasks are drafted but not scheduled;
the unblocking condition is an environment where the codec plugins
resolve (`HDF5_PLUGIN_PATH` or bundled codecs).

## 1. Unblock verification

- [ ] 1.1 Establish and document an environment where the NCZarr codec plugins resolve; record the recipe

## 2. Implementation

- [ ] 2.1 Attach the Zarr codec via the NCZarr filter API on the field-write path
- [ ] 2.2 Remove or narrow the `ppser_initialize` rejection; update the abort message
- [ ] 2.3 Convert the `compression-nczarr*` negative ctest scenarios to positive round-trip scenarios

## 3. Documentation and verification

- [ ] 3.1 Update `storage_mapping.md` §9 with the codec path
- [ ] 3.2 Add the CHANGELOG bullet under `[Unreleased]`
- [ ] 3.3 Run `pixi run verify` and confirm it is green
