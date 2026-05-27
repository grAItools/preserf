# preserf specs

Per-feature spec directories under
`specs/<YYYY-MM>-<slug>/`, each closing one gap left
in the v0.1 Fortran helper that shipped in
[#4](https://github.com/grAItools/preserf/pull/4). Two files per
spec dir: `spec.md` (WHAT and WHY, per
[`.agents/commands/spec.md`](../.agents/commands/spec.md)) and
`plan.md` (phased plan, per
[`.agents/commands/plan.md`](../.agents/commands/plan.md)). The
single-letter slice labels (A-1, A-2, B, C, D, E, G) used in the
progress table below and across the spec prose are historical labels
that originated in PR #4's gap analysis; they bridge cross-references
in ADRs and CHANGELOG entries to the rename-able spec dirs. Slice C-0
is ADR-only and lands directly as `docs/adr/0003-tracer-storage.md`
when work begins; Slice F shipped via [#14](https://github.com/grAItools/preserf/pull/14)
and [#15](https://github.com/grAItools/preserf/pull/15); Slice B′
(string data fields) is deferred past v1.0 and no spec exists yet.

## Progress at a glance

| Slice | Title                                                                        | Status        | Tracking PR(s) |
| ----- | ---------------------------------------------------------------------------- | ------------- | -------------- |
| A-1   | [Read-mode resolve-and-validate](2026-05-fortran-read-mode/)                 | planned       | —              |
| A-2   | [Read-perturb implementation](2026-05-fortran-read-perturb/)                 | planned       | —              |
| B     | [Full type-coverage matrix (numeric)](2026-05-fortran-type-coverage-matrix/) | planned       | —              |
| B′    | String data fields                                                           | deferred      | —              |
| C-0   | ADR: tracer descriptor storage (lands as `docs/adr/0003-tracer-storage.md`)  | planned       | —              |
| C     | [Tracers, k-buffer, OPTION](2026-05-fortran-tracers-kbuff-option/)           | planned       | —              |
| D     | [pp_ser.py port — open work](2026-05-preprocessor-port-open-work/)           | partial       | #6 (core)      |
| E     | [Backend selector + NCZarr URL targets](2026-05-fortran-backend-selector/)   | planned       | —              |
| F     | CI for the Fortran build                                                     | shipped       | #14, #15       |
| G     | [Append mode](2026-05-fortran-append-mode/)                                  | deferred-v1.0 | —              |

Update this table on every slice-PR merge — single source of truth for
"where are we", with per-spec detail in each linked dir.

## Cross-slice dependencies

Non-obvious orderings to land specs in:

- **A-2 depends on D** — read-perturb sources its scale from
  `ppser_zrperturb`, which only becomes runtime-controllable once
  Slice D's `rperturb` keyword threading lands.
- **C depends on C-0** — the tracer-storage ADR must accept before
  the tracer API (C) commits to a layout.
- **E depends on D** — the `backend` keyword threads through
  `ppser_initialize` alongside D's other widened keywords; landing E
  first would require touching the same signature twice.
- A-1, B, and G are independent of each other and of D.

## v1.0 — Definition of Done

The roadmap should cut a v1.0 of `preserf-fortran` when all of the
following hold:

1. Slices A-1, A-2, B, C-0, C, D (full), and E have landed on `main`.
2. `tests/integration_tests/test_fortran_wire_compat.py` parametrises
   over the full (rank × dtype × backend) matrix and passes in CI
   with `PRESERF_REQUIRE_FORTRAN=1`.
3. The native Fortran test exercises at least one read-mode
   round-trip per shipped slice (A-1 read-back, A-2 perturb-read, B
   type matrix, C tracer write+read).
4. No `error stop` remains as a stub in `src/preserf-fortran/` —
   every compile-only overload either has an implementation or has
   been removed.
5. The `_preserf_*` housekeeping attributes documented in
   `docs/references/storage_mapping.md` §1 round-trip without drift
   between writer and reader.

**Explicitly deferred past v1.0:** Slice B′ (string data fields) and
Slice G (append mode); both are documented as low-priority today and
should not block a v1.0 cut. If demand emerges, they ship as v1.1.
B′ has no spec dir yet; G's spec exists so the work is captured but
is marked deferred.

## Out of scope (any release)

- A second backend implementation (e.g. native HDF5, native Zarr
  without going through netcdf-c). The whole point of the schema is
  that one Fortran helper produces both NetCDF4 and NCZarr.
- Distributed / MPI-aware writes beyond what Serialbox itself
  supported. The `mpi_rank` keyword that Slice D wires up only
  controls the `_rank<n>` suffix on the store name (one independent
  store per rank, per `docs/references/storage_mapping.md` §9);
  parallel HDF5 / parallel NCZarr is a future option, not part of
  this spec set.
- A C API. pp_ser only generates Fortran.

## Spec-set tech debt

Advisory items from the [#4](https://github.com/grAItools/preserf/pull/4)
Copilot review that fold into specific slice plans (rather than
opening their own specs):

- Negative test for write-side registry validation mismatched
  dtype / dims → A-1 Phase 3.
- Negative test for read-side `require_variable_xtype` rejection →
  A-1 Phase 3.
- Savepoint-metainfo native coverage limited to `int32` / `real64` →
  subsumed by B Phase 3 (parametrised matrix).
- `next_sp_index` / `sp_000001` naming not exercised end-to-end →
  A-1 Phase 3.
- Disabled-savepoint round-trip checks `grpid` and `idx` but not
  `owner_ncid` → A-1 Phase 3.
