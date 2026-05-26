---
status: active
date: 2026-05-26
owners: preserf maintainers
related:
  - development/decisions/0001-storage-model-mapping.md
  - development/references/storage_mapping.md
  - development/references/directives_specification.md
  - src/preserf-fortran/README.md
---

# Fortran helper module — implementation roadmap

This document tracks the slices that take `src/preserf-fortran/` from the
v0.1 write-mode subset (merged in PR #4) to a complete drop-in replacement
for the Serialbox Fortran helpers that `pp_ser`-generated source links
against. It is descriptive, not prescriptive — each slice still needs its
own design review when it lands.

## Progress at a glance

| Slice | Title                                      | Status   | Tracking PR(s) |
| ----- | ------------------------------------------ | -------- | -------------- |
| A-1   | Read-mode resolve-and-validate             | planned  | —              |
| A-2   | Read-perturb implementation                | planned  | —              |
| B     | Full type-coverage matrix (numeric)        | planned  | —              |
| B′    | String data fields                         | deferred | —              |
| C-0   | ADR: tracer descriptor storage             | planned  | —              |
| C     | Tracers, k-buffer, OPTION                  | planned  | —              |
| D     | pp_ser.py port + ppser_initialize widening | partial  | #6 (core)      |
| E     | Backend selector + NCZarr URL targets      | planned  | —              |
| F     | CI for the Fortran build                   | shipped  | #14, #15       |
| G     | Append mode                                | planned  | —              |

Update this table on every slice-PR merge — it is the single source of
truth for "where are we", with the section-level prose providing detail.

## 1. What is already shipped

Already on `main`:

- **PR #3 — storage mapping**
  (`development/references/storage_mapping.md`, plus the
  `tests/_support/storage.py` / `tests/_support/serialbox.py` reference reader and a
  Serialbox ↔ preserf Python round-trip test).
- **PR #4 — minimal Fortran helper** (`src/preserf-fortran/`):
  - `utils_preserf.f90` — lifecycle (`ppser_initialize` /
    `ppser_finalize` / `ppser_set_mode` / `ppser_get_mode`) and the
    module-level state pp_ser-emitted code uses (`ppser_serializer`,
    `ppser_serializer_ref`, `ppser_savepoint`, `ppser_intlength`,
    `ppser_reallength`, `ppser_realtype`, `ppser_zrperturb`).
  - `m_preserf.f90` — `fs_register_field`, `fs_create_savepoint`,
    `fs_add_savepoint_metainfo` / `fs_add_serializer_metainfo`
    (scalar `logical` / `int32` / `int64` / `real32` / `real64` /
    `character`), `fs_write_field` / `fs_read_field` for `real64`
    1D/2D/3D (4-arg and compile-only 5-arg perturb form),
    `fs_enable_serialization` / `fs_disable_serialization` /
    `fs_serialization_status`.
  - `m_serialize` / `utils_ppser` alias modules so pp_ser-generated
    source using the historical Serialbox module names compiles
    unchanged.
  - `src/preserf-fortran/CMakeLists.txt` (CMake 3.20+,
    `pkg-config` discovery of `netcdf-fortran`, `Fortran_STANDARD
    2008` plus an explicit gfortran `-std=f2008`, project version
    threaded via `preserf_version.f90.in`); the native-test build is
    driven from `tests-fortran/CMakeLists.txt` (with per-suite config
    at `tests-fortran/unit/m_preserf/CMakeLists.txt`).
  - `tests-fortran/unit/m_preserf/test_minimal.f90` native Fortran
    test + `tests/integration_tests/test_fortran_wire_compat.py`
    cross-language wire-compat test (skips when the Fortran binary is
    absent).

The schema documented in
[`storage_mapping.md`](../references/storage_mapping.md) is now exercised
by both a Python writer (`tests/_support/storage.py`) and a Fortran writer
(`src/preserf-fortran/`).

Hardening that has landed since PR #4:

- **PR #16** — `require_fits_int32` guard in `active_dims_c_order` /
  `put_halo_attr` closes a latent truncation on very large dim sizes /
  halo extents.
- **PR #17** — test reorganization into `tests/unit_tests/`,
  `tests/integration_tests/`, and `tests-fortran/unit/m_preserf/`; all
  path references in this roadmap reflect that layout.

## 2. Known gaps after PR #4

These are gaps in the current shipped code, not future enhancements.
They are the things pp_ser-generated source can already hit today.

1. **Read mode is structurally partial.** `fs_register_field`,
   `fs_create_savepoint`, `fs_add_savepoint_metainfo` and
   `fs_add_serializer_metainfo` unconditionally **create** their
   netCDF objects. pp_ser-generated source calls these directives
   _outside_ the `SELECT CASE (ppser_get_mode())` that gates DATA
   blocks, so pointing a generated read run at an existing read-only
   store aborts at the first create call — `fs_register_field`'s
   `nf90_def_var` on the registry carrier, or `fs_create_savepoint`'s
   `nf90_def_grp(sp_NNNNNN)`, whichever the generated source reaches
   first. Additionally, the read
   path validates the registry on `s%fields_grpid` but pulls the data
   variable from `sp%grpid` — `ppser_savepoint` lives on
   `ppser_serializer` rather than `ppser_serializer_ref`, so an
   _explicit_ reference store would validate against one file and
   read from another.
2. **Read-perturb is a stub.** The 5-arg
   `fs_read_field(..., perturb)` overloads exist so pp_ser-emitted
   `CASE(2)` branches compile, but `error stop` at runtime. The
   perturbation algorithm itself is unimplemented.
3. **`ppser_initialize` keyword surface is narrower than Serialbox's.**
   v0.1 takes `directory`, `prefix`, `mode`, `directory_ref`,
   `prefix_ref`. Serialbox accepts additional `singlefile`,
   `mpi_rank`, `rprecision`, `rperturb`, `realtype`, `archive`,
   `unique_id`. pp_ser passes those through verbatim from
   `!$SER INIT` directives.
4. **Append mode (`'a'`) is rejected**, not half-implemented.
5. **Type-coverage matrix is `real64`-only for fields, scalar-only
   for metainfo.** No `bool` / `int32` / `int64` / `float32` field
   overloads, no 0D or 4D field overloads, no array-metainfo
   variants of _any_ type — `fs_add_savepoint_metainfo` and
   `fs_add_serializer_metainfo` only have scalar overloads
   (`_l` / `_i4` / `_i8` / `_r4` / `_r8` / `_s`); 1D-array overloads
   are part of Slice B. **String data fields** (Serialbox
   `TypeID::String` for data, not metainfo) are also not supported —
   see `storage_mapping.md` §9 "String data fields" — and there is
   no `NF90_STRING` write path for field variables yet. _Scalar_
   string metainfo is supported (both reference writers produce
   `NC_CHAR`); _array_ string metainfo is supported by the Python
   reference writer (as `NC_STRING`) but not by the Fortran helper
   in v0.1 (per `storage_mapping.md` §1's String-storage note).
6. **No tracer / k-buffer / OPTION support.** `!$SER TRACER`,
   `!$SER DATA_KBUFF`, `!$SER OPTION` would fail to link.
7. **NCZarr targets unreachable.** `preserf_open_serializer` builds
   `<directory>/<prefix>.nc` and passes `NF90_NETCDF4`. No backend
   selector at the `ppser_initialize` boundary.
8. **No CI for the Fortran build.** `tests/integration_tests/test_fortran_wire_compat.py`
   skips by default; nothing on `main` blocks a Fortran regression.

## 3. Slice plan

Each slice is intended to land as one PR. Slices are roughly ordered
by how much they unblock real pp_ser-generated source. They are not
strictly sequential — Slice B can land before or after the Slice A
sub-slices.

**Cross-slice dependencies (non-obvious):**

- **A-2 depends on D** — read-perturb sources its scale from
  `ppser_zrperturb`, which only becomes runtime-controllable once
  Slice D's `rperturb` keyword threading lands.
- **C depends on C-0** — the tracer storage ADR (C-0) must accept
  before the tracer API (C) commits to a layout.
- **E depends on D** — the `backend` keyword threads through
  `ppser_initialize` alongside the other widened keywords; landing E
  first would require touching the same signature twice.
- A-1, B, and G are independent of each other and of D.

### Slice A-1 — Read-mode "create-or-resolve-and-validate"

Closes gap §1.

- Switch `fs_register_field`, `fs_create_savepoint`,
  `fs_add_savepoint_metainfo`, `fs_add_serializer_metainfo` to a
  create-or-resolve-and-validate shape: on a writable store they
  create as today; on a read-only store they resolve the existing
  group/var/attr and validate that the runtime arguments match.
  Specifically:
  - `fs_register_field`: type, dims, halos must match the
    `/_fields/<name>` registry entry.
  - `fs_create_savepoint`: the runtime `name` argument must match the
    existing savepoint group's `name` attribute (per
    `storage_mapping.md` §5 — savepoints are identified by index
    `sp_NNNNNN` _plus_ the `name` attribute, since Serialbox permits
    multiple savepoints to share a name and they're disambiguated by
    metainfo).
  - metainfo helpers: value plus `__preserf_type_id` must match the
    existing attribute.

  Mismatch aborts with a clear error.
- Resolve the `ppser_serializer` vs `ppser_serializer_ref`
  savepoint-grpid mismatch: either savepoints carry per-serializer
  grpids, or `fs_read_field` re-resolves the savepoint under `s`
  before reading. Pick one in the design notes; the second is less
  state but more I/O.
- Add a native Fortran test that round-trips a write run and then a
  read run against the same store, exercising the resolve+validate
  branch end-to-end. Add a _second_ scenario that uses an explicit
  `directory_ref`/`prefix_ref` pair pointing at a different store
  (or otherwise deliberately mismatched `s` / `sp` pairing) so the
  `ppser_serializer` vs `ppser_serializer_ref` savepoint-grpid case
  is actually covered — the same-store round-trip alone hits the
  implicit-ref path.

### Slice A-2 — Read-perturb implementation

Closes gap §2's runtime side.

**Depends on Slice D's `rperturb` keyword threading reaching
`ppser_zrperturb`**, since the perturb scale is sourced from that
module-level variable.

- Implement read-perturb (5-arg `fs_read_field`). Algorithm matches
  Serialbox's `zrperturb` semantics (multiplicative noise scaled by
  `ppser_zrperturb`). Cross-language test covering at least `real64`
  3D.

### Slice B — Full type-coverage matrix

Closes gap §5.

- `fs_register_field` already takes a generic `type` string, so the
  registry side is mostly there. The field write/read overloads need
  to be filled out: `logical`, `integer(int32)`, `integer(int64)`,
  `real(real32)`, `real(real64)` × 0D / 1D / 2D / 3D / 4D.
- Array-metainfo overloads (`fs_add_savepoint_metainfo` /
  `fs_add_serializer_metainfo` for 1D arrays of each scalar type,
  per Serialbox `MetainfoValue::Array`).
- **String data fields are explicitly deferred** to a separate slice
  (call it Slice B′). Storage mapping §9 says `TypeID::String` for
  data lands as `NF90_STRING` variables under the same
  group-per-savepoint layout, with no schema-version bump expected,
  but the Python reference reader (`numpy_dtype_for` in
  `tests/_support/serialbox.py`, imported by `tests/_support/storage.py`) currently
  rejects the type and there's no `NF90_STRING` write path in
  `fs_write_field`. Bundling it into
  Slice B would expand scope; tracking it separately keeps the
  primary numeric matrix tractable.
- The cross-language test (`tests/integration_tests/test_fortran_wire_compat.py`) grows a
  parametrised matrix: for each (rank, dtype), assert raw netCDF
  type via `Dataset[…].dtype` matches the TypeID → netCDF-type table
  in `storage_mapping.md §1`.

### Slice C-0 — ADR: tracer descriptor storage

Docs-only prelude to Slice C. Splits the schema decision out of the
implementation PR so layout review and code review can run on
independent change-sets.

- Decide where tracer descriptors live in the store. Candidate is a
  `/_tracers` sibling of `/_fields`; the ADR should weigh that against
  inlining descriptors into the existing `/_fields` registry.
- Decide what attribute set identifies a tracer (name, dtype, units,
  the Serialbox tracer flags).
- Land as `development/decisions/0002-tracer-storage.md` following
  the template at `development/decisions/adr-template.md`.
- Update `development/references/storage_mapping.md` once the ADR is
  accepted, before Slice C opens.

### Slice C — Tracers, k-buffer, OPTION

Closes gap §6. **Depends on Slice C-0** (tracer storage ADR).

- `fs_RegisterAllTracers` (from `!$SER REGISTERTRACERS`) and the
  tracer write API — `ppser_write_tracer_by_name`,
  `ppser_write_tracer_by_idx`, `ppser_write_tracer_all` (from
  `!$SER TRACER`, per
  `development/references/directives_specification.md` §§3.11 / 3.14).
  Implementation follows the layout ratified in Slice C-0's ADR.
- `fs_write_kbuff` (`!$SER DATA_KBUFF`). Needs the k-buffer flush
  semantics from `pp_ser.py` to be re-derived.
- `fs_Option` (`!$SER OPTION`). pp_ser emits OPTION entries as
  Fortran keyword arguments (e.g. `call fs_Option(verbosity=1)`)
  rather than as a `(name, value)` pair, so this slice must first
  define the supported `fs_Option` optional-argument surface (or
  change the pp_ser port's emission shape) before deciding how
  options land in the store.
- All three need cross-language coverage in
  `tests/integration_tests/test_fortran_wire_compat.py` (or a sibling test program).

### Slice D — `pp_ser.py` port

Independent of slices A–C; can land in parallel.

**Status:** partial — the preprocessor port has landed (PR #6); the
`ppser_initialize` widening and the end-to-end test remain.

**Done (PR #6).**
`pp_ser.py` (a reference file under `development/references/`) is
ported into the distributed Python package as
`src/preserf/preprocessor.py` — a typed, two-pass reimplementation
expanding every `!$SER` directive — alongside `errors.py`
(`DirectiveError` with file/line context) and a real `cli.py`
(single-file, output-dir and recursive modes). Generated output uses
preserf's helper API (`USE m_serialize` / `utils_ppser`).
Directive-by-directive unit tests live in
`tests/unit_tests/test_preprocessor.py` and
`tests/unit_tests/test_cli.py`; deviations from the reference (all
toward correctness) are enumerated in the PR description.

**Open.**

- Widen `ppser_initialize` to accept the keyword surface pp_ser
  emits (gap §3): `singlefile`, `mpi_rank`, `rprecision`,
  `rperturb`, `realtype`, `archive`, `unique_id`. Several of these
  are _not_ purely metadata:
  - `mpi_rank`: per `storage_mapping.md` §9, this maps to a
    `_rank<n>` suffix on the store name. `preserf_open_serializer`
    must apply the suffix, otherwise parallel runs would clobber
    each other's stores.
  - `realtype` and `rprecision`: pp_ser-generated REGISTER calls
    pass `ppser_realtype` / `ppser_reallength` for `real` fields
    (see `pp_ser.py` "datatypes" map). The helper currently exposes
    those as fixed constants; the port must let `ppser_initialize`
    update them so single-precision real fields get registered with
    the right type metadata. `rperturb` threads through to the
    read-perturb path from Slice A-2 (which depends on this work).
  - `singlefile`, `archive`, `unique_id`: metadata-only on the
    preserf side; record them in root attrs for round-trip fidelity.
- End-to-end test: run the ported preprocessor on a representative
  `!$SER`-annotated Fortran source, compile the generated output
  against preserf's helpers, run it, and read the store back with
  `tests/_support/storage.py`.

### Slice E — Backend selector and NCZarr URL targets

Closes gap §7.

- Add a backend selector at `ppser_initialize`
  (`backend='netcdf4'|'nczarr-v2'`, default `netcdf4`). The
  `nczarr-v2` label matches the selector already used by the Python
  reference path (`tests/_support/storage.py`).
- Rework `preserf_open_serializer` to construct
  `file://<directory>/<prefix>.zarr#mode=nczarr,zarr2` when the
  backend is NCZarr, and pass appropriate creation flags.
- Cross-language test wiring `tests/_support/storage.py`'s Zarr V2 reader
  against a Fortran-written NCZarr store. This test exists today on
  the Python side (`tests/unit_tests/test_storage_round_trip.py`) for
  both the `netcdf4` and `nczarr-v2` backends; extend it to also
  accept Fortran-written input.
- Zarr V3 (NCZarr V3 PR) explicitly deferred until the netcdf-c PR
  lands. See `development/decisions/0001-storage-model-mapping.md`.

### Slice F — CI for the Fortran build

Closes gap §8. **Status:** landed.

- GitHub Actions workflow `.github/workflows/ci.yml` runs on
  `ubuntu-latest` and provisions the toolchain via pixi (no raw
  `apt install` — the base pixi environment already declares
  `fortran-compiler` and `netcdf-fortran`, and the `dev` feature adds
  `cmake`). The workflow runs `pixi run build-fortran`,
  `pixi run test-fortran`, then `pixi run verify` with
  `PRESERF_REQUIRE_FORTRAN=1` exported.
- Build artefacts land under the top-level `build/preserf-fortran/`
  directory (already covered by `.gitignore`), not under `src/`. The
  Python fixture `_BUILD_TEST_DIR` in `tests/integration_tests/test_fortran_wire_compat.py`
  points at the same path.
- The pytest fixture still `pytest.skip`s when the binary is missing
  by default (preserves the local-dev ergonomics), but switches to a
  hard `pytest.fail` when `PRESERF_REQUIRE_FORTRAN=1` is set — so CI
  cannot let a broken Fortran build pass by silently skipping the
  wire-compat test. `xfail` would not be enough — an xfailed test
  still lets the suite pass.

### Slice G — Append mode

Closes gap §4. Lowest priority — pp_ser-generated source rarely uses
`'a'`, and `'w'` + `'r'` cover the typical run/replay loop.

- Implement `nf90_inq_grps` resumption of the savepoint group index.
- Sanity-check that the existing `_preserf_*` housekeeping attrs
  match what the new run would write, otherwise abort (don't
  silently fork the store).

## 4. Carry-over Copilot review notes from PR #4

These are advisory comments that arrived on the PR around merge time.
They are tracked here so they don't get lost; promoting any of them to
a slice is a judgement call.

- `m_preserf.f90` — write-side registry validation has no explicit
  negative test. `fs_write_field` validates only overload type and
  runtime shape against the registry (it does not take halo
  arguments), so the missing cases are mismatched dtype and
  mismatched dims; halo-mismatch validation belongs to the
  Slice A-1 resolve-and-validate path on `fs_register_field`, not to
  the write side.
- `m_preserf.f90` — read-side `require_variable_xtype` rejection has
  no negative test.
- `m_preserf.f90` — savepoint-metainfo native test coverage is
  limited to `int32` and `real64`; the `logical`, `int64`, `real32`,
  and `character` savepoint overloads are not exercised by the
  native Fortran test. (The serializer-metainfo side already covers
  `logical`, `int64`, and `real32` in the native test, and the
  cross-language test asserts their raw netCDF dtypes — those rows
  are not a gap.)
- `tests-fortran/unit/m_preserf/test_minimal.f90` —
  disabled-savepoint round-trip checks `grpid` and `idx` but not
  `owner_ncid`.
- `tests-fortran/unit/m_preserf/test_minimal.f90` — only one enabled
  savepoint is created, so the `next_sp_index` increment and
  `sp_000001` naming aren't exercised end-to-end.

Most of these fold into Slice A-1 (read-mode tests) or Slice B
(type-coverage tests). The previously listed int32 truncation note
landed as PR #16 (see §1) — `require_fits_int32` is now applied in
`active_dims_c_order` / `put_halo_attr`.

## 5. v1.0 — Definition of Done

The roadmap should cut a v1.0 of `preserf-fortran` when all of the
following hold:

1. Slices A-1, A-2, B, C-0, C, D (full), and E have landed on `main`.
2. `tests/integration_tests/test_fortran_wire_compat.py` parametrises
   over the full (rank × dtype × backend) matrix and passes in CI
   with `PRESERF_REQUIRE_FORTRAN=1`.
3. The native-Fortran test exercises at least one read-mode round-trip
   per shipped slice (A-1 read-back, A-2 perturb-read, B type matrix,
   C tracer write+read).
4. No `error stop` remains as a stub in `src/preserf-fortran/` — every
   compile-only overload either has an implementation or has been
   removed.
5. The `_preserf_*` housekeeping attributes documented in
   `storage_mapping.md` §1 round-trip without drift between writer
   and reader.

**Explicitly deferred past v1.0:** Slice B′ (string data fields) and
Slice G (append mode); both are documented as low-priority today and
should not block a v1.0 cut. If demand emerges, they ship as v1.1.

## 6. Out of scope

- A second backend implementation (e.g. native HDF5, native Zarr
  without going through netcdf-c). The whole point of the schema is
  that one Fortran helper produces both NetCDF4 and NCZarr.
- Distributed / MPI-aware writes beyond what Serialbox itself
  supported. The `mpi_rank` keyword that Slice D wires up only
  controls the `_rank<n>` suffix on the store name (one independent
  store per rank, per `storage_mapping.md` §9); parallel HDF5 /
  parallel NCZarr is a future option, not part of this roadmap.
- A C API. pp_ser only generates Fortran.
