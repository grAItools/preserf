# Slice G: Append mode

## Problem

`ppser_initialize(..., mode='a')` is currently rejected outright, not
half-implemented. pp_ser-generated source that opens a store in
append mode fails at initialisation.

## Goal

`ppser_initialize(..., mode='a')` opens an existing preserf store and
appends new savepoints + field writes without forking the store or
clobbering existing data.

## Non-goals

- Read-perturb, type-coverage, tracers, backend selector — covered
  by Slices A-2, B, C, E.
- Concurrent multi-writer append. Append assumes a single writer at
  a time (the Serialbox baseline).

## Status

**Deferred past v1.0.** The v1.0 DoD in
[`specs/README.md`](../README.md#v10--definition-of-done) explicitly
defers Slice G — pp_ser-generated source rarely uses `'a'`, and the
`'w'` + `'r'` modes cover the typical run/replay loop. This spec
exists so the work is captured while context is fresh; it can be
picked up post-v1.0 (likely v1.1) if demand emerges.

## Success criteria

- `ppser_initialize(..., mode='a')` opens an existing store, resumes
  the savepoint group index via `nf90_inq_grps`, and prepares the
  serializer state to append starting at the next `sp_NNNNNN`.
- The `_preserf_*` housekeeping attributes documented in
  `storage_mapping.md` §1 are sanity-checked on open: if they
  disagree with what the new run would write, the open aborts with
  a clear error rather than silently forking the store.
- A native scenario writes a store, closes it, re-opens in append
  mode, writes additional savepoints, closes, and reads back —
  asserting both original and appended savepoints are present and
  correctly ordered.
