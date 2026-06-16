# Laplacian example

Applies a 5-point Laplacian to a smooth field on a periodic grid in a short
**time loop**, serializes the input and output at every step with `preserf`,
then re-runs the same iteration in numpy to verify the dumped values and plot
the result.

The example ships in **two build-system variants** that compile the _same_
program from the _same_ shared source — they differ only in how they consume
the `preserf_fortran` runtime:

- [**`cmake/`**](cmake/) — the recommended path: consumes the runtime through
  the shipped `PreserfFortran.cmake` helper (one `preserf_add_fortran_target()`
  call does expand → compile → link). This is exactly what a `pip install
  preserf` user gets, and what CI exercises.
- [**`make/`**](make/) — installs the runtime once with CMake and then drives
  the preprocess → compile → link steps from a hand-written `Makefile`,
  demonstrating that the runtime is consumable from a non-CMake build system and
  spelling out the recipe the helper otherwise hides.

Shared between them, in this directory:

- [`laplacian.f90`](laplacian.f90) — the `!$SER`-annotated source (single
  source of truth, two build systems).
- [`verify.py`](verify.py) — loads the store, re-runs the iteration in numpy,
  checks every step, and plots the result.

## The problem

On the periodic domain `[0, 2π)²` sampled at 100×100 points (spacing
`h = 2π/100`), initialize

```
phi(x, y) = sin(2x) · cos(3y)
```

Each step computes the discrete Laplacian with the standard 5-point stencil
and **periodic wrap** on all four neighbours:

```
lap(i,j) = (phi(i+1,j) + phi(i-1,j) + phi(i,j+1) + phi(i,j-1) - 4·phi(i,j)) / h²
```

The operator is then applied **repeatedly**: the output of one step becomes the
input of the next. The example runs 3 steps by default (override with an
optional command-line count). At every step the input field `phi` and its
Laplacian `lap` are serialized into their own savepoint.

## The directives

Serialization is set up **once, above the time loop** (open the store, register
the two fields); the loop only writes savepoints:

```fortran
!$SER INIT directory=outdir prefix="laplacian" mode="w"
!$SER REGISTER phi real IJ
!$SER REGISTER lap real IJ

do t = 1, nsteps
   ! ... compute lap = Laplacian(phi) ...
   !$SER SAVEPOINT fields step=t
   !$SER DATA phi=phi
   !$SER DATA lap=lap
   phi = lap          ! apply the operator repeatedly
end do

!$SER CLEANUP
```

- `INIT … mode="w"` opens the store for writing at `outdir/laplacian.nc`.
- `REGISTER … real IJ` uses the `IJ` shortcut, which expands to the field's
  `(ie, je)` dimensions using the in-scope `ie`, `je`, `nboundlines` params.
- Each loop iteration's `SAVEPOINT fields step=t` plus the two `DATA`
  directives dump `phi` and `lap` into `/savepoints/sp_NNNNNN/{phi,lap}`, one
  savepoint group per step.

## What `verify.py` does

1. Loads the **initial field** from the first dumped step.
2. Re-runs the identical iterated Laplacian in numpy (`np.roll`-based periodic
   stencil).
3. Verifies at **every step** that the numpy input and output match the
   Fortran dump (to a tight floating-point tolerance), printing the per-step
   max difference.
4. Plots three panels for the final step: the Fortran Laplacian, the numpy
   Laplacian, and their difference (which is numerical noise — they agree to
   machine precision).

Both variants produce the same `out/laplacian.nc`, so the same `verify.py`
checks either one:

```sh
pixi run -e examples python examples/laplacian/verify.py \
    examples/laplacian/cmake/out/laplacian.nc       # or make/out/laplacian.nc
```

## Run it

Pick a variant and run its `run.sh` inside the `examples` pixi env:

```sh
pixi run -e examples bash examples/laplacian/cmake/run.sh   # CMake helper
pixi run -e examples bash examples/laplacian/make/run.sh    # install + plain make
```

See [`cmake/README.md`](cmake/README.md) and [`make/README.md`](make/README.md)
for what each writes and how it works.
