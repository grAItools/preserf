# Code review rules

The canonical project conventions live in `AGENTS.md` at the repository
root. Copilot code review does **not** read `AGENTS.md` — it reads only
the files under `.github/`, from the pull request's base branch, capped at
4,000 characters each — so the review-relevant subset is restated here.
Keep this file under that cap (target ≤ 3,500 chars).

These defaults assume correctness-critical numerical / data / compute code
(scientific computing, HPC, ML). Trim what doesn't apply to your project.

## Always flag

- Floating-point values compared with `==`/`!=` instead of a tolerance,
  and code that ignores `NaN`/`inf` propagation.
- Numerically unstable patterns: catastrophic cancellation, summing values
  of very different magnitude, dividing by a near-zero without a guard.
- Silent precision or dtype changes (float64→float32, integer overflow,
  unintended upcasting/broadcasting in array ops).
- Randomness without a seeded, documented generator where results must be
  reproducible.
- Hot-path scalar loops over arrays where a vectorized/batched op exists,
  and avoidable large-array copies or allocations in inner loops.
- Resource leaks: unfreed GPU memory, leaked file handles, MPI
  communicators or device contexts not released, unbounded memory growth.
- Missing error handling on I/O, network, or subprocess calls.
- New runtime dependencies without a matching ADR under `docs/adr/`.
- Secrets, tokens, or per-developer absolute paths to data/scratch in source.

## Don't comment on

- Formatting or import order — `pixi run fmt` and `pixi run lint`
  own that; defer to them (and to CI, where the project runs it).
- Missing docstrings on private or internal functions.
- Test coverage of trivial getters/setters, or anything under
  `*/generated/` (overwritten by codegen).
- Micro-optimizations with no measured impact — ask for a benchmark first.

## Review style

- One comment per distinct issue; lead with the risk, then the fix.
- Cite evidence as `path/to/file.ext:LINE`.
- When a PR changes architecture or adds an architecture-level feature,
  question the design and propose refactorings where warranted. For a
  localized fix, prefer the smallest change over a refactor.
- If a finding is a question rather than a defect, phrase it as one.

> Path-scoped rules live in `.github/instructions/`. Copilot code review
> uses cached model context, so edits here may not take effect until the
> next push to the PR or a manually re-requested review. Reviews always
> land as `Comment` (never approve / request-changes), so they never
> block a merge by design.
