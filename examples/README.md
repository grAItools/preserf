# preserf examples

Runnable, end-to-end examples of using `preserf` on real Fortran: annotate a
source file with `!$SER` directives, expand them with the `preserf` CLI,
compile the generated code against the `preserf_fortran` helper, run it, and
inspect the serialized store.

Each example is a **self-contained folder**. The shared parts (the
`!$SER`-annotated source and the verification script) live at its top level;
each way of building it lives in its own variant subfolder with a `run.sh`:

```
<example>/
├─ README.md          # the math/problem, the directives used, the variants
├─ <example>.f90      # !$SER-annotated source (preprocessor input), shared
├─ verify.py          # load the store, check it, and visualize it, shared
├─ cmake/             # build via the shipped PreserfFortran.cmake helper
│  ├─ README.md
│  ├─ CMakeLists.txt
│  ├─ run.sh          # preserf -> cmake build -> run
│  └─ clean.sh
└─ make/              # install the runtime, then build from a plain Makefile
   ├─ README.md
   ├─ Makefile
   ├─ run.sh          # cmake install -> make -> run
   └─ clean.sh
```

## Examples

- [`laplacian/`](laplacian/) — iterated Laplacian of a trigonometric field on a
  100×100 periodic grid, serialized per step and cross-checked against numpy.
  Two build variants: [`laplacian/cmake/`](laplacian/cmake/) (the
  `PreserfFortran.cmake` helper) and [`laplacian/make/`](laplacian/make/)
  (install the runtime, then build from a hand-written `Makefile`).

## Running

Examples use a dedicated pixi environment (`examples`) that adds the plotting
dependencies (`matplotlib`, `netcdf4`, `numpy`) and `cmake` on top of the
default Fortran/netcdf-fortran toolchain and the `preserf` CLI. Run a variant's
`run.sh`, then check the store it wrote with the shared `verify.py`:

```sh
pixi run -e examples bash examples/laplacian/cmake/run.sh
pixi run -e examples python examples/laplacian/verify.py \
    examples/laplacian/cmake/out/laplacian.nc
```

These examples are **standalone documentation** but every variant is also built
and run on CI as its own step (see `.github/workflows/ci.yml`) so a broken
example breaks the build. They are intentionally _not_ wired into `pixi run
verify` — verify covers the strict Python+Fortran suite, not the end-to-end
example builds. To exercise every example in one shot locally, use `pixi run
test-examples` (which also runs as part of `pixi run test-all`); it invokes
`examples/run-all.sh`, which finds every `run.sh` at any depth (so both the
`cmake/` and `make/` variants run) and executes it. Generated artifacts
(`build/`, `out/`, the make variant's `prefix/`) are gitignored and can be
cleared with each variant's `clean.sh`.
