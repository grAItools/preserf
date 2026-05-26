# Style guide

> One worked example beats a page of prose. Show, don't tell.

## Tooling

`preserf` mixes Python and Fortran; both are auto-formatted and statically
checked. Configuration lives next to the code, not here — this file
documents intent.

- **Python:** `ruff` (lint + format, config in `pyproject.toml`),
  `mypy` strict mode targeting Python 3.12 (`pyproject.toml` `[tool.mypy]`).
- **Fortran:** `fprettify` for formatting (no separate linter; gfortran
  `-std=f2008` enforces standards conformance at build time).
- **Markdown, JSON, TOML:** `dprint` (config in `dprint.json`).

The PostToolUse hook in `.claude/settings.json` runs `pixi run fmt-py-src`
or `pixi run fmt-f-src` on every Write/Edit of a `.py` / `.f90` file, so
formatting drift never reaches a commit. The Stop hook runs
`pixi run verify` (fmt-check + lint + typecheck + test) before letting
the agent claim "done".

## Conventions

- **Tests are the spec.** If you change behaviour, change a test first.
  See [`testing.md`](testing.md) for layering and where each test kind
  lives.
- **Errors carry context.** Python: raise `DirectiveError` (`src/preserf/errors.py`)
  with file/line where the offending directive was read; never raise a
  bare `ValueError` from the preprocessor. Fortran: validate at API
  boundaries and `error stop` with a clear message — silent failure in
  a long pp_ser-driven run is the worst outcome.
- **Boundary validation only.** Trust internal types. Don't validate
  function arguments that come from your own code three frames up; only
  validate at I/O boundaries (CLI parsing, file reads, Fortran ↔ Python
  wire).
- **No back-compat shims for unreleased code.** Until v1.0 ships, prefer
  changing the code over keeping a shim around.

## Anti-pattern (with the fix)

A real preserf example, from
`src/preserf-fortran/m_preserf.f90` (PR [#16](https://github.com/grAItools/preserf/pull/16)):

> **Don't** cast a Fortran-side `integer(int64)` to `int32` without
> checking the range. NetCDF attributes are `int32`-typed and a silent
> wrap would corrupt the registry without anyone noticing.
>
> **Do** route the cast through the `require_fits_int32` subroutine in
> `src/preserf-fortran/m_preserf.f90`, which `error stop`s with a clear
> message if the value exceeds `huge(0_int32)`. The guard is applied in
> `active_dims_c_order` and `put_halo_attr`, the two places where
> user-supplied dim/halo sizes enter the wire format.

Generalising: **don't trust an implicit conversion at a wire boundary;
do raise a typed error that names the offending field**. The same
pattern applies to Python `int → numpy.int32` casts and to any
`TypeID` round-trip.
