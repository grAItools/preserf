# Proposal

Issue: #47

## Why

preserf stores every `(savepoint, field)` write as its own dataset,
while Serialbox content-deduplicates identical writes by checksum —
a measured 2.63x ratio on the icon4py `exclaim_ch_r04b09_dsl`
reference run (2077 write references collapse to 789 unique stored
versions). For workloads whose fields are unchanged across
savepoints, preserf stores are substantially larger than the
Serialbox equivalent for the same data.

## What Changes

- Opt-in cross-savepoint content deduplication: identical field
  payloads are stored once and referenced by every savepoint that
  writes them, restoring the Serialbox dedup ratio
- The dedup index lives inside the store (Serialbox keeps its
  external only because its store is flat `.dat`);
  per-savepoint references resolve through it
- An ADR (`dev/adr/0014`) recording the storage-model decision:
  dictionary-encoding versus a content-addressed blob pool

## Out of Scope

- Default-on dedup — existing stores stay byte-identical; dedup is
  opt-in per store
- Wire-format changes for the netcdf4 backend
- Concurrent multi-writer dedup (single writer, matching the
  append-mode baseline)

## Capabilities

### Modified Capabilities

- `storage`: a new cross-savepoint content-deduplication requirement
  pins the opt-in reference-based layout and its round-trip through
  the Python support reader

## Impact

`m_preserf.F90` (write path, dedup index),
`dev/adr/0014`, `dev/references/storage_mapping.md`, native ctest
scenarios, `tests/_support/storage.py` (reader resolves references).
