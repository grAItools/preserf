# Laplacian example

Applies a 5-point Laplacian to a smooth field on a periodic grid in a short
**time loop**, serializes the input and output at every step with `preserf`,
then re-runs the same iteration in numpy to verify the dumped values and plot
the result.

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

## What `plot.py` does

1. Loads the **initial field** from the first dumped step.
2. Re-runs the identical iterated Laplacian in numpy (`np.roll`-based periodic
   stencil).
3. Verifies at **every step** that the numpy input and output match the
   Fortran dump (to a tight floating-point tolerance), printing the per-step
   max difference.
4. Plots three panels for the final step: the Fortran Laplacian, the numpy
   Laplacian, and their difference (which is numerical noise — they agree to
   machine precision).

## Run it

```sh
pixi run -e examples bash examples/laplacian/run.sh
pixi run -e examples python examples/laplacian/plot.py examples/laplacian/out/laplacian.nc
```

`run.sh` writes three things under this folder:

- `build/laplacian.F90` — the expanded source (open it to see the `!$SER`
  directives turned into explicit serialization calls).
- `build/laplacian` — the compiled binary. Run it as
  `build/laplacian <outdir> [nsteps]` to change the iteration count.
- `out/laplacian.nc` — the store, with one savepoint per step.

`plot.py` prints the per-step verification and writes `out/laplacian.png` with
the three-panel comparison.
