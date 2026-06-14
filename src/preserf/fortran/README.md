# preserf-fortran

Fortran helper modules that pp_ser-generated `!$SER` directive code links
against, following the group-per-savepoint layout documented in
[`../../docs/references/storage_mapping.md`][mapping]. The helper writes
**NetCDF4 stores** (`.nc` files, the default) or **NCZarr V2 stores**
(`.zarr` directory stores), selected by the `backend` keyword on
`ppser_initialize` (Slice E); the same schema serves both (ADR 0002).
The `nczarr-v2` backend resolves a relative `directory` (e.g. `./ser_data`)
to absolute against the CWD before building its `file://` URL, so it accepts
the same relative directories as the NetCDF4 backend. Zarr V3 stays
forward-compatible but deferred until netcdf-c's NCZarr V3 PR lands.

[mapping]: ../../docs/references/storage_mapping.md

## Platform assumptions

The helper targets a POSIX environment:

- **Write-mode output-directory creation** shells out to `mkdir -p` via
  `EXECUTE_COMMAND_LINE` (`utils_preserf.f90`, `preserf_ensure_directory`) —
  Fortran has no intrinsic `mkdir`.
- **Relative-directory resolution** for the `nczarr-v2` `file://` URL binds
  the libc `getcwd(3)` directly (`utils_preserf.f90`, the `c_getcwd`
  interface) — there is no F2008-standard CWD intrinsic.

## Modules

| Module          | Purpose                                                                                                                                                                                                    |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `m_preserf`     | Main API: `fs_register_field`, `fs_create_savepoint`, `fs_write_field`, `fs_read_field`, `fs_add_savepoint_metainfo`, `fs_add_serializer_metainfo`, `fs_enable_serialization`, `fs_disable_serialization`. |
| `utils_preserf` | Lifecycle + module-level state (`ppser_serializer`, `ppser_savepoint`, `ppser_initialize`, `ppser_finalize`, `ppser_set_mode`, `ppser_get_mode`).                                                          |
| `m_serialize`   | Drop-in re-export of `m_preserf` under Serialbox's historical module name.                                                                                                                                 |
| `utils_ppser`   | Drop-in re-export of `utils_preserf` under Serialbox's historical module name.                                                                                                                             |

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
  read the stored field, then apply symmetric multiplicative noise
  `data*(1 + perturb*(2*r - 1))` (`r ~ U[0,1)` via `RANDOM_NUMBER`),
  matching pp_ser's CASE(2) read-perturb semantics. The generator is
  left unseeded, so its initial seed — and thus whether the noise
  repeats across runs — is processor-dependent (some compilers/runtimes
  are deterministic, others vary); call `random_seed` before reading if
  you need control over the sequence (a fixed `put=` seed for
  reproducibility, or a clock-derived seed for variability). Tests
  assert bounds, not exact values.
- `fs_enable_serialization` / `fs_disable_serialization` gate every
  fs_* I/O entry point at runtime; `fs_serialization_status()` exposes
  the flag for tests.

### Known limitations / mismatches with pp_ser-generated code

A corner of pp_ser's contract remains unimplemented, tracked as a
follow-up:

1. **Append mode (`'a'`) is rejected** rather than half-implemented.
   It needs `nf90_inq_grps` index resumption that the netcdf-fortran
   4.5.x wrapper makes awkward.

Out of scope for this PR (tracked as follow-ups):

- Full type-coverage matrix (bool / i32 / i64 / f32 + 0D..4D for fields,
  array metainfo variants).
- `fs_write_kbuff` (k-buffer / `!$SER DATA_KBUFF`).
- `fs_RegisterAllTracers` and the tracer write API (`!$SER TRACER`).
- `fs_Option` (`!$SER OPTION`).
- Explicit `directory_ref` / `prefix_ref` test coverage. The integration
  test exercises only the implicit same-store reference path
  (`ppser_initialize(..., 'r')` opens `ppser_serializer_ref` against the
  same store). The explicit-ref branch — which `ppser_initialize`
  deliberately orders to open the read-only reference _before_ the
  writable target so a bad reference path doesn't truncate an existing
  file — is not yet tested. Covering "bad reference path doesn't
  clobber the main store" needs a separate Fortran test program that's
  expected to `error stop` (a `WILL_FAIL` ctest entry) plus a Python
  assertion that the writable target survived.

[axis-order]: ../../docs/references/storage_mapping.md

## Building

Requires `cmake` ≥ 3.20, a Fortran compiler (tested with gfortran 13),
and `netcdf-fortran` development files (`libnetcdff-dev` on
Debian/Ubuntu; the `netcdf-fortran.pc` pkg-config file is what the
CMake build looks for).

```sh
# Build the library + its native tests (entry point is the tests-fortran/ tree)
cmake -S tests-fortran -B build/preserf-fortran
cmake --build build/preserf-fortran
ctest --test-dir build/preserf-fortran --output-on-failure
```

Or, via pixi:

```sh
pixi run build-fortran
pixi run test-fortran
```

### Installing as a library

The `CMakeLists.txt` in this directory is also a standalone, installable
project. Building its `install` target lays down the library, the compiled
`.mod` interface files, and a CMake package config:

```sh
cmake -S . -B build/install -DCMAKE_INSTALL_PREFIX=/your/prefix
cmake --build build/install --target install
```

A downstream project consumes the install with `find_package`:

```cmake
find_package(preserf_fortran REQUIRED)        # prefix on CMAKE_PREFIX_PATH
target_link_libraries(my_app PRIVATE preserf::preserf_fortran)
```

`netcdf-fortran` is re-discovered via pkg-config by the generated package
config, so the consumer needs it on its pkg-config path too. The `.mod` files
are compiler-specific — build the consumer with the same Fortran compiler.
Install rules are emitted only when this tree is the top-level CMake project
(`cmake -S .`); when it is pulled in via `add_subdirectory()` — the shipped
`PreserfFortran.cmake` helper, the example, the native tests — no install rules
are added (override with `-DPRESERF_FORTRAN_INSTALL=ON/OFF`).

## Cross-language wire-compat test

After building, the Python-side pytest at
[`tests/integration_tests/test_fortran_wire_compat.py`](../../tests/integration_tests/test_fortran_wire_compat.py)
runs the `preserf_fortran_test_minimal` binary and reads the resulting
store back with the Python reference reader at
[`tests/_support/storage.py`](../../tests/_support/storage.py), asserting
that every metadata attribute and the field data survives the round-trip:

```sh
pixi run test-py-integration
```

If the binary hasn't been built, the test is skipped.

## Conventions

See [`storage_mapping.md` §1.1][axis-order] for the axis-ordering rule
(`dims` is recorded in netCDF C-order, with the Fortran helper
transparently reversing the user-supplied `(iSize, jSize, kSize, lSize)`
tuple).
