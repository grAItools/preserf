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

- `fs_read_field` 5-arg overloads apply multiplicative noise
  `data*(1 + ppser_zrperturb*(2*r - 1))` (`r ~ U[0,1)`) and return
  without `error stop`; a zero scale is the identity.
- The algorithm matches Serialbox's `zrperturb` multiplicative-noise
  semantics. Because the RNG is left unseeded (intrinsic
  `RANDOM_NUMBER`, processor-dependent seed), correctness is verified
  by **bounds**, not exact values.
- Native Fortran ctest (`tests-fortran/unit/m_preserf`,
  `perturb-roundtrip`) covers `real64` 1D / 2D / 3D: write a field,
  re-open read-only, perturb-read it, and assert every element lands
  in `[orig*(1-|scale|), orig*(1+|scale|)]` with non-zero overall
  deviation, plus a scale-0 identity re-read per rank.

A cross-language test asserting *exact* perturbed values is
deliberately out of scope: perturbation is applied only in Fortran
memory, so the on-disk store stays unperturbed and a Python reader
cannot observe it without a deterministic, cross-language-reproducible
PRNG (which we chose not to introduce). Wire-compatibility of the
unperturbed store is already covered by
`tests/integration_tests/test_fortran_wire_compat.py`.
