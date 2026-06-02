#!/usr/bin/env python
"""Load a preserf store and plot the Laplacian example fields.

Self-contained: reads the store with :mod:`netCDF4` directly (the documented
``/savepoints/sp_NNNNNN/<name>`` layout) and renders ``phi`` and ``lap`` as
side-by-side heatmaps. Run inside the ``examples`` pixi environment::

    pixi run -e examples python examples/laplacian/plot.py examples/laplacian/out/laplacian.nc

The argument may be a ``.nc`` file or an NCZarr URL string, so the same script
works for either backend. It also reports ``max|lap - (-13*phi)| / max|phi|``,
which should be small (O(h^2) discretization error) for this field.
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


def read_field(root: nc.Dataset, savepoint: str, name: str) -> np.ndarray:
    """Return the field `name` from `/savepoints/<savepoint>` as an array."""
    sp = root.groups["savepoints"].groups[savepoint]
    return np.asarray(sp.variables[name][...])


def main(argv: list[str]) -> int:
    url = argv[1] if len(argv) > 1 else str(DEFAULT_STORE)

    root = nc.Dataset(url, "r")
    root.set_auto_mask(False)  # plain ndarrays, not masked arrays
    try:
        phi = read_field(root, "sp_000000", "phi")
        lap = read_field(root, "sp_000000", "lap")
    finally:
        root.close()

    for label, field in (("phi", phi), ("lap", lap)):
        print(
            f"{label}: shape={field.shape} "
            f"min={field.min():.4g} max={field.max():.4g} mean={field.mean():.4g}"
        )

    # Analytic check: continuous Laplacian of sin(2x)cos(3y) is -13*phi.
    denom = np.abs(phi).max()
    rel_err = np.abs(lap - (-13.0 * phi)).max() / denom if denom else float("nan")
    print(f"max |lap - (-13*phi)| / max|phi| = {rel_err:.4g}  (expect O(h^2))")

    fig, axes = plt.subplots(1, 2, figsize=(10, 4.2))
    for ax, (label, field) in zip(axes, (("phi", phi), ("lap", lap))):
        im = ax.imshow(field.T, origin="lower", cmap="RdBu_r", aspect="equal")
        ax.set_title(label)
        ax.set_xlabel("i")
        ax.set_ylabel("j")
        fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    fig.suptitle("preserf example: Laplacian of sin(2x)cos(3y)")
    fig.tight_layout()

    # Write the PNG next to the store. Strip any "file://" scheme and NCZarr
    # URL fragment (e.g. ".../laplacian.zarr#mode=nczarr,zarr2") first so the
    # derived path is sane for both a plain .nc file and a zarr URL.
    store_path = url.split("#", 1)[0].removeprefix("file://")
    out_png = Path(store_path).with_suffix(".png")
    fig.savefig(out_png, dpi=120)
    print(f"Wrote {out_png}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
