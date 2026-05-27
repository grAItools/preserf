# Slice A-2 plan: Read-perturb implementation

## Phase 0 — Wait for Slice D's `rperturb` threading

Slice A-2 cannot land in isolation; the perturbation scale lives in
the module-level `ppser_zrperturb`, which is only runtime-controllable
once Slice D (`pp_ser.py` port open work) threads the `rperturb`
keyword from `ppser_initialize` into that variable. Pick this slice up
after Slice D's `ppser_initialize` widening lands.

## Phase 1 — Implement the perturbation algorithm

**Scope.** Replace the `error stop` in the 5-arg `fs_read_field`
overloads with the multiplicative-noise algorithm matching
Serialbox's `zrperturb` semantics.

**Steps.**

1. Locate the existing 5-arg overloads in `src/preserf-fortran/m_preserf.f90`
   (currently compile-only stubs).
2. Port the `zrperturb` algorithm from Serialbox (multiplicative
   noise scaled by `ppser_zrperturb`). If Serialbox's reference test
   is portable, port that as the validation fixture.
3. Decide RNG strategy and document it (likely a deterministic seed
   per call site so tests are reproducible).

**Tests.**

- Cross-language test in
  `tests/integration_tests/test_fortran_wire_compat.py` (or a
  sibling): Fortran writes a `real64` 3D field, Fortran reads it back
  with `perturb=...`, Python reads the same store and asserts the
  perturbed values match the algorithm's expected output for the
  given scale.
- Native Fortran scenario: write + perturb-read round-trip with a
  known scale, asserting non-zero deviation from the original and
  matching the algorithm's expected pattern.

**Exit criteria.** Cross-language `real64` 3D perturb-read passes in
CI with `PRESERF_REQUIRE_FORTRAN=1`; the `error stop` is gone from
the 5-arg overloads.
