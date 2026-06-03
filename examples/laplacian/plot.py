#!/usr/bin/env python
"""Verify and plot the iterated-Laplacian preserf store.

Self-contained: reads the store with :mod:`netCDF4` directly (the documented
``/savepoints/sp_NNNNNN/<name>`` layout). The store holds one savepoint per
time step, each carrying the input field ``phi`` and its Laplacian ``lap``.

This script:

1. loads the initial field from the first dumped step,
2. re-runs the *same* iterated 5-point Laplacian in numpy, and
3. checks at every step that the numpy input/output match the Fortran dump.

It then plots the final-step Laplacian from Fortran, the same field recomputed
in numpy, and their difference. Run inside the ``examples`` pixi environment
(the store path argument defaults to ``out/laplacian.nc`` next to this file)::

    pixi run -e examples python examples/laplacian/plot.py

The argument is a local store as preserf emits it: a ``.nc`` file or a
``file://.../<prefix>.zarr#mode=nczarr,...`` NCZarr URL, so the same script
works for either backend.
"""

from __future__ import annotations

import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # headless: write a PNG, never open a window
import matplotlib.pyplot as plt
import netCDF4 as nc
import numpy as np

DEFAULT_STORE = Path(__file__).resolve().parent / "out" / "laplacian.nc"

# numpy and Fortran do the same float64 arithmetic, so the only divergence is
# sub-ULP rounding (e.g. gfortran FMA contraction) amplified over a few
# iterations — comfortably below this relative tolerance.
RTOL = 1e-9
ATOL = 1e-12


def laplacian(field: np.ndarray, h: float) -> np.ndarray:
    """5-point Laplacian with periodic wrap, matching the Fortran stencil.

    The store returns the field in ``[j, i]`` order (netcdf-fortran reverses
    the dimensions of ``phi(ie, je)``), so axis 1 is the ``i`` direction and
    axis 0 is the ``j`` direction. Neighbour terms are summed in the same
    E+W+N+S order as the Fortran expression to stay numerically close, but
    Fortran may reassociate or contract these operations (e.g. FMA), so the
    results are compared with a tolerance (RTOL/ATOL) rather than assuming
    bitwise-identical rounding.
    """
    return (
        np.roll(field, -1, axis=1)  # i+1 (E)
        + np.roll(field, 1, axis=1)  # i-1 (W)
        + np.roll(field, -1, axis=0)  # j+1 (N)
        + np.roll(field, 1, axis=0)  # j-1 (S)
        - 4.0 * field
    ) / h**2


def read_steps(url: str) -> list[dict]:
    """Read every savepoint as an ordered list of {step, phi, lap} dicts."""
    steps: list[dict] = []
    root = nc.Dataset(url, "r")
    root.set_auto_mask(False)  # plain ndarrays, not masked arrays
    try:
        if "savepoints" not in root.groups:
            raise SystemExit(f"no /savepoints group in {url}")
        sp_root = root.groups["savepoints"]
        for name in sorted(sp_root.groups):  # sp_000000, sp_000001, ...
            grp = sp_root.groups[name]
            step = (
                int(grp.getncattr("step"))
                if "step" in grp.ncattrs()
                else len(steps) + 1
            )
            steps.append(
                {
                    "step": step,
                    "phi": np.asarray(grp.variables["phi"][...]),
                    "lap": np.asarray(grp.variables["lap"][...]),
                }
            )
    finally:
        root.close()
    if not steps:
        raise SystemExit(f"no savepoints found in {url}")
    return steps


def main(argv: list[str]) -> int:
    url = argv[1] if len(argv) > 1 else str(DEFAULT_STORE)
    steps = read_steps(url)

    # Grid spacing from the field shape: i is axis 1 (columns) -> ie = ncols.
    # The example uses a square domain (je == ie), so the same h applies to
    # both directions; a non-square grid would need a separate hj.
    ie = steps[0]["phi"].shape[1]
    h = 2.0 * np.pi / ie

    # Reproduce the Fortran iteration in numpy, starting from the dumped
    # initial field, and check input + output at every step.
    phi_py = steps[0]["phi"].copy()
    all_ok = True
    for s in steps:
        lap_py = laplacian(phi_py, h)
        in_ok = np.allclose(s["phi"], phi_py, rtol=RTOL, atol=ATOL)
        out_ok = np.allclose(s["lap"], lap_py, rtol=RTOL, atol=ATOL)
        in_err = np.abs(s["phi"] - phi_py).max()
        out_err = np.abs(s["lap"] - lap_py).max()
        print(
            f"step {s['step']}: input match={in_ok} (max|Δ|={in_err:.2e})  "
            f"output match={out_ok} (max|Δ|={out_err:.2e})"
        )
        all_ok = all_ok and in_ok and out_ok
        phi_py = lap_py  # the operator is applied repeatedly

    if not all_ok:
        print("MISMATCH: numpy and Fortran results diverged beyond tolerance")
        return 1
    print(f"OK: all {len(steps)} timesteps match between Fortran and numpy.")

    # Plot the final-step Laplacian from Fortran, from numpy, and the diff.
    fortran_final = steps[-1]["lap"]
    python_final = lap_py
    diff = fortran_final - python_final
    vmax = np.abs(fortran_final).max()
    # Symmetric, non-degenerate colour scale for the difference: it is ~0 when
    # Fortran and numpy agree, so floor the limit to keep the panel readable.
    dmax = np.abs(diff).max()
    dlim = dmax if dmax > 0.0 else 1.0

    fig, axes = plt.subplots(1, 3, figsize=(14, 4.2))
    panels = (
        ("Fortran lap (final)", fortran_final, "RdBu_r", -vmax, vmax),
        ("numpy lap (final)", python_final, "RdBu_r", -vmax, vmax),
        (f"difference (max|Δ|={dmax:.1e})", diff, "PuOr", -dlim, dlim),
    )
    for ax, (title, field, cmap, vmn, vmx) in zip(axes, panels, strict=True):
        # netCDF4 returns the field as [j, i]; plot it directly (no transpose)
        # to put i on the x-axis and j on the y-axis.
        im = ax.imshow(
            field, origin="lower", cmap=cmap, aspect="equal", vmin=vmn, vmax=vmx
        )
        ax.set_title(title)
        ax.set_xlabel("i")
        ax.set_ylabel("j")
        fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    fig.suptitle(f"preserf example: iterated Laplacian after {len(steps)} steps")
    fig.tight_layout()

    # Write the PNG next to the store. Strip any "file://" scheme and NCZarr
    # URL fragment (e.g. ".../laplacian.zarr#mode=nczarr,zarr2") first so the
    # derived path is sane for both a plain .nc file and a local zarr URL.
    store_path = url.split("#", 1)[0].removeprefix("file://")
    out_png = Path(store_path).with_suffix(".png")
    fig.savefig(out_png, dpi=120)
    print(f"Wrote {out_png}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
