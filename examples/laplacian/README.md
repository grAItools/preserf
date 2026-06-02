# Laplacian example

Computes the Laplacian of a smooth field on a periodic grid, serializes both
the field and its Laplacian with `preserf`, and plots them.

## The problem

On the periodic domain `[0, 2π)²` sampled at 100×100 points (spacing
`h = 2π/100`), initialize

```
phi(x, y) = sin(2x) · cos(3y)
```

Its continuous Laplacian is analytic:

```
∇²phi = (∂²/∂x² + ∂²/∂y²) phi = (-4 - 9)·phi = -13·phi
```

The program computes the discrete Laplacian with the standard 5-point stencil
and **periodic wrap** on all four neighbours:

```
lap(i,j) = (phi(i+1,j) + phi(i-1,j) + phi(i,j+1) + phi(i,j-1) - 4·phi(i,j)) / h²
```

so `lap ≈ -13·phi` to `O(h²)`. `plot.py` reports that error as a sanity check
that the data survived the preprocess → compile → run → serialize round-trip.

## The directives

```fortran
!$SER INIT directory=outdir prefix="laplacian" mode="w"
!$SER REGISTER phi real IJ
!$SER REGISTER lap real IJ
!$SER SAVEPOINT fields step=0
!$SER DATA phi=phi
!$SER DATA lap=lap
!$SER CLEANUP
```

- `INIT … mode="w"` opens the store for writing at `outdir/laplacian.nc`.
- `REGISTER … real IJ` uses the `IJ` shortcut, which expands to the field's
  `(ie, je)` dimensions using the in-scope `ie`, `je`, `nboundlines` params.
- `SAVEPOINT fields` then two `DATA` directives dump both fields into
  `/savepoints/sp_000000/{phi,lap}`.

## Run it

```sh
pixi run -e examples bash examples/laplacian/run.sh
pixi run -e examples python examples/laplacian/plot.py examples/laplacian/out/laplacian.nc
```

`run.sh` writes three things under this folder:

- `build/laplacian.F90` — the expanded source (open it to see the `!$SER`
  directives turned into explicit serialization calls).
- `build/laplacian` — the compiled binary.
- `out/laplacian.nc` — the store.

`plot.py` reads the store, prints per-field min/max/mean and the analytic
error, and writes `out/laplacian.png` with two heatmaps.
