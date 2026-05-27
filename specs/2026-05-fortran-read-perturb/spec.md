# Slice A-2: Read-perturb implementation

## Problem

The 5-arg `fs_read_field(..., perturb)` overloads exist so
pp_ser-emitted `CASE(2)` branches compile, but they `error stop` at
runtime. The perturbation algorithm itself is unimplemented.

## Goal

`fs_read_field(..., perturb=...)` returns field data perturbed by the
multiplicative noise scale `ppser_zrperturb`, matching Serialbox's
`zrperturb` semantics.

## Non-goals

- Widening `ppser_initialize` to accept `rperturb` from `!$SER INIT` —
  tracked as part of Slice D (open work).
- Read-mode validation / reference-store correctness — tracked as
  Slice A-1.
- Type-coverage expansion beyond `real64` — tracked as Slice B.

## Dependencies

**Depends on Slice D** (`pp_ser.py` port, open work). Read-perturb
sources its scale from `ppser_zrperturb`, which only becomes
runtime-controllable once Slice D's `rperturb` keyword threading
lands.

## Success criteria

- `fs_read_field` 5-arg overloads apply multiplicative noise scaled
  by `ppser_zrperturb` and return without `error stop`.
- The numerical algorithm matches Serialbox's `zrperturb` semantics
  (verified by porting Serialbox's reference test, or by reproducing
  a known-good output for at least one fixture).
- Cross-language test in `tests/integration_tests/` covering at
  least `real64` 3D end-to-end (Fortran writes, Fortran reads back
  with perturbation, Python reads the same store and asserts the
  expected perturbed values).
