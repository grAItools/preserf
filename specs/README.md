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

| Slice | Title                                                                        | Status        | Tracking PR(s)                      |
| ----- | ---------------------------------------------------------------------------- | ------------- | ----------------------------------- |
| A-1   | [Read-mode resolve-and-validate](2026-05-fortran-read-mode/)                 | shipped       | —                                   |
| A-2   | [Read-perturb implementation](2026-05-fortran-read-perturb/)                 | shipped       | —                                   |
| B     | [Full type-coverage matrix (numeric)](2026-05-fortran-type-coverage-matrix/) | shipped       | —                                   |
| B′    | String data fields                                                           | deferred      | —                                   |
| C-0   | ADR: tracer descriptor storage (`docs/adr/0003-tracer-storage.md`)           | shipped       | —                                   |
| C     | [Tracers, k-buffer, OPTION](2026-05-fortran-tracers-kbuff-option/)           | shipped       | —                                   |
| D     | [pp_ser.py port — open work](2026-05-preprocessor-port-open-work/)           | shipped       | #6 (core); open work landed via #21 |
| E     | [Backend selector + NCZarr URL targets](2026-05-fortran-backend-selector/)   | shipped       | —                                   |
| F     | CI for the Fortran build                                                     | shipped       | #14, #15                            |
| G     | [Append mode](2026-05-fortran-append-mode/)                                  | deferred-v1.0 | —                                   |

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
   over the full (rank × dtype) matrix plus a representative
   cross-backend scenario, and passes in CI with
   `PRESERF_REQUIRE_FORTRAN=1`. (A literal rank × dtype × backend
   cross-product is deferred to v1.1 hardening — see the sign-off below
   for the rationale.)
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

### v1.0 DoD sign-off (2026-06-02)

All five criteria are met; the release is ready to cut once the version
label (`pyproject.toml`) and a `CHANGELOG.md` entry are added — those two
steps are intentionally held back from this sign-off.

1. **All slices landed** — ✅ A-1, A-2, B, C-0, C, D (full), E are all
   `shipped` in the table above; only B′ and G remain, both deferred by
   design. Slice D's open work landed via #21
   (`ppser_initialize` widened + wired in
   `src/preserf-fortran/utils_preserf.f90:308-453`).
2. **Wire-compat matrix** — ✅ the 25-field `rank × dtype` matrix is
   parametrised in
   `tests/integration_tests/test_fortran_wire_compat.py:736-737`. The
   `backend` axis is covered by the representative `backend-nczarr`
   scenario (same file, ~L256-283): the helper is a single writer that
   emits the same group-per-savepoint schema to both NetCDF4 and
   NCZarr, so one full-matrix backend plus a representative cross-backend
   scenario exercises the on-disk contract. A literal
   `rank × dtype × backend` cross-product is a possible v1.1 hardening,
   not a v1.0 blocker.
3. **Native read-mode round-trip per slice** — ✅
   `tests-fortran/unit/m_preserf/test_minimal.f90` exercises
   `read-roundtrip` (A-1, L287), `perturb-roundtrip` (A-2, L333),
   `type-matrix` / `wire-matrix` (B, L542/L696), and `tracers-roundtrip`
   (C, L870).
4. **No `error stop` stub** — ✅ every `error stop` in
   `src/preserf-fortran/` is a genuine runtime-validation path
   (unsupported rank, unsupported `nc_type`, schema-version mismatch);
   no compile-only overload stub remains.
5. **`_preserf_*` housekeeping round-trips** — ✅ asserted end-to-end by
   `tests/integration_tests/test_preprocessor_e2e.py` (Slice D Phase 3).

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
