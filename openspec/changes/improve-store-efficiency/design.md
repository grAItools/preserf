# Design

## Context

The review verified both gaps by static reading: `ensure_variable`
creates every variable with netCDF-4 defaults and no storage-layout
follow-up anywhere in the tree, and the perturb template deliberately
holds a single scalar random value at a time. Both were flagged with
explicit measurement prerequisites, and the project's own rule
(`dev/conventions.md`) puts correctness and maintainability over unmeasured
optimization — so this change leads with fixtures that measure, then
lands the optimizations behind them.

## Goals / Non-Goals

**Goals:**

- Opt-in chunking/deflate/shuffle for registered fields, default off, so
  existing stores are byte-identical.
- Read-perturb RNG drawn in bounded batches with the same distribution
  and bounds.
- Measured wins: a perf-smoke fixture asserting file size and read
  wall-time before/after, on a representative large field through both
  backends.

**Non-Goals:**

- Default-on compression (byte-format stability preserved until the ADR
  and measurements justify flipping it).
- Wire-format changes, preprocessor/CLI work, and the refactors the
  review explicitly flagged as premature (merging per-line regex scans,
  collapsing the two-pass model, memoizing per-file analysis, replacing
  the linear tracer scan).

## Decisions

- The compression request surface is the Fortran registration API
  (`fs_register_field` and the auto-registration path), not the
  `REGISTER` directive grammar: the preprocessor stays untouched and the
  knobs live where the field metadata is declared.
- The ADR (new `dev/adr/0012`) records the storage-layout decision:
  opt-in, default off, chunk shape derived from the registered dims,
  deflate level from the registration request, reader transparency
  guaranteed by netCDF itself.
- The perturb batching allocates a bounded scratch (on the order of 8192
  elements), one `random_number(chunk)` per chunk, combining elementwise
  within the chunk — peak memory stays O(field + chunk).
- Perf-smoke fixtures come first and stay as regression tests: a
  representative multi-hundred-MB field through both backends asserting
  file size and read wall-time.

## Risks / Trade-offs

- Chunked layout changes partial-read performance characteristics for
  readers; the fixtures measure both file size and read wall-time so the
  trade-off is explicit.
- HDF5 filter availability differs across netcdf-fortran builds; the
  opt-in path degrades to a clear error where the filter stack is
  unavailable rather than silently writing contiguous.
