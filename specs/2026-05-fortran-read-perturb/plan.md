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

- Native Fortran scenario (`perturb-roundtrip`): write `real64`
  1D / 2D / 3D fields, re-open read-only, perturb-read each with a
  known scale, and assert every element lands within
  `[orig*(1-|scale|), orig*(1+|scale|)]` with non-zero overall
  deviation; a scale-0 re-read is the identity per rank.
- A cross-language exact-value test is out of scope (unseeded RNG;
  perturbation is in-memory only, so the on-disk store is
  unperturbed). See `spec.md` for the rationale.

**Exit criteria.** `perturb-roundtrip` passes under
`pixi run test-fortran` with `PRESERF_REQUIRE_FORTRAN=1`; the
`error stop` is gone from the 5-arg overloads.
