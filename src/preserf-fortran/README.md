# preserf-fortran

Fortran helper modules that pp_ser-generated `!$SER` directive code links
against. Writes the group-per-savepoint NetCDF4 / NCZarr layout documented
in [`../../development/references/storage_mapping.md`][mapping].

[mapping]: ../../development/references/storage_mapping.md

## Modules

| Module           | Purpose                                                                  |
|------------------|--------------------------------------------------------------------------|
| `m_preserf`      | Main API: `fs_register_field`, `fs_create_savepoint`, `fs_write_field`, `fs_read_field`, `fs_add_savepoint_metainfo`, `fs_add_serializer_metainfo`, `fs_enable_serialization`, `fs_disable_serialization`. |
| `utils_preserf`  | Lifecycle + module-level state (`ppser_serializer`, `ppser_savepoint`, `ppser_initialize`, `ppser_finalize`, `ppser_set_mode`, `ppser_get_mode`). |
| `m_serialize`    | Drop-in re-export of `m_preserf` under Serialbox's historical module name. |
| `utils_ppser`    | Drop-in re-export of `utils_preserf` under Serialbox's historical module name. |

The `m_serialize` / `utils_ppser` aliases let unchanged pp_ser output
compile against preserf without further preprocessor flags.

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
  (`fs_read_field(s, sp, name, data, perturb)`). v0.1 reads the field
  as-is and ignores the perturbation magnitude.
- `fs_enable_serialization` / `fs_disable_serialization` gate every
  fs_* I/O entry point at runtime; `fs_serialization_status()` exposes
  the flag for tests.

### Known limitations / mismatches with pp_ser-generated code

The first slice trades a few corners of pp_ser's contract for a small
implementation. These are tracked as follow-up PRs:

1. **Read mode is partial.** `ppser_initialize(directory, prefix, 'r')`
   opens the store read-only and `fs_read_field(...)` works against it,
   which is enough for the cross-language round-trip test in
   `tests/test_fortran_minimal.py`. However, pp_ser-generated code
   calls `fs_register_field`, `fs_create_savepoint`, and the metainfo
   helpers unconditionally (outside the `SELECT CASE (ppser_get_mode())`
   that wraps DATA blocks). Those routines currently always **create**
   the corresponding netCDF object and will fail or duplicate when
   pointed at an existing read-only store. The follow-up PR will switch
   them to a "create-or-resolve-and-validate" shape.
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
- NCZarr URL targets (the helper currently writes plain `.nc`; switching
  to `file://...#mode=nczarr,zarr2` requires only an additional
  `nf90_create` mode flag and is a one-line change once we add a test).

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
