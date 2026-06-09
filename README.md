# preserf - Preprocessor for Fortran data serialization directives

`preserf` is a Python preprocessor that expands `!$SER` directives in Fortran
source into explicit serialization calls.

The repository contains two main pieces:

- `src/preserf/`: the preprocessor engine and CLI.
- `src/preserf/fortran/`: Fortran helper modules that provide the runtime API
  targeted by generated code.

## What it does

- Parses `!$SER` directives using a two-pass analysis/generation model.
- Injects the required `USE` imports and guarded serialization blocks.
- Expands directives such as `INIT`, `SAVEPOINT`, `DATA`, `REGISTER`, and
  related forms into Fortran API calls.
- Supports CLI processing of single files or directory trees.

## Using preserf in your build

`pip install preserf` ships the Fortran runtime sources and a CMake helper
inside the package, so you can compile preserf-generated Fortran without
cloning this repository.

**Prerequisites** (unchanged from a source checkout): a Fortran compiler,
[`netcdf-fortran`](https://docs.unidata.ucar.edu/netcdf-fortran/) discoverable
via pkg-config, and CMake ≥ 3.20. `preserf` does not bundle or build these —
the runtime is shipped as **source** and compiled by your own project against
your own `netcdf-fortran` (compiler-specific `.mod` files and prebuilt
libraries are deliberately not distributed).

**Discover the bundled files.** The package exposes their location both as a
CLI command and a Python API (the numpy `get_include()` pattern):

```sh
preserf --fortran-dir     # absolute path to the runtime sources
preserf --cmake-helper    # absolute path to the CMake helper module
```

```python
import preserf
preserf.get_fortran_dir()    # -> Path to the runtime sources
preserf.get_cmake_helper()   # -> Path to PreserfFortran.cmake
```

**Wire it into CMake.** Include the shipped helper and call one function — it
runs `preserf` to expand your `!$SER` sources, compiles and links them against
the runtime, and applies the `SERIALIZE` definition and required flags:

```cmake
cmake_minimum_required(VERSION 3.20)
project(my_app LANGUAGES Fortran)

execute_process(COMMAND preserf --cmake-helper
                OUTPUT_VARIABLE PRESERF_CMAKE_HELPER
                OUTPUT_STRIP_TRAILING_WHITESPACE)
include("${PRESERF_CMAKE_HELPER}")

preserf_add_fortran_target(my_app SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/my_app.f90)
```

Building the target expands the directives and produces a runnable binary.
The same helper drives the in-tree [laplacian example](examples/laplacian/)
and the Fortran e2e test, so this is exactly the recipe CI exercises.

**Alternative: build and install the runtime, then `find_package` it.** If you
prefer to compile the runtime once and consume it as an installed library
(rather than rebuilding it from source inside every project), the bundled
`CMakeLists.txt` is a standalone, installable CMake project:

```sh
cmake -S "$(preserf --fortran-dir)" -B build -DCMAKE_INSTALL_PREFIX=/your/prefix
cmake --build build --target install
```

This installs the `preserf_fortran` library, its compiled Fortran `.mod`
interface files, and a CMake package config. A downstream project then consumes
it the standard way:

```cmake
find_package(preserf_fortran REQUIRED)        # add the prefix to CMAKE_PREFIX_PATH
target_link_libraries(my_app PRIVATE preserf::preserf_fortran)
```

Linking `preserf::preserf_fortran` pulls in the installed modules and the
transitive `netcdf-fortran` flags. The `.mod` files are compiler- and
version-specific, so build the consumer with the **same Fortran compiler** that
produced the install. Expanding your own `!$SER` sources is still the
preprocessor's job — run `preserf` (or the helper above) on them and link the
result against this target.

**Choosing the storage backend at runtime.** When the running binary does not
pass an explicit `backend=` to `ppser_initialize` (as pp_ser / Serialbox
`!$SER INIT` call sites do not), the on-disk format is selected from the
`PRESERF_BACKEND` environment variable — `netcdf4` (default) or `nczarr-v2`:

```sh
PRESERF_BACKEND=nczarr-v2 ./my_app   # write a Zarr V2 store instead of .nc
```

## Development commands

- `pixi run test-py`: run the fast Python test suite.
- `pixi run test-all`: run the Python suite, the native Fortran ctest suite, and every example.
- `pixi run lint`: run static checks.
- `pixi run fmt`: apply formatting.
- `pixi run verify`: run the full verification gate (fmt-check + lint + typecheck + Python tests + Fortran build/ctest).

## Key documentation

- Project architecture overview: [docs/architecture.md](docs/architecture.md)
- Directive grammar and expansion contract:
  [docs/references/directives_specification.md](docs/references/directives_specification.md)
- Storage model mapping:
  [docs/references/storage_mapping.md](docs/references/storage_mapping.md)
- Fortran runtime helpers and compatibility details:
  [src/preserf/fortran/README.md](src/preserf/fortran/README.md)
- Testing strategy: [docs/testing.md](docs/testing.md)
- Code style guide: [docs/style.md](docs/style.md)
- Architecture decision records: [docs/adr/README.md](docs/adr/README.md)
