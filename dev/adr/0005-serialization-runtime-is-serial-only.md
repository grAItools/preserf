# 5. The Fortran serialization runtime is serial-only (not thread-safe)

## Status

Accepted

## Context

The preserf Fortran helper keeps `save`d, module-level mutable state that
`pp_ser`-expanded `!$SER` directives mutate without any synchronization:

- `ppser_serializer`, `ppser_serializer_ref`, `ppser_savepoint`
  (`src/preserf/fortran/utils_preserf.f90`).
- `serialisation_enabled` — the on/off gate read by every `fs_*` entry point.
- `ppser_tracers` and its count (`!$SER TRACER` registry).
- `ppser_kbuffers` and its count (`!$SER DATA_KBUFF`).
- The intrinsic `RANDOM_NUMBER` generator state used by the read-perturb
  path (`preserf_apply_perturb.inc`).

`!$SER` directives routinely appear inside OpenMP parallel regions in host
models (ICON and similar). Concurrent `!$SER DATA` from multiple threads
would race on all of the above — the serializer/savepoint structs, the
enable flag, the tracer/k-buffer registries, and the shared RNG. Neither
`src/preserf/fortran/README.md` nor the module headers stated any threading
constraint, so a downstream user had no way to know the API is serial-only
(graitools/preserf#73).

The open question driving this decision: **is `!$SER` usage inside OpenMP
parallel regions in scope for downstream hosts?** That determines whether
documenting the constraint suffices or whether the runtime needs real
synchronization (a lock around serializer mutation, a thread-local
perturbation RNG).

## Decision

**The serialization runtime is serial-only.** Running `!$SER` from within
an OpenMP parallel region is **out of scope** for the current helper. The
contract is: `!$SER` directives must be executed from serial regions only,
or guarded so that at most one thread serializes at a time (e.g. an
`!$omp critical` / `!$omp master` around the directive in the host model).

We record this constraint rather than implement synchronization because:

- The reference serialization workflow (Serialbox) is itself driven from
  serial regions; there is no filed downstream requirement for in-region,
  multi-threaded serialization against preserf.
- Real thread-safety is a non-trivial design effort — every shared mutable
  symbol above needs a lock or thread-local replacement, including the
  shared `RANDOM_NUMBER` state — and would be premature while the helper is
  still closing basic write-mode gaps.
- Documenting the boundary is the simplest correct closure and is what the
  issue's acceptance criteria call for.

The constraint is stated in three places so a downstream user meets it
wherever they enter the code: `src/preserf/fortran/README.md`, the
`m_preserf` module header (`m_preserf.F90`), and the `utils_preserf` module
header (`utils_preserf.f90`).

## Consequences

- **Positive.** The threading contract is explicit and discoverable. A
  downstream host integrating `!$SER` knows to keep it serial or to guard it,
  avoiding a silent data race that would corrupt the store or the perturb
  sequence.
- **Negative.** Hosts that want serialization from inside a parallel region
  must add their own guard, which serializes that region and may perturb
  performance characteristics during a debug/serialize run.
- **Revisiting.** If a downstream host establishes a concrete need for
  thread-safe in-region serialization, file a follow-up to add real
  synchronization (lock around serializer/savepoint/registry mutation,
  thread-local perturbation RNG) and supersede this ADR. This decision does
  not change the on-disk schema or any runtime behaviour — it is a
  documentation-and-contract decision only.
