# Tasks

## 1. Native tests (fail first)

- [x] 1.1 Add a ctest scenario where `fs_Option` with a verbosity below the int32 lower bound (for example −2⁴⁰ under a 64-bit default-integer build) aborts with the shared guard's message
- [x] 1.2 Add a ctest scenario where a registry-mismatched store is rejected on the k-buffer read path, mirroring the field path's message
- [x] 1.3 Add a ctest scenario asserting the friendly read-only message for `fs_write_field` on a read-only handle

## 2. Fixes

- [x] 2.1 Make both `require_fits_int32` copies check both bounds (`m_preserf.F90:2445-2455`, `utils_preserf.f90:260-271`)
- [x] 2.2 Route the k-buffer read path through registry validation before `kbuff_load_full` (`preserf_write_kbuff.inc:30-40`)
- [x] 2.3 Add the read-only-handle abort to the write template (`preserf_write_field.inc:16-27`)

## 3. Documentation

- [ ] 3.1 Reword the README's explicit-ref known-limitation bullet to state the native coverage (`src/preserf/fortran/README.md:99-101`)
- [ ] 3.2 Correct the e2e fixture header comment: the omission is a choice, not a linking constraint (`tests/fortran/e2e/e2e_fixture.f90.in:12-13`)

## 4. Verification

- [ ] 4.1 Add the CHANGELOG bullet under `[Unreleased]`
- [ ] 4.2 Run `pixi run verify` and confirm it is green
