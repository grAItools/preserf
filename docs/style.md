# Style guide

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
or `pixi run fmt-f-src` on every Write/Edit of a `.py` / `.f90` file as
a best-effort auto-format — it swallows errors with `|| true` so that a
missing pixi or a transient task failure doesn't block the agent's
edit loop. The hard gate is the Stop hook, which runs `pixi run verify`
(fmt-check + lint + typecheck + test) and exits non-zero on drift —
that's what blocks "done" until the tree is clean.

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

## Commit messages

This project uses **[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)**.

Format: `<type>(<scope>): <description>` — the `(scope)` segment
(parentheses included) is optional, so a commit without one is just
`<type>: <description>`. Description in imperative mood, no trailing
period, first line ≤72 chars.

Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`,
`build`, `ci`, `perf`, `style`, `revert`. Mark breaking changes with `!`
after the type/scope (e.g. `feat(api)!: drop v1 endpoints`) or a
`BREAKING CHANGE:` footer.

Examples:

```
feat(serializer): add Zarr backend for !$SER directives
fix: guard int32 cast of dim sizes in m_preserf
chore!: drop Python 3.11 support
docs(adr): record Serialbox→NetCDF4/Zarr storage mapping
```

PRs are **squash-merged**, so only the squash commit lands in history.
Put the Conventional Commits header in the **PR title**; individual
branch commits during work can be freeform working notes.

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
