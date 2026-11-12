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

- Opt-in chunking/deflate for registered fields, default off, so
  existing stores are byte-identical.
- Read-perturb RNG drawn in bounded batches with the same distribution
  and bounds.
- Measured wins: a perf-smoke fixture asserting file size and read
  wall-time before/after, on a representative large field through both
  backends for the default-off baseline; the compressed "after"
  measurement is netcdf4-only until the nczarr codec follow-up (#111)
  lands, since the NCZarr combination is rejected at initialization.

**Non-Goals:**

- Default-on compression (byte-format stability preserved until the ADR
  and measurements justify flipping it).
- Wire-format changes, preprocessor/CLI work, and the refactors the
  review explicitly flagged as premature (merging per-line regex scans,
  collapsing the two-pass model, memoizing per-file analysis, replacing
  the linear tracer scan).

## Decisions

- The compression request surface is a store-wide default at
  `ppser_initialize` (a `compression=` keyword, mirroring `backend=`)
  plus a `PRESERF_COMPRESSION` env var — the surface PR #53 implements
  and that the issue body and the nczarr-compression-codec change
  assume. The storage reference §9 deferred naming (proposing
  `!$SER OPTION` keys), which this decision now supplies. A per-field
  override through the Fortran registration API (`fs_register_field`)
  is an explicit follow-up: the auto-registration path carries no
  caller-supplied metadata today and `!$SER REGISTER` rejects
  key=value pairs, so that surface is not implementable without
  preprocessor work.
- The ADR (new `dev/adr/0013`) records the storage-layout decision:
  the store-wide request surface at `ppser_initialize` plus the env
  var, the per-field override deferred, bounded chunk shapes derived
  from the registered dims, tracer data following the global knob,
  and the NCZarr combination rejected until the codec follow-up.
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
