# preserf examples

Runnable, end-to-end examples of using `preserf` on real Fortran: annotate a
source file with `!$SER` directives, expand them with the `preserf` CLI,
compile the generated code against the `preserf_fortran` helper, run it, and
inspect the serialized store.

Each example is a **self-contained subfolder** following the same shape:

```
<example>/
├─ README.md          # the math/problem, the directives used, how to run
├─ <example>.f90      # !$SER-annotated source (preprocessor input)
├─ CMakeLists.txt     # builds the generated .F90 against preserf_fortran
├─ run.sh             # preserf -> cmake build -> run
└─ plot.py            # load the store and visualize it
```

## Examples

- [`laplacian/`](laplacian/) — Laplacian of a trigonometric field on a 100×100
  periodic grid, serialized and plotted.

## Running

Examples use a dedicated pixi environment (`examples`) that adds the plotting
dependencies (`matplotlib`, `netcdf4`, `numpy`) and `cmake` on top of the
default Fortran/netcdf-fortran toolchain and the `preserf` CLI:

```sh
pixi run -e examples bash examples/laplacian/run.sh
pixi run -e examples python examples/laplacian/plot.py examples/laplacian/out/laplacian.nc
```

These examples are **standalone documentation**. They are intentionally _not_
wired into `pixi run verify` or CI — run them by hand. Generated artifacts
(`build/`, `out/`) are gitignored.
