# 4. Generate the Fortran field/metainfo overload matrix with CPP `#include` templates

## Status

Accepted

## Context

The preserf Fortran helper exposes generic interfaces (`fs_write_field`,
`fs_read_field`, `fs_add_savepoint_metainfo`, `fs_add_serializer_metainfo`,
and the 5-argument read-perturb form) that `pp_ser`-generated source resolves
by Fortran's generic-overload rules. Each concrete overload differs only by
the element **dtype** (`logical` / `integer(int32)` / `integer(int64)` /
`real(real32)` / `real(real64)`) and the **rank** (0D–4D) of its `data`
argument; the body — registry validation, dim/variable creation, the
`nf90_put_var` / `nf90_get_var` call — is otherwise identical.

Slice B (`specs/2026-05-fortran-type-coverage-matrix/`) takes the v0.1 helper,
which only implemented `real(real64)` at ranks 1D–3D plus scalar metainfo, up
to the full numeric matrix: 5 dtypes × 5 ranks = 25 write + 25 read field
overloads, 10 read-perturb overloads (the two floating dtypes × 5 ranks), and
1D-array metainfo overloads for every scalar type. Fortran has no generics or
templates, so the alternatives are:

1. **Hand-write every overload.** ~50 near-identical field subroutines plus
   metainfo/perturb variants — roughly 850 lines of boilerplate that drift
   out of sync the moment the shared body changes, and a large review surface
   for a mechanical change.
2. **A committed Python code-generation step** that emits a `.f90`. Keeps the
   native build plain, but adds a generator to maintain, a regenerate step to
   the workflow, and a generated artifact that can fall out of sync with its
   generator.
3. **CPP `#include` templates.** Keep one readable template body per
   operation in a `.inc` file and instantiate it with `#define` / `#include`
   / `#undef` stanzas. This is the idiomatic Fortran answer to a type×rank
   matrix (Serialbox itself preprocesses its helper with `fpp`).

The C preprocessor is already a build-time dependency for the **generated
e2e** source (`tests-fortran/e2e/CMakeLists.txt` compiles a `.F90` with
`-cpp -ffree-line-length-none`), but not for the shipped library, whose
sources are plain `.f90`. Adding `-cpp` to the library target is the
architectural change this ADR records.

## Decision

Generate the **field-I/O and read-perturb overload matrix** (the 25 write +
25 read field overloads, the 10 read-perturb overloads, and the 10
`apply_perturb` helpers) with **CPP `#include` templates**, compiled by
enabling the C preprocessor on the library target. The 1D-array metainfo
overloads and their `put_typed_array_attr` / `check_typed_array_attr` helpers
are **hand-written** in `m_preserf.F90` — there are only a handful and they do
not vary over rank, so a template would not pay for itself.

Concretely:

- Rename `src/preserf-fortran/m_preserf.f90` → `m_preserf.F90` (uppercase
  extension triggers gfortran's preprocessor) and add
  `-cpp -ffree-line-length-none` to the `preserf_fortran` GNU compile
  options, mirroring the existing e2e target. The re-export shims
  (`m_serialize.f90`, `utils_ppser.f90`) and `utils_preserf.f90` stay plain
  `.f90` — only `m_preserf.F90` is preprocessed.
- Each template body lives in a `preserf_*.inc` file beside `m_preserf.F90`
  (resolved by `#include "…"` relative to the including file, so no
  include-path configuration is needed).
- Every instantiation is an explicit stanza that `#define`s a `PRESERF_SUB`
  macro holding the **full, verbatim subroutine name** (e.g.
  `fs_write_field_i4_2d`) before the `#include`. This keeps every generated
  name greppable in source and avoids fragile `##` token-pasting; debugger
  and compiler diagnostics resolve to real line numbers inside the `.inc`.

## Consequences

- **Positive.** One body to maintain per operation; adding a dtype or rank is
  a few-line stanza. The matrix cannot drift internally. Generated names stay
  searchable. No new runtime dependency (the preprocessor is build-time only,
  already present in the toolchain).
- **Negative.** The library now depends on the C preprocessor at build time,
  and `m_preserf.F90` carries a long, repetitive block of
  `#define`/`#include`/`#undef` stanzas. Template `.inc` files are not
  self-contained Fortran (they only compile when included with the macros
  set), so they are not independently lintable; the explicit `PRESERF_SUB`
  names mitigate the loss of grep-ability for the bodies.
- **Scope.** This decision governs the Fortran helper only; `pp_ser` and the
  Python package are unaffected. It does not introduce a second backend or
  change the on-disk schema (`docs/references/storage_mapping.md`).
