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
├─ verify.py          # load the store, check it, and visualize it
└─ clean.sh           # remove the build/ and out/ artifacts
```

## Examples

- [`laplacian/`](laplacian/) — iterated Laplacian of a trigonometric field on a
  100×100 periodic grid, serialized per step and cross-checked against numpy.

## Running

Examples use a dedicated pixi environment (`examples`) that adds the plotting
dependencies (`matplotlib`, `netcdf4`, `numpy`) and `cmake` on top of the
default Fortran/netcdf-fortran toolchain and the `preserf` CLI:

```sh
pixi run -e examples bash examples/laplacian/run.sh
pixi run -e examples python examples/laplacian/verify.py examples/laplacian/out/laplacian.nc
```

These examples are **standalone documentation** but every example is
also built and run on CI as its own step (see `.github/workflows/ci.yml`)
so a broken example breaks the build. They are intentionally _not_
wired into `pixi run verify`, which stays on the fast Python suite.
To exercise every example in one shot locally, use
`pixi run test-examples` (which also runs as part of `pixi run test-all`);
it invokes `examples/run-all.sh`, which iterates each subfolder and runs
its `run.sh`. Generated artifacts (`build/`, `out/`) are gitignored and
can be cleared with each example's `clean.sh`.
