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

## Thread safety — serial use only

**The serialization runtime is not thread-safe.** Run `!$SER` directives
from serial regions only. The helper keeps `save`d, module-level mutable
state (the `ppser_serializer` / `ppser_serializer_ref` / `ppser_savepoint`
structs, the `serialisation_enabled` gate, the tracer and k-buffer
registries, and the shared `RANDOM_NUMBER` state used by read-perturb) that
is mutated with no synchronization. Concurrent `!$SER DATA` from multiple
OpenMP threads races on all of it and can corrupt the store or the perturb
sequence.

If a host model issues `!$SER` from inside an OpenMP parallel region, guard
it so at most one thread serializes at a time (e.g. wrap the directive in
`!$omp critical` or `!$omp master`). In-region, multi-threaded serialization
is out of scope for this helper; see
[ADR 0005](../../docs/adr/0005-serialization-runtime-is-serial-only.md).

## Modules

| Module          | Purpose                                                                                                                                                                                                    |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `m_preserf`     | Main API: `fs_register_field`, `fs_create_savepoint`, `fs_write_field`, `fs_read_field`, `fs_add_savepoint_metainfo`, `fs_add_serializer_metainfo`, `fs_enable_serialization`, `fs_disable_serialization`. |
| `utils_preserf` | Lifecycle + module-level state (`ppser_serializer`, `ppser_savepoint`, `ppser_initialize`, `ppser_finalize`, `ppser_set_mode`, `ppser_get_mode`).                                                          |
| `m_serialize`   | Drop-in re-export of `m_preserf` under Serialbox's historical module name.                                                                                                                                 |
| `utils_ppser`   | Drop-in re-export of `utils_preserf` under Serialbox's historical module name.                                                                                                                             |

The `m_serialize` / `utils_ppser` aliases preserve the historical
module identifiers pp_ser-generated source imports.

## Implemented surface

The helper implements the full pp_ser directive surface:

- `fs_register_field` records `/_fields/<name>` with `type_id` + `dims`
  (in C-order — see [§1.1 of the storage mapping][axis-order]) and any
  non-zero halo attributes. Re-registration is idempotent (Serialbox
  parity). Includes a contiguous-prefix check on the
  `(iSize, jSize, kSize, lSize)` tuple.
- `fs_create_savepoint` allocates the next `/savepoints/sp_NNNNNN`
  group with `name` and `_preserf_savepoint_index` attributes.
- `fs_add_savepoint_metainfo` and `fs_add_serializer_metainfo` are
  overloaded for the six scalar Serialbox `TypeID`s
  (`logical`, `integer(int32)`, `integer(int64)`, `real(real32)`,
  `real(real64)`, `character(len=*)`) plus array-of-scalar variants.
  Reserved keys (`_preserf_*` prefix, `__preserf_type_id` suffix, plus
  `name` on savepoint groups) are rejected.
- `fs_write_field` / `fs_read_field` — full type-coverage matrix:
  `logical`, `integer(int32)`, `integer(int64)`, `real(real32)`,
  `real(real64)`, in 0D through 4D. Each I/O call validates the runtime
  shape and dtype against the registered `/_fields/<name>` metadata
  before touching the store. `fs_read_field` has both the 4-argument
  form and the 5-argument read-perturb form
  (`fs_read_field(s, sp, name, data, perturb)`). The 5-arg overloads
  apply symmetric multiplicative noise `data*(1 + perturb*(2*r - 1))`
  (`r ~ U[0,1)` via `RANDOM_NUMBER`), matching pp_ser's CASE(2)
  semantics. The generator is left unseeded; call `random_seed` before
  reading if you need a controlled sequence.
- `fs_write_kbuff` — k-buffer (`!$SER DATA_KBUFF`) write API.
- `fs_RegisterAllTracers` / `ppser_write_tracer_*` — tracer write API
  (`!$SER TRACER`, `!$SER REGISTERTRACERS`).
- `fs_Option` — runtime option knob (`!$SER OPTION verbosity=N`).
- `fs_enable_serialization` / `fs_disable_serialization` gate every
  fs_* I/O entry point at runtime; `fs_serialization_status()` exposes
  the flag for tests.

### Known limitations

- **Append mode (`'a'`) is rejected** rather than half-implemented.
  It needs `nf90_inq_grps` index resumption that the netcdf-fortran
  4.5.x wrapper makes awkward. Tracked in
  [`specs/2026-05-fortran-append-mode/`](../../specs/2026-05-fortran-append-mode/).
- **Explicit `directory_ref` / `prefix_ref` test coverage is incomplete.**
  The integration test exercises only the implicit same-store reference
  path. The explicit-ref branch is untested end-to-end.
- **Thread safety:** the module-level serializer state is not thread-safe.
  `!$SER` directives must execute from serial regions only (or be guarded
  with `!$omp critical` / `!$omp master`).
- **POSIX assumptions:** directory creation uses a `mkdir -p` shell-out;
  CWD resolution uses `getcwd`. These are not portable to non-POSIX
  platforms (Windows).

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
