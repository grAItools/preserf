# Conventions

## Tooling

`preserf` mixes Python and Fortran; both are auto-formatted and statically
checked. Configuration lives next to the code, not here — this file
documents intent.

- **Python:** `ruff` (lint + format, config in `pyproject.toml`),
  `mypy` strict mode targeting Python 3.12 (`pyproject.toml` `[tool.mypy]`).
- **Fortran:** `fprettify` for formatting (no separate linter; gfortran
  `-std=f2008` enforces standards conformance at build time).
- **Markdown, JSON, TOML:** `dprint` (config in `dprint.json`).

No harness auto-format hooks are configured. Run `pixi run fmt` after
editing (or the file-scoped `pixi run fmt-py-src` / `pixi run fmt-f-src`),
and treat `pixi run verify` (fmt-check + lint + typecheck + test) as the
pre-done gate — CI is the only hard enforcement of it.

## Code conventions

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

## Issue triage and change lifecycle

GitHub issues are the entry point for user-reported bugs and feature
requests; they describe problems. Solution sketches are welcome
input, but the change spec owns the design. The lifecycle is:

1. **New** — an issue is filed via the bug/feature templates
   (`.github/ISSUE_TEMPLATE/`).
2. **Accepted** — a human developer reviews it and marks it valid
   (`triage/accepted`). Agents may summarize or draft, but only a human
   accepts (`triage/declined` otherwise).
3. **Linked** — the accepted issue is dealt with by drafting an OpenSpec
   change (`openspec/changes/<change>/`) whose proposal references the
   issue (`Issue: #N`); the change name is posted as a comment on the
   issue so the link is bidirectional.
4. **Closed** — when the change is implemented and merged, the PR carries
   `Closes #N` so GitHub closes the issue automatically at merge.

Accepted issues blocked on an external enabler carry `blocked/deferred`
and stay open, with the blocker documented in the linked proposal.
Spec-first work (not originating from a user issue) skips the acceptance
gate but still runs the same propose → apply → archive loop. The
decision is recorded in
[ADR 0012](adr/0012-issue-driven-change-lifecycle.md).

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

## Changelog

When the project keeps a `CHANGELOG.md`, follow
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[SemVer](https://semver.org/spec/v2.0.0.html):

- Log every user-facing change under `## [Unreleased]`, in the right group
  (`Added` / `Changed` / `Fixed` / `Removed` / `Deprecated` / `Security`).
- Write **one concise bullet** per change, and **lead with the file, command,
  or behaviour** that changed — not the motivation.
- Mark breaking changes (`### Removed (breaking)`, or a `!` per the commit
  convention) and add an `### Upgrade notes` block when an upgrade needs manual
  action.
- Link the ADR when the change has one (see [`dev/adr/`](adr/)).
- On release, rename `[Unreleased]` to the version + date and add the compare
  link.

> **Don't** bury the change under a paragraph of rationale.
> **Do** lead with it: "`find` dropped from the allow-list (its `-delete` form
> bypassed the deny-list)." — the change first, the why in a clause.

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
