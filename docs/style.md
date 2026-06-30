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

## Comments

Comments and docstrings describe the **code**, not the **process** that
produced it. A comment earns its place only when it adds something the code
cannot say for itself.

- **Explain _why_, not _what_.** The code already says what it does. A good
  comment captures what a reader can't recover from the code: an invariant, a
  non-obvious constraint, the spec/ADR that motivates the shape. Don't narrate
  the next line (`# increment i`).
- **Keep them true.** A wrong comment is worse than none — it actively
  misleads. When you change behaviour, update or delete the adjacent comment in
  the same change. Tests are the spec; comments get no such safety net, so
  accuracy is on you.
- **No review- or release-process prose.** `out of scope for this PR`,
  `v0.1 covers…`, or internal `Slice X / Phase N` slice labels describe how the
  work was cut up for review. That process moves on and the comment goes stale
  at once. Scope, rationale, and future work belong in the PR description, an
  issue, an ADR, or the spec — _referenced_ from the code, not inlined. This is
  enforced: `pixi run verify` fails on such phrasing
  (`tests/unit_tests/test_comment_hygiene.py`), on commented-out code (ruff
  `ERA`), and on stray `TODO`/`FIXME` (ruff `FIX`) — file an issue instead.
- **State a rationale once.** Don't copy an explanatory block to every call
  site; duplicated prose drifts out of sync. Put it at the definition (or an
  ADR) and reference it.

Worked example — a real `src/preserf/fortran/utils_preserf.f90` comment:

> **Don't** frame a limitation as review scope:
> `… and 'a' mode is out of scope for the minimal v0.1 helper.`
> "v0.1" and "minimal helper" name a milestone that will move; a year on, the
> reader can't tell whether it still holds.
>
> **Do** state the limitation as a fact about the code, keeping the real
> reason: append-mode index resumption _is not implemented_ because it would
> require `nf90_inq_grps` with a pre-sized output array, so the resolver starts
> the savepoint index at 0. The behaviour is described; no PR is named. If
> there's tracked future work, link the issue.

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
`src/preserf/fortran/m_preserf.F90` (PR [#16](https://github.com/grAItools/preserf/pull/16)):

> **Don't** cast a Fortran-side `integer(int64)` to `int32` without
> checking the range. NetCDF attributes are `int32`-typed and a silent
> wrap would corrupt the registry without anyone noticing.
>
> **Do** route the cast through the `require_fits_int32` subroutine in
> `src/preserf/fortran/m_preserf.F90`, which `error stop`s with a clear
> message if the value exceeds `huge(0_int32)`. The guard is applied in
> `active_dims_c_order` and `put_halo_attr`, the two places where
> user-supplied dim/halo sizes enter the wire format.

Generalising: **don't trust an implicit conversion at a wire boundary;
do raise a typed error that names the offending field**. The same
pattern applies to Python `int → numpy.int32` casts and to any
`TypeID` round-trip.
