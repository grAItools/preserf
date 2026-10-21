# Design

## Context

The CLI already guarantees directive errors as one-line diagnostics with a
non-zero exit; the gaps are in the collection and destination layers, where
`OSError` from `rglob` walking is uncaught, and the stdout path has no
single-source contract. The suffix filter (`_is_fortran`) exists and is
applied during recursion only, so explicit arguments bypass it. The review
verified each path by reading and by tracing the mutual-exclusion checks.

## Goals / Non-Goals

**Goals:**

- Every user-reachable failure is a one-line `preserf:` diagnostic with
  exit 1 — no raw tracebacks from collection.
- The stdout contract is explicit: either exactly one input, or a refusal.
- Explicit arguments get the same suffix sanity check as recursive walks.

**Non-Goals:**

- Changing `--output-dir` semantics, the preprocessor engine, or the
  recursive mirroring rules.
- Performance work beyond hoisting the repeated root `is_dir` stat.

## Decisions

- Broaden the collection handler to `except (ValueError, OSError)` and
  route both through the existing `_fail` one-liner.
- Multi-source runs without `-o`/`-d` fail fast with a usage error; silent
  concatenation is retired as a documented behavior rather than kept.
- Non-Fortran explicit arguments warn (stderr) rather than error, since
  include-file conventions and typos both exist in the wild and warning
  preserves the passthrough escape hatch.
- `--version` joins the path callbacks on bare `print` for clean
  command substitution; the dead `if wrote and destination is not None`
  condition is collapsed.

## Risks / Trade-offs

- Rejecting multi-source stdout runs could break a script that relied on
  silent concatenation; the previous output was arguably corrupt
  (duplicated headers), so the break is intentional and CHANGELOG-noted.
- The warning for non-Fortran arguments may be noisy for deliberate
  passthrough; acceptable, and suppressible by renaming the argument.
