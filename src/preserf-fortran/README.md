# preserf-fortran

Fortran helper modules that pp_ser-generated `!$SER` directive code links
against. **v0.1 writes NetCDF4 stores** following the group-per-savepoint
layout documented in [`../../development/references/storage_mapping.md`][mapping].
The schema itself is also defined for NCZarr V2 (and is forward-compatible
with Zarr V3 once netcdf-c's NCZarr V3 PR lands), but emitting an NCZarr
URL target from the Fortran helper is tracked as a follow-up — see
"Known limitations" below.

[mapping]: ../../development/references/storage_mapping.md

## Modules

| Module           | Purpose                                                                  |
|------------------|--------------------------------------------------------------------------|
| `m_preserf`      | Main API: `fs_register_field`, `fs_create_savepoint`, `fs_write_field`, `fs_read_field`, `fs_add_savepoint_metainfo`, `fs_add_serializer_metainfo`, `fs_enable_serialization`, `fs_disable_serialization`. |
| `utils_preserf`  | Lifecycle + module-level state (`ppser_serializer`, `ppser_savepoint`, `ppser_initialize`, `ppser_finalize`, `ppser_set_mode`, `ppser_get_mode`). |
| `m_serialize`    | Drop-in re-export of `m_preserf` under Serialbox's historical module name. |
| `utils_ppser`    | Drop-in re-export of `utils_preserf` under Serialbox's historical module name. |

The `m_serialize` / `utils_ppser` aliases preserve the historical
module identifiers pp_ser-generated source imports, but the
**implemented symbol surface is the v0.1 subset described below**.
pp_ser output that uses directives or `ppser_initialize` keyword
arguments outside that subset will still fail to compile against the
aliases until the relevant follow-up PR lands — see the "Known
limitations" subsection.

## Scope of this build

v0.1 of the helper covers the minimum **write-mode** surface needed for
the `!$SER INIT(mode='w')` / `REGISTER` / `SAVEPOINT` / `DATA` /
`CLEANUP` flow:

- `fs_register_field` records `/_fields/<name>` with `type_id` + `dims`
  (in C-order — see [§1.1 of the storage mapping][axis-order]) and any
  non-zero halo attributes. Includes a contiguous-prefix check on the
  `(iSize, jSize, kSize, lSize)` tuple.
- `fs_create_savepoint` allocates the next `/savepoints/sp_NNNNNN`
  group with `name` and `_preserf_savepoint_index` attributes.
- `fs_add_savepoint_metainfo` and `fs_add_serializer_metainfo` are
  overloaded for the six scalar Serialbox `TypeID`s
  (`logical`, `integer(int32)`, `integer(int64)`, `real(real32)`,
  `real(real64)`, `character(len=*)`). Reserved keys (`_preserf_*`
  prefix, `__preserf_type_id` suffix, plus `name` on savepoint groups)
  are rejected.
- `fs_write_field` is overloaded for `real(real64)` in 1D / 2D / 3D.
  Each write validates the runtime shape and dtype against the
  registered `/_fields/<name>` metadata before touching the store.
- `fs_read_field` is overloaded for `real(real64)` in 1D / 2D / 3D in
  both the 4-argument form and the 5-argument read-perturb form
  (`fs_read_field(s, sp, name, data, perturb)`). The 5-arg overloads
  exist so pp_ser-emitted CASE(2) branches compile, but they
  `error stop` at runtime — see "Known limitations" §1 below.
- `fs_enable_serialization` / `fs_disable_serialization` gate every
  fs_* I/O entry point at runtime; `fs_serialization_status()` exposes
  the flag for tests.

### Known limitations / mismatches with pp_ser-generated code

The first slice trades a few corners of pp_ser's contract for a small
implementation. These are tracked as follow-up PRs:

1. **Read mode is partial.** `ppser_initialize(directory, prefix, 'r')`
   opens the store read-only (and, in this slice, also opens
   `ppser_serializer_ref` against the same store so pp_ser's read DATA
   branches can call `fs_read_field(ppser_serializer_ref, ...)`).
   `fs_read_field` works against a read-only store, which is enough
   for `tests/test_fortran_minimal.py`. However, pp_ser-generated
   source also calls `fs_register_field`, `fs_create_savepoint`, and
   the metainfo helpers (`fs_add_serializer_metainfo` /
   `fs_add_savepoint_metainfo`) unconditionally — these directives
   live OUTSIDE the `SELECT CASE (ppser_get_mode())` that wraps DATA
   blocks. The current implementation of those routines always
   **creates** the corresponding netCDF object, so pointing a
   pp_ser-generated read run at an existing read-only store will
   abort (e.g. `fs_create_savepoint` trying to `nf90_def_grp(sp_000000)`
   on a read-only dataset). The follow-up PR will switch them to a
   "create-or-resolve-and-validate" shape; until then, only the
   write-mode end-to-end flow is exercised.

   Read-perturb mode (CASE(2)) is similarly partial: the 5-arg
   `fs_read_field(..., perturb)` overloads exist so generated source
   compiles, but they `error stop` at runtime since the perturbation
   algorithm itself is not yet implemented.

   Additionally, the read overloads validate the registry on the
   `s` serializer (via `s%fields_grpid`) but pull the data variable
   from `sp%grpid`, the savepoint group created by
   `fs_create_savepoint`. pp_ser-generated read DATA branches call
   `fs_read_field(ppser_serializer_ref, ppser_savepoint, ...)` where
   `ppser_savepoint` lives in `ppser_serializer` rather than
   `ppser_serializer_ref` — so an explicit reference store would
   validate against one file and read from another. This is one of
   the cases the create-or-resolve-and-validate refactor needs to
   address (savepoints would carry per-serializer grpids, or the
   read path would re-resolve the savepoint under `s` first).
2. **`ppser_initialize` keyword surface is narrow.** v0.1 takes
   `directory`, `prefix`, `mode` (plus optional `directory_ref`,
   `prefix_ref`). Serialbox's `ppser_initialize` accepts additional
   keyword args (`singlefile`, `mpi_rank`, `rprecision`, `rperturb`,
   `realtype`, `archive`, `unique_id`) which pp_ser passes through
   verbatim from `!$SER INIT` directives. Generated source that uses
   any of those keyword arguments will not yet compile against
   preserf. The follow-up PR that ports `pp_ser.py` will widen the
   helper's signature to match Serialbox's.
3. **Append mode (`'a'`) is rejected** rather than half-implemented.
   It needs `nf90_inq_grps` index resumption that the netcdf-fortran
   4.5.x wrapper makes awkward.

Out of scope for this PR (tracked as follow-ups):
- Full type-coverage matrix (bool / i32 / i64 / f32 + 0D..4D for fields,
  array metainfo variants).
- `fs_write_kbuff` (k-buffer / `!$SER DATA_KBUFF`).
- `fs_RegisterAllTracers` and the tracer write API (`!$SER TRACER`).
- `fs_Option` (`!$SER OPTION`).
- NCZarr URL targets. The helper currently constructs the open path as
  `<directory>/<prefix>.nc` and passes `NF90_NETCDF4` to `nf90_create`.
  Supporting `file://<directory>/<prefix>.zarr#mode=nczarr,zarr2`
  requires both reworking the path/URL construction in
  `preserf_open_serializer` and surfacing a backend selector at the
  `ppser_initialize` boundary, plus a cross-language test that exercises
  it via `tests/_storage.py`. Not the one-line change the original draft
  suggested.

[axis-order]: ../../development/references/storage_mapping.md

## Building

Requires `cmake` ≥ 3.20, a Fortran compiler (tested with gfortran 13),
and `netcdf-fortran` development files (`libnetcdff-dev` on
Debian/Ubuntu; the `netcdf-fortran.pc` pkg-config file is what the
CMake build looks for).

```sh
cmake -S src/preserf-fortran -B src/preserf-fortran/build
cmake --build src/preserf-fortran/build
ctest --test-dir src/preserf-fortran/build --output-on-failure
```

## Cross-language wire-compat test

After building, the Python-side pytest at
[`tests/test_fortran_minimal.py`](../../tests/test_fortran_minimal.py)
runs the `test_minimal` binary and reads the resulting store back with
the Python reference reader at [`tests/_storage.py`](../../tests/_storage.py),
asserting that every metadata attribute and the field data survives the
round-trip:

```sh
uv run pytest tests/test_fortran_minimal.py -v
```

If the binary hasn't been built, the test is skipped.

## Conventions

See [`storage_mapping.md` §1.1][axis-order] for the axis-ordering rule
(`dims` is recorded in netCDF C-order, with the Fortran helper
transparently reversing the user-supplied `(iSize, jSize, kSize, lSize)`
tuple).
