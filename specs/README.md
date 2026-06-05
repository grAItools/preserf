# preserf specs

Per-feature spec directories live under `specs/<YYYY-MM>-<slug>/`. Each
captures one feature or change. The files in a spec dir accumulate as it moves
through the workflow — only `spec.md` exists up front; the later phases add the
rest (`.agents/commands/spec.md` deliberately does not pre-create them):

- `spec.md` — WHAT and WHY, no implementation detail; written by `/spec`
  (per [`.agents/commands/spec.md`](../.agents/commands/spec.md)).
- `plan.md` — numbered, phased plan with per-phase tests; added by `/plan`
  (per [`.agents/commands/plan.md`](../.agents/commands/plan.md)).
- `tasks.md` — checkbox list mirrored from `plan.md`; added by `/plan`,
  then ticked off by the developer during `/build`.
- `scratch.md` — developer working notes; created during `/build` as needed,
  gitignored, cleared on completion.

In practice a dir carries only the artifacts its work has reached, and the
layout has evolved — most of the `2026-05-*` specs retain just
`spec.md` + `plan.md`, so don't expect all four files in every dir.

These dirs are produced and consumed by the four-phase loop
`/spec` → `/plan` → `/build` → `/verify`; see `.agents/commands/` and
[`AGENTS.md`](../AGENTS.md) for the full workflow.

> **Historical note.** The v0.1 Fortran helper was built out as a set of
> single-letter implementation "slices" (A–G) tracked from this file with a
> progress table, cross-slice dependency ordering, and a v1.0
> Definition-of-Done sign-off. That initial roadmap has landed, so the
> per-slice tracking has been retired. The individual shipped spec dirs
> (`2026-05-fortran-*`) remain in place as the record of what was built;
> ADR and CHANGELOG entries that still reference the old slice labels point
> back to them.

## Pending / future work

- [Fortran distribution + CMake helper](2026-06-fortran-distribution/) —
  specced, not yet planned or built. Ship the Fortran runtime sources inside
  the wheel together with a CMake configuration helper so installed users can
  compile preserf-generated Fortran without cloning the repo.
- [Append mode](2026-05-fortran-append-mode/) — deferred past v1.0. Spec
  captured so the work is recorded; low priority, ships if demand emerges.
- **String data fields** — deferred past v1.0. No spec dir yet; open one when
  the work is picked up.

## Out of scope (any release)

- A second backend implementation (e.g. native HDF5, or native Zarr without
  going through netcdf-c). The whole point of the schema is that one Fortran
  helper produces both NetCDF4 and NCZarr.
- Distributed / MPI-aware writes beyond what Serialbox itself supported. The
  `mpi_rank` keyword only controls the `_rank<n>` suffix on the store name
  (one independent store per rank, per
  `docs/references/storage_mapping.md` §9); parallel HDF5 / parallel NCZarr is
  a possible future option, not part of this spec set.
- A C API. preserf only generates Fortran.
