---
applyTo: "**/*.py"
---

# python review rules

Path-scoped guidance for python sources, applied on top of
the repo-wide rules in `.github/copilot-instructions.md`.

- Flag exported/public functions whose error and edge-case behaviour isn't
  covered by a test.
- Flag data races in threaded / OpenMP / MPI / async code: shared mutable
  state without clear ownership or synchronization.
- Flag broad catch-alls that swallow errors without logging or rethrowing.
- Flag array/buffer indexing that can run out of bounds, and off-by-one in
  loop, grid, or halo boundaries.
- Prefer established numerical libraries over hand-rolled routines; flag
  reinvented BLAS/LAPACK, stdlib reductions, or framework array ops.
- Flag review/release-process prose in comments and docstrings (`Slice X` /
  `Phase N` labels, `v0.x` scope notes, "out of scope for this PR"), stale
  comments, and commented-out code — comments describe the code, not the
  process.

> Tighten this list for preserf: add the review rules that
> `pixi run lint` can't express, and delete anything it already enforces.
