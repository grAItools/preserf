---
name: code-review
description: |
  Review pull-request changes for preserf against the project's
  review rules. This is correctness-critical numerical / data / compute
  code, so weight numerical stability, reproducibility, performance, and
  resource use alongside the usual error handling, dependency, and secret
  checks. Skips style nits that `pixi run lint` and `pixi run fmt`
  already own. A directory named `code-review` biases Copilot toward using
  this skill during review.
---

# code-review

## When to invoke

- During Copilot code review of a pull request against this repository.
- When asked to review a diff for correctness, security, or maintainability.

## What to check

1. **Numerical correctness** — float equality without a tolerance; ignored
   `NaN`/`inf`; unstable patterns (catastrophic cancellation, near-zero
   division); silent precision/dtype changes; unseeded randomness where
   reproducibility matters.
2. **Performance & resources** — scalar loops where a vectorized/batched op
   exists; avoidable large-array copies; unfreed GPU memory, leaked file
   handles, MPI communicators or device contexts not released.
3. **Correctness** — unhandled errors on I/O, network, or subprocess calls;
   off-by-one and grid/halo boundary conditions; data races in
   threaded/OpenMP/MPI/async code; behaviour changes without a matching test.
4. **Security** — untrusted input or unsafe deserialization
   (`pickle`/`torch.load`/`yaml.load`); committed secrets. See
   [`../../instructions/security.instructions.md`](../../instructions/security.instructions.md).
5. **Maintainability** — functions over ~50 lines or nested beyond 4 levels;
   new runtime dependencies without an ADR under `docs/adr/`.

## What to skip

- Formatting, import order, and lint-enforced style — `pixi run fmt` and
  `pixi run lint` own these.
- Docstrings on private functions; trivial getter/setter coverage.
- Micro-optimizations with no measured impact; anything under `*/generated/`.

## Review style

- One comment per issue; lead with the risk, cite `path/file.ext:LINE`, then
  propose the smallest fix.
- Reviews land as comments, never approvals or blocks — be precise, not noisy.
