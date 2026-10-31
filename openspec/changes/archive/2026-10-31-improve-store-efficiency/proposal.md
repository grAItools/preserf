# Proposal

Issue: #46

## Why

Two storage-efficiency gaps cap the runtime for large-field workloads.
Store variables are created with netCDF-4 defaults — contiguous,
uncompressed HDF5 datasets — so compression is impossible and file size
scales with raw field bytes (`m_preserf.F90:3582-3597`, `ensure_variable`;
no chunking, deflate, or shuffle call exists in the tree). And
read-perturb draws `random_number` one element at a time — the only
element-wise library-call loop on a hot path
(`preserf_apply_perturb.inc:29-66`) — a 10-100x constant-factor gap
versus one bulk draw.

## What Changes

- Opt-in `nf90_def_var_chunking` and `nf90_def_var_deflate(level)`, requested through a store-wide `compression=` keyword on `ppser_initialize` (mirroring `backend=`) plus a `PRESERF_COMPRESSION` env var, threaded to `ensure_variable`, default off; a per-field override through `fs_register_field` is an explicit follow-up
- Batched read-perturb RNG with a bounded chunk scratch (one `random_number(chunk)` per chunk)
- Perf-smoke fixtures measuring file size and read wall-time for both; an ADR (`dev/adr/0013-opt-in-store-compression.md`) recording the storage-layout decision

## Out of Scope

- Default-on compression (byte-format stability preserved) and wire-format changes
- The per-field registration-API override (an explicit follow-up; see the design for why the registration-API surface is not implementable today)

## Capabilities

### Modified Capabilities

- `storage`: new variable storage layout requirements pin opt-in chunking and compression with default-off behavior; the perturbed-reads requirement gains a batched-drawing scenario

## Impact

`m_preserf.F90`, `preserf_apply_perturb.inc`, native ctest scenarios, `dev/adr/` (new record), CHANGELOG.
