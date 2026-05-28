# Tool bootstrap

## Required tools

`preserf` uses **pixi** as the single entry point. There is no separate
language-version manager (`asdf`/`mise`/`pyenv`) to set up: pixi resolves
the Python interpreter, the Fortran/C/C++ compilers, NetCDF, and every
dev tool from `conda-forge`, pinned in `pixi.toml` / `pixi.lock`.

- **pixi** — project / environment / task runner. Install below.
- Everything else (Python ≥3.12, `fortran-compiler`, `netcdf-fortran`,
  `cmake`, `dprint`, `ruff`, `mypy`, `pytest`, `fprettify`, `numpy`) is
  provisioned by `pixi install` — do not install these by hand.

Supported platforms: `linux-64`, `linux-aarch64`, `osx-arm64`.

## Install `pixi`

[`pixi`](https://pixi.sh) — conda-ecosystem project manager.

```sh
# macOS / Linux:
curl -fsSL https://pixi.sh/install.sh | sh
exec $SHELL                # reload shell so $PATH picks up ~/.pixi/bin

# Windows (PowerShell):
#   iwr -useb https://pixi.sh/install.ps1 | iex
# Or via package manager — see https://pixi.sh/latest/#installation

pixi --version             # verify
```

## Materialise the environment

From the repo root:

```sh
pixi install               # solve + install from pixi.toml / pixi.lock
```

This builds the `default` environment (the runtime deps plus the editable
`preserf` install). The `dev` environment — lint/format/type/test tooling
— is provisioned on first use; the project's tasks already target it via
`default-environment = "dev"`, so you do not need to activate it manually.

## Verify the bootstrap

Run the canonical verification gate (fmt-check + lint + typecheck + test):

```sh
pixi run verify
```

If it succeeds on a fresh clone, the Python side of the bootstrap worked.

## Fortran helper (optional)

The Fortran helper modules under `src/preserf-fortran/` are built and
tested through CMake/CTest, driven by pixi tasks:

```sh
pixi run build-fortran     # cmake configure + build into build/preserf-fortran
pixi run test-fortran      # ctest --output-on-failure
```

The cross-language wire-compat test
(`tests/integration_tests/test_fortran_wire_compat.py`) skips when the
Fortran binary is absent, so `pixi run verify` passes without the Fortran
build; run the two tasks above to exercise the full Python↔Fortran path.
