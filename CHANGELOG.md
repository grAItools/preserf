# Changelog

All notable changes to `preserf` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Per-slice spec / plan dirs live under [`specs/`](specs/) (overview in
[`specs/README.md`](specs/README.md)). v0.1 gaps the specs close are
embedded in each spec's Problem section.

## [0.2.0-dev] — post-v0.1.0 main, unreleased

### Added

- Fortran distribution (`specs/2026-06-fortran-distribution`): the Fortran
  runtime now ships inside the wheel as package data. The runtime tree moved
  from `src/preserf-fortran/` to `src/preserf/fortran/`, so a `pip install
  preserf` user can compile preserf-generated Fortran without cloning the
  repo. `preserf.get_fortran_dir()` / `get_cmake_helper()` and the matching
  `preserf --fortran-dir` / `--cmake-helper` CLI flags expose the bundled
  location (numpy `get_include()` pattern). A shipped CMake helper
  (`preserf/fortran/cmake/PreserfFortran.cmake`) provides
  `preserf_add_fortran_target()` — one call that expands `!$SER` sources,
  compiles and links them against the runtime, and applies `SERIALIZE` and the
  required flags. The laplacian example and the Fortran e2e test consume that
  same shipped helper so the integration recipe cannot drift. A packaging test
  asserts the wheel carries the runtime + helper and that discovery resolves
  (fast `verify` gate); a `consumer`-marked external-consumer test builds a
  throwaway project against the bundled runtime via the discovery CLI, runs it,
  and validates the store round-trips (`pixi run test-all`). Distribution is
  source-only and CMake-only; `netcdf-fortran` remains a user-supplied
  pkg-config dependency. See the README "Using preserf in your build" section.
- Standalone install target for the Fortran runtime: the bundled
  `preserf/fortran/CMakeLists.txt` is now an installable CMake project, so
  `cmake -S "$(preserf --fortran-dir)" -B build` followed by
  `cmake --build build --target install` lays down the `preserf_fortran`
  library, its compiled `.mod` interface files, and a namespaced CMake package
  config (`preserf::preserf_fortran`). Downstream projects consume the install
  with `find_package(preserf_fortran)` instead of rebuilding the runtime from
  source via `add_subdirectory()`. The generated config re-discovers
  `netcdf-fortran` through pkg-config. Install rules are emitted only for the
  top-level (standalone) build, so the existing helper / example / native-test
  `add_subdirectory` consumers are unchanged (override with
  `-DPRESERF_FORTRAN_INSTALL=ON/OFF`). A new `consumer`-marked test installs the
  runtime and builds a throwaway project against it through `find_package`.
- Plain-`make` example (`examples/laplacian/make/`): runs the same Laplacian
  program as the CMake variant (`examples/laplacian/cmake/`), reusing the
  parent `examples/laplacian/` shared `laplacian.f90` source and `verify.py`,
  but installs the runtime with CMake and then drives the preprocessing,
  compilation and linking from a hand-written `Makefile` against the install
  prefix — demonstrating that the install target makes the runtime consumable
  from a non-CMake build system, and documenting the expand → compile → link
  recipe (the `SERIALIZE` / `-cpp` / `-ffree-line-length-none` / F2008 flags and
  the explicit `netcdf-fortran` link) the CMake helper otherwise applies.
- `PRESERF_BACKEND` environment variable: when `ppser_initialize` is
  called without an explicit `backend=` argument (as pp_ser / Serialbox
  `!$SER INIT` call sites do), the storage backend is resolved from the
  `PRESERF_BACKEND` env var, else the `netcdf4` default. Precedence,
  most → least specific: explicit `backend=` argument → `PRESERF_BACKEND`
  → `netcdf4`. An unknown value — from either source — aborts at the
  init boundary with the same clear "unknown backend" message
  (`netcdf4` / `nczarr-v2`). This makes the on-disk format a runtime
  choice for callers that never surface the `backend` keyword. The
  resolved backend is also logged in the "SERIALIZATION IS ON" init
  line so the format is self-evident from the run log. A blank or
  whitespace-only `PRESERF_BACKEND` is treated as unset and falls back to
  the default; a value too long for the read buffer (truncation) aborts
  with a clear message rather than acting on a partial value. An explicit
  `backend=` argument is normalised with `trim`/`adjustl`, so a value passed
  in a fixed-length character variable (with leading/trailing blanks) is
  accepted rather than rejected as "unknown backend", matching the env-var
  path. Covered by the `backend-env` / `backend-env-bad` /
  `backend-env-blank` / `backend-arg-padded` ctest scenarios (#48).
- Tracers (Slice C, Phase 1 — `!$SER REGISTERTRACERS` / `!$SER TRACER`):
  the Fortran helper gains `fs_RegisterAllTracers`,
  `ppser_write_tracer_by_name` / `_by_idx` / `_all`, and a host-side
  `ppser_register_tracer` that binds tracer data to a small built-in
  registry (the directive surface carries only a name/index + stype +
  integer timelevel, never the data — see
  [ADR 0003](docs/adr/0003-tracer-storage.md)). `fs_RegisterAllTracers`
  writes one `/_tracers/<name>` descriptor per registered tracer
  (`type_id`, C-order `dims`, `stype`, `tracer_index`), mirroring
  `/_fields`; the write entry points emit each tracer as an ordinary
  savepoint variable (byte-identical to a `!$SER DATA` field) with the
  integer timelevel as an optional `timelevel` attribute. One snapshot per
  `(savepoint, tracer)`, last-wins (`storage_mapping.md` §4a). The registry
  keeps a pointer to the host's `TARGET` array (not a copy), so a read-mode
  `!$SER TRACER` reads the stored field back into the same array; read mode
  also resolves-and-validates the `/_tracers` descriptors. v1.0 binds
  `real(real64)` tracers (ranks 1–4). A native `tracers` / `tracers-roundtrip`
  (write + Fortran read-back) ctest plus a
  `test_fortran_wire_compat.py` scenario assert the descriptors, per-entry-
  point data placement, the timelevel attribute, and axis-order through the
  Python reference reader.
- k-buffer serialization (Slice C, Phase 2 — `!$SER DATA_KBUFF`):
  `fs_write_kbuff(serializer, savepoint, name, data, k, k_size, mode)` is
  called once per vertical level with the horizontal slice at that level;
  the helper buffers each slice and, on the last level (`k == k_size`),
  assembles the full `(slice_shape…, k_size)` field and writes it through
  the field path, so the on-disk variable is byte-identical to a `!$SER
  DATA` write (`storage_mapping.md` §6, ADR 0003 §5). Read mode is the
  mirror: the stored field is loaded once and each level is copied back into
  the caller's slice (`data` is `intent(inout)`). v1.0 buffers
  `real(real64)` slices of rank 1–3 (fields rank 2–4). A native `kbuff` ctest
  (write + read-back) plus a `test_fortran_wire_compat.py` scenario assert
  the assembled fields against the per-level accumulation.
- Runtime options (Slice C, Phase 3 — `!$SER OPTION`): `fs_Option` exposes
  a single fixed keyword, `verbosity` (ADR 0003 §4) — Fortran cannot accept
  an arbitrary `key=value` dummy, so the preprocessor now rejects any other
  OPTION key with a clear directive error (was: passed through verbatim).
  `fs_Option(verbosity=N)` sets a module-level verbosity knob and records
  the value as the reserved `_preserf_option_verbosity` root attribute so it
  round-trips (`storage_mapping.md` §4b); the `on`/`off` → `1`/`0` mapping is
  unchanged. With this, Slice C (tracers + k-buffer + OPTION) and its
  predecessor ADR (C-0) are complete.
- Full numeric type-coverage matrix (Slice B): the Fortran helper's
  `fs_write_field` / `fs_read_field` overloads now cover every
  `{logical, int32, int64, real32, real64}` × `{0D, 1D, 2D, 3D, 4D}`
  combination (was `real64` 1D/2D/3D only), and read-perturb (the 5-arg
  `fs_read_field`) extends to `real32` alongside `real64`. Logical fields
  land as `NF90_BYTE` 0/1; 0-D (scalar) fields register with a zero-length
  `dims` attribute and a netCDF scalar variable. New 1D-array overloads of
  `fs_add_savepoint_metainfo` / `fs_add_serializer_metainfo` cover
  `logical / int32 / int64 / real32 / real64` (Serialbox
  `MetainfoValue::Array`), stored as native vector attributes whose
  `__preserf_type_id` shadow carries the array TypeID (`TID_ARRAY .or.
  base`). The 50 field overloads, 10 read-perturb overloads, and 10
  `apply_perturb` helpers are generated from `#include` templates:
  `m_preserf.f90` becomes `m_preserf.F90`, compiled with `-cpp` (the
  array-metainfo overloads and their write/validate helpers are
  hand-written, since they do not vary over rank) (see
  [ADR 0004](docs/adr/0004-fortran-cpp-templates.md)). A native
  `type-matrix` ctest scenario round-trips each dtype, a 0-D scalar, a 4-D
  field, real32 perturb, and array metainfo; a `wire-matrix` scenario plus
  a parametrised `test_fortran_wire_compat.py` matrix assert the on-disk
  netCDF type and registry `type_id` for all 25 `(rank, dtype)`
  combinations against `storage_mapping.md` §1. Array **string** metainfo
  (`NC_STRING`) is deferred to Slice B′ with string data fields.
- Backend selector + NCZarr URL targets (Slice E): `ppser_initialize` now
  accepts a `backend` keyword selecting `'netcdf4'` (default, the v0.1
  `.nc` file behaviour) or `'nczarr-v2'`. `preserf_open_serializer`
  constructs the on-disk target per backend — a plain `<dir>/<prefix>.nc`
  path for NetCDF4, or a `file://<dir>/<prefix>.zarr#mode=nczarr,zarr2`
  URL onto a `.zarr` directory store for NCZarr V2 — matching
  `open_url_for` in `tests/_support/storage.py` so a Fortran-written store
  and the Python reader agree on the URL. The same group-per-savepoint
  schema serves both (ADR 0002); the `#mode=` query drives netcdf-c's
  backend dispatch, so the `nf90_create` / `nf90_open` flags are unchanged.
  An unknown `backend` aborts at the `ppser_initialize` boundary. The
  `nczarr-v2` backend builds its store URL by raw concatenation, so it
  requires an absolute `directory` (its `file://` URL has no portable
  relative form) and a `directory` / `prefix` free of URI-significant
  characters (space, `#`, `?`, `%`); a relative directory or an
  un-encodable path aborts with a clear message instead of building a
  malformed `file://…` target that would point at the wrong store. A new
  `backend-nczarr` `tests-fortran/unit/m_preserf` ctest scenario
  round-trips a `real64` field through an NCZarr V2 store; `backend-bad`,
  `backend-nczarr-relpath`, and `backend-nczarr-badchar` negative
  scenarios cover the aborts; and a new `test_fortran_wire_compat.py` case
  decodes a Fortran-written `.zarr` store through the Python reference
  reader. Zarr V3 remains deferred until netcdf-c's NCZarr V3 PR lands.
- Read-perturb implementation (Slice A-2): the 5-arg
  `fs_read_field(..., perturb)` overloads (`real64` 1D/2D/3D) now read the
  stored field and apply symmetric multiplicative noise
  `data*(1 + perturb*(2*r - 1))` (`r ~ U[0,1)` via Fortran intrinsic
  `RANDOM_NUMBER`), matching the original COSMO `serialize` read-perturb
  (`mode=2`) semantics that pp_ser emits as `ppser_zrperturb`. The 5th arg
  carries the scale, so a zero scale is the identity. The previous
  compile-only `error stop` stub (`read_perturb_not_implemented`) is gone.
  A new `perturb-roundtrip` `tests-fortran/unit/m_preserf` ctest scenario
  writes a `real64` field, reads it back with scale `0.1` asserting every
  element stays within `[orig*0.9, orig*1.1]` with non-zero overall
  deviation, and confirms scale `0.0` reads back unperturbed.
- Read-mode create-or-resolve-and-validate (Slice A-1): `fs_register_field`,
  `fs_create_savepoint`, and the scalar `fs_add_savepoint_metainfo` /
  `fs_add_serializer_metainfo` overloads now resolve and validate the
  existing store entry when `ppser_get_mode()` is read (1) or read-perturb
  (2) instead of unconditionally creating netCDF objects, so a
  pp_ser-generated read run against a read-only store no longer aborts at
  the first create call. Each directive aborts with a specific message on a
  mismatch (field type_id / dims / per-direction halo; savepoint `name`;
  metainfo value or `__preserf_type_id`). `fs_read_field` re-resolves the
  savepoint group under its own serializer, so an explicit
  `directory_ref` / `prefix_ref` store reads from the reference file rather
  than the primary. New `tests-fortran/unit/m_preserf` ctest scenarios
  cover the read round-trip (including the `sp_000000` → `sp_000001`
  index advance), the explicit-reference read, and negative cases for each
  validation (including read-side `require_variable_xtype` rejection).
- `ppser_initialize` accepts the Serialbox-compatible keywords pp_ser
  passes through from `!$SER INIT`: `singlefile`, `mpi_rank`,
  `rprecision`, `rperturb`, `realtype`, `archive`, `unique_id`.
  `mpi_rank` suffixes the on-disk store name with `_rank<n>`
  (one store per rank); `realtype`/`rprecision` override
  `ppser_realtype`/`ppser_reallength`; `rperturb` threads to
  `ppser_zrperturb` (consumed by read-perturb, Slice A-2). The
  metadata-only `singlefile`/`archive`/`unique_id` keywords are recorded
  on the writable store as the `_preserf_singlefile` / `_preserf_archive`
  / `_preserf_unique_id` root attributes for round-trip fidelity
  (`docs/references/storage_mapping.md` §3.1); `tests/_support/storage.py`
  reads them back onto `SerialboxDump`. Completes Slice D Phase 3.
- End-to-end pipeline test (Slice D Phase 4): `tests-fortran/e2e/`
  carries a `!$SER`-annotated fixture that CMake expands through the
  `preserf` CLI, compiles against the helper, and runs;
  `tests/integration_tests/test_preprocessor_e2e.py` reads the resulting
  store back and asserts the field, savepoint, metainfo, data, and the
  Phase 3 init attrs all round-trip. Runs natively under
  `pixi run test-fortran` and is gated by `PRESERF_REQUIRE_FORTRAN=1`.
- `src/preserf/preprocessor.py`: typed, two-pass reimplementation of
  `pp_ser.py` expanding every `!$SER` directive ([#6](https://github.com/grAItools/preserf/pull/6)).
- `src/preserf/cli.py`: `preserf` CLI with single-file, output-dir, and
  recursive modes ([#6](https://github.com/grAItools/preserf/pull/6)).
- `src/preserf/errors.py`: `DirectiveError` carries file/line context
  ([#6](https://github.com/grAItools/preserf/pull/6)).
- `.github/workflows/ci.yml`: Fortran CI gate — builds the helper,
  runs ctest, then runs `pixi run verify` with
  `PRESERF_REQUIRE_FORTRAN=1` so a broken Fortran build cannot pass by
  silently skipping the wire-compat test. Closes roadmap Slice F
  ([#14](https://github.com/grAItools/preserf/pull/14), [#15](https://github.com/grAItools/preserf/pull/15)).
- `.devcontainer/`: pixi-based dev container ([#10](https://github.com/grAItools/preserf/pull/10), [#12](https://github.com/grAItools/preserf/pull/12)).
- `tests/unit_tests/test_storage_read_validation.py`: a
  `test_read_dump_rejects_*` family pinning every validation branch in the
  test-support reader `tests/_support/storage.py` `read_dump()` — the trusted
  oracle the round-trip and wire-compat tests ride on. Each test builds a valid
  store with the shared `_make_dump`/`write_dump` helpers, corrupts one
  invariant (bad/missing schema version, missing `/_fields` or `/savepoints`
  group, odd-length/duplicate/inconsistent/non-dense field ids, savepoint
  variable absent from both registries), and asserts the branch-specific
  failure. Runs in the fast pytest selection ([#77](https://github.com/grAItools/preserf/issues/77)).

### Changed

- The Fortran helper sources moved from `src/preserf-fortran/` to
  `src/preserf/fortran/` (no API or behaviour change; updated CMake
  `add_subdirectory` paths, `pixi` fprettify paths, and docs).
- The `/_fields/<name>` registry-entry layout (`def_var` NF90_INT carrier
  → `type_id` att → `dims` att → non-zero halos → scalar `put_var`,
  storage_mapping.md §1) now lives in a single private helper
  `write_field_registry_entry`. Both explicit registration
  (`fs_register_field`) and first-write auto-registration
  (`autoregister_field`) emit through it, so the shared registry-entry
  layout cannot drift between the two paths. Auto-registration records
  zero halos (omitted on disk), so its bytes match an explicit zero-halo
  registration. Pure refactor; on-disk bytes unchanged
  (verified by the existing `test_fortran_wire_compat.py` suite)
  ([#57](https://github.com/grAItools/preserf/issues/57)).
- `ppser_initialize` now validates the `realtype` keyword at the init
  boundary, mirroring the existing `backend` allowlist check. An
  unrecognised name (e.g. the typo `'flaot'`) aborts in `ppser_initialize`
  with a clear, `!$SER INIT`-attributable message naming the bad value and
  listing the recognised names (`float` / `single` / `double` / `real`,
  case-insensitive) — before any field is registered — rather than being
  stored verbatim and blowing up much later inside `type_id_from_datatype`
  when `fs_register_field` runs. The four recognised names continue to set
  `ppser_realtype` / `ppser_reallength` consistently. Covered by the
  `realtype-bad` / `realtype-valid` ctest scenarios (#56).
- Test layout reorganized into `tests/unit_tests/`,
  `tests/integration_tests/`, and `tests-fortran/unit/m_preserf/`
  ([#17](https://github.com/grAItools/preserf/pull/17)).
- Build harness consolidated onto pixi tasks; legacy
  Makefile/scripts removed ([#13](https://github.com/grAItools/preserf/pull/13)).
- Agent harness scaffolded via the
  `grAItools/harness-copier-template` ([#8](https://github.com/grAItools/preserf/pull/8), [#9](https://github.com/grAItools/preserf/pull/9)).
- Agent harness synced to template `ea70ca1` → `42e06b6`: adds the
  role-based subagents (`product-owner`, `architect`, `developer`,
  `reviewer`), the `/build` command, and `docs/tool-bootstrap.md`;
  adopts Conventional Commits (`commit_convention`) with squash-merge
  PR titles, documented in [`docs/style.md`](docs/style.md#commit-messages).

### Fixed

- `fs_register_field` no longer aborts with a raw netCDF error when a field
  is registered more than once or on a read-only handle. Re-registering a
  field (a `!$SER REGISTER` in a per-timestep loop, or a field already
  auto-registered by a first `!$SER DATA` write) is now idempotent: the
  existing `/_fields/<name>` entry is validated against the new arguments
  and skipped, matching Serialbox, and a mismatch (including a halo a
  REGISTER skipped while serialization was OFF failed to record) aborts
  with a clear `re-registered field` message instead of crashing on a
  duplicate `def_var` (`NC_ENAMEINUSE`). A REGISTER that reaches the create
  path on a read-only handle (global write mode but a read-opened
  serializer) now aborts with a clear `opened read-only` message rather
  than a low-level `def_var` failure — the explicit-registration
  counterpart of the auto-register gate added in
  [#59](https://github.com/grAItools/preserf/pull/59)
  ([#57](https://github.com/grAItools/preserf/issues/57)).
- Auto-registration of a zero-size array (a `0` runtime extent) now aborts
  with a clear message instead of writing a malformed `/_fields/<name>`
  entry: the explicit REGISTER tuple cannot express such a shape, and a `0`
  extent reaching `nf90_def_dim` is read by netCDF as `NF90_UNLIMITED`,
  silently creating an unlimited dimension
  ([#57](https://github.com/grAItools/preserf/issues/57)).
- `resolve_abs_dir` (the relative-directory → absolute-path helper used by
  the `nczarr-v2` backend) no longer corrupts the resolved CWD under
  **nvfortran**. The `getcwd` copy loop appended the `char()` _function
  result_ straight onto a deferred-length allocatable string
  (`cwd = cwd//char(...)`); nvfortran (nvhpc — the production ICON compiler
  on CSCS) miscompiles this, treating the function result as having a bogus
  length and padding each character with ~98 spaces, so the resolved CWD
  became garbage and `nczarr-v2` with a relative `directory` failed. No
  nvfortran flag fixes it; staging the converted character through an
  explicit `character(len=1)` temporary before concatenation sidesteps the
  codegen bug. gfortran was unaffected. A new `resolve-relpath` ctest
  scenario locks in the byte-exact `<CWD>/<reldir>` resolution so a future
  regression (corrupted length / stray padding) fails the gate
  ([#63](https://github.com/grAItools/preserf/issues/63)).
- Line-continuation detection for `!$SER` directives is now comment-aware: a
  `&` that appears inside a **trailing inline comment** (e.g.
  `!$SER DATA vn=vn ! foo &`) is no longer mistaken for a line continuation,
  so the comment is dropped and the following source line is not swallowed
  into the directive. Genuine continuations (a `&` outside any comment) are
  unaffected. This reuses the quote-aware comment stripper to drop the
  trailing comment before checking for the `&` marker
  ([#55](https://github.com/grAItools/preserf/issues/55)).
- The `nczarr-v2` backend now resolves a **relative** `directory` (e.g.
  `./ser_data`) to an absolute path against the process CWD (via POSIX
  `getcwd`) before building its `file://...#mode=nczarr,zarr2` URL, instead
  of aborting. NetCDF4 (and Serialbox) already accept relative directories,
  so this makes `nczarr-v2` a drop-in for the same inputs; an absolute
  `directory` is unchanged, and a genuinely un-resolvable path still aborts
  with a clear message. The `backend-nczarr-relpath` ctest now round-trips a
  field through a relative directory
  ([#49](https://github.com/grAItools/preserf/issues/49)).
- `fs_write_field` now **auto-registers** a field on its first write when it
  is not already present under `/_fields/`, inferring the `type_id` from the
  Fortran overload and the C-order `dims` from the runtime array shape (no
  halos). This matches Serialbox, whose `fs_write_field` registers a field on
  first write, so pp_ser `!$SER DATA` / `!$SER ACCDATA` call sites — which
  never emit `!$SER REGISTER` — write without an explicit registration
  instead of aborting with "write on unregistered field". A read of an
  unregistered field still aborts (there is nothing to read). A new
  `autoregister` ctest scenario writes representative dtypes / ranks with no
  prior `fs_register_field` and round-trips them back, and a
  `test_fortran_wire_compat.py` scenario asserts the inferred registry
  entries decode through the Python reference reader
  ([#43](https://github.com/grAItools/preserf/issues/43)).
- First-write auto-registration (above) is now gated on the serializer
  handle's own **writability** (`s%writable`), not merely on the
  `op == 'write'` code path. A direct `fs_write_field` against a serializer
  opened in **read** mode on a field that was never registered now aborts
  with the clear
  `write on unregistered field "..."; call fs_register_field first` message
  again, instead of a raw low-level netCDF `def_var` error from
  auto-registration attempting an `nf90_def_var` on the read-only handle.
  `s%writable` is the authoritative per-handle test of whether
  `nf90_def_var` can succeed; the global `ppser_get_mode()` is DATA-mode
  state, not this handle's writability, so it is deliberately _not_ part of
  the gate — a writable handle still auto-registers a first write
  regardless of the global mode (issue #43 parity). Generated code never
  reaches the read-mode case (pp_ser's mode `SELECT` gates DATA blocks); it
  is reachable only via direct API use. New `write-readmode-unregistered`,
  `write-readhandle-mode0-unregistered`, and
  `write-writable-mode1-autoregister` ctest scenarios cover it
  ([#58](https://github.com/grAItools/preserf/issues/58)).
- `ppser_initialize` now creates the output `directory` (`mkdir -p`
  semantics) before `nf90_create` on the write path, restoring drop-in
  compatibility with Serialbox: its serializer creation made the output
  directory, so real `!$SER INIT directory='...'` call sites (e.g. ICON)
  and the runscripts that drive them never `mkdir` it. Previously a fresh
  run aborted inside `nf90_create` with netCDF's generic "Permission
  denied" (the real cause being the missing parent directory). The mkdir
  is portable (`EXECUTE_COMMAND_LINE` with `mkdir -p`), idempotent over an
  existing store, and shell-injection-safe; read-mode opens are unaffected
  (the store must already exist). A new `init-mkdir` ctest scenario writes
  into a fresh nested subdirectory and asserts the store is created
  ([#42](https://github.com/grAItools/preserf/issues/42)).
- `ppser_initialize`'s `mode` argument is now **optional**, restoring
  drop-in compatibility with pp_ser / Serialbox `!$SER INIT` call sites,
  which never pass `mode` (Serialbox selects it separately via `!$SER MODE`
  → `ppser_set_mode`). When `mode` is omitted, the open mode is derived
  from the current runtime mode state: `1` (read) / `2` (read-perturb) open
  read-only, `0` (write, the default when no mode was set) creates the
  store; the omitted-mode path no longer overwrites the runtime mode, so a
  prior read-perturb (`2`) survives. A new `init-default-mode` ctest
  scenario covers all three paths
  ([#32](https://github.com/grAItools/preserf/issues/32)).
- `require_fits_int32` guard in `active_dims_c_order` / `put_halo_attr`
  closes a latent truncation on very large dim sizes / halo extents
  ([#16](https://github.com/grAItools/preserf/pull/16)).

## [0.1.0] — 2026-05

Initial usable preview: storage mapping decision + minimal Fortran helper
that pp_ser-generated source can link against in write mode for the most
common shapes.

### Added

- Storage mapping ADR and reference: Serialbox data model mapped onto
  NetCDF4 and Zarr V2 via NCZarr, with `tests/_support/storage.py` and
  `tests/_support/serialbox.py` reference readers and a Python
  round-trip test ([#3](https://github.com/grAItools/preserf/pull/3)).
- Minimal Fortran helper (`src/preserf-fortran/`):
  - `utils_preserf.f90` — lifecycle (`ppser_initialize`,
    `ppser_finalize`, `ppser_set_mode`, `ppser_get_mode`) plus the
    module-level state pp_ser-emitted code uses (`ppser_serializer`,
    `ppser_serializer_ref`, `ppser_savepoint`, `ppser_intlength`,
    `ppser_reallength`, `ppser_realtype`, `ppser_zrperturb`).
  - `m_preserf.f90` — `fs_register_field`, `fs_create_savepoint`,
    scalar `fs_add_savepoint_metainfo` / `fs_add_serializer_metainfo`
    (`logical` / `int32` / `int64` / `real32` / `real64` /
    `character`), `fs_write_field` / `fs_read_field` for `real64` 1D/2D/3D
    (4-arg and compile-only 5-arg perturb form),
    `fs_enable_serialization` / `fs_disable_serialization` /
    `fs_serialization_status`.
  - `m_serialize` / `utils_ppser` alias modules so pp_ser-generated
    source using the historical Serialbox module names compiles
    unchanged.
  - CMake 3.20+ build (`src/preserf-fortran/CMakeLists.txt`,
    `tests-fortran/CMakeLists.txt`); pkg-config discovery of
    `netcdf-fortran`; gfortran `-std=f2008`.
  - Native Fortran test (`tests-fortran/unit/m_preserf/test_minimal.f90`)
    plus cross-language wire-compat test
    (`tests/integration_tests/test_fortran_wire_compat.py`) that skips
    when the Fortran binary is absent ([#4](https://github.com/grAItools/preserf/pull/4)).
- Directive specification extracted from `pp_ser.py` as a reference
  document; initial project scaffolding (Python ≥3.12, pixi, MIT
  license) ([#1](https://github.com/grAItools/preserf/pull/1), [#2](https://github.com/grAItools/preserf/pull/2), [#5](https://github.com/grAItools/preserf/pull/5)).

[Unreleased]: https://github.com/grAItools/preserf/compare/v0.2.0-dev...HEAD
[0.2.0-dev]: https://github.com/grAItools/preserf/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/grAItools/preserf/releases/tag/v0.1.0
