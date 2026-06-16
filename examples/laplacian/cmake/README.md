# Laplacian example — CMake helper consumer

Builds the [shared Laplacian program](../laplacian.f90) using the **shipped
`PreserfFortran.cmake` helper** — the recommended way to consume preserf from a
CMake project, and exactly what a `pip install preserf` user gets.

The whole build is one helper call in [`CMakeLists.txt`](CMakeLists.txt):

```cmake
include(.../src/preserf/fortran/cmake/PreserfFortran.cmake)   # `preserf --cmake-helper`
preserf_add_fortran_target(laplacian SOURCES ../laplacian.f90)
```

`preserf_add_fortran_target()` does the whole recipe for you: it runs the
`preserf` CLI to expand the `!$SER` directives, compiles the generated `.F90`
against the `preserf_fortran` runtime, links it, and applies the `SERIALIZE`
definition and the required F2008 / `-cpp` / line-length flags. The runtime
itself is built from source via `add_subdirectory` (no separate install step) —
contrast the [`make/`](../make/) variant, which installs the runtime first.

> The example includes the helper by its in-tree path
> (`../../../src/preserf/fortran/cmake/PreserfFortran.cmake`), which is the same
> layout the wheel ships, so this example cannot drift from what users get. An
> installed consumer instead discovers it with `preserf --cmake-helper`.

## Run it

```sh
pixi run -e examples bash examples/laplacian/cmake/run.sh
pixi run -e examples python examples/laplacian/verify.py \
    examples/laplacian/cmake/out/laplacian.nc
```

`run.sh` configures + builds (which expands the directives), then runs the
binary. It writes, under this folder:

- `build/laplacian.F90` — the expanded source (open it to see the `!$SER`
  directives turned into explicit serialization calls).
- `build/laplacian` — the compiled binary. Run it as
  `build/laplacian <outdir> [nsteps]` to change the iteration count.
- `out/laplacian.nc` — the store, with one savepoint per step.

`verify.py` (shared, one level up) prints the per-step verification and writes
`out/laplacian.png` with the three-panel comparison. `clean.sh` removes
`build/` and `out/`.
