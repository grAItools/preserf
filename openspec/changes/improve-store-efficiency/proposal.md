# Proposal

## Why

Two storage-efficiency gaps cap the runtime for large-field workloads.
Store variables are created with netCDF-4 defaults — contiguous,
uncompressed HDF5 datasets — so compression is impossible and file size
scales with raw field bytes (`m_preserf.F90:3296-3311`, `ensure_variable`;
no chunking, deflate, or shuffle call exists in the tree). And
read-perturb draws `random_number` one element at a time — the only
element-wise library-call loop on a hot path
(`preserf_apply_perturb.inc:29-66`) — a 10-100x constant-factor gap
versus one bulk draw.

## What Changes

- Opt-in `nf90_def_var_chunking`, `nf90_def_var_deflate(level)`, and shuffle, requested through the Fortran registration API (`fs_register_field` and the auto-registration path) and threaded to `ensure_variable`, default off
- Batched read-perturb RNG with a bounded chunk scratch (one `random_number(chunk)` per chunk)
- Perf-smoke fixtures measuring file size and read wall-time for both; an ADR recording the storage-layout decision

## Out of Scope

- Default-on compression (byte-format stability preserved) and wire-format changes
- The REGISTER directive grammar (the request surface is the Fortran registration API)

## Capabilities

### Modified Capabilities

- `storage`: a new variable storage layout requirement pins opt-in chunking and compression with default-off behavior; the perturbed-reads requirement gains a batched-drawing scenario

## Impact

`m_preserf.F90`, `preserf_apply_perturb.inc`, native ctest scenarios, `dev/adr/` (new record), CHANGELOG.
