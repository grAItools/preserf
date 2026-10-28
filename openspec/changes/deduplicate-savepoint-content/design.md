# Design

## Deliberation absorbed from the superseded ADR drafts

PRs #50 and #54 deliberated this decision without a resolution
vehicle, and #144 deferred it pending a content-addressed store.
Their reasoning, consolidated:

- There is no transparent content deduplication in the NetCDF4 or
  NCZarr data models: two identical variables always use separate
  storage.
- HDF5 hard links would give true in-file dedup (one refcounted
  dataset, many group paths), but netcdf-c does not expose them,
  and raw-HDF5 link surgery on a netcdf-managed file is
  unsupported and fragile.
- A **dictionary-encoding** layer (the #54 line): one dataset per
  unique field payload; savepoint variables reference dictionary
  entries. Transparent to a reader that resolves a single
  indirection; keeps per-field datasets (self-describing savepoint
  groups survive).
- A **content-addressed blob pool** (the framing #144 defers
  against): one growable dataset plus an `(offset, len)` index,
  with per-savepoint references into the pool. Cheaper per object
  than many tiny datasets, but loses self-describing savepoint
  groups and moves reader complexity up a notch.

## Chosen direction

**Dictionary encoding**, for three reasons:

1. **Reader complexity is bounded**: one indirection (savepoint
   variable → dictionary entry) instead of a pool-plus-offset
   arithmetic; the Python support reader resolves it with a single
   lookup per field.
2. **Self-describing layout survives**: each dictionary entry is a
   normal, named dataset; a reader that ignores the dedup
   reference still sees a coherent store, which keeps the
   wire-compat test suite honest.
3. **It composes with append mode**: the dictionary grows by
   unique payload; the savepoint-group index resumption that
   append mode already requires (scanning `/savepoints/sp_NNNNNN`)
   extends naturally to reference the dictionary.

The pool remains the fallback if dictionary metadata overhead
measures poorly for very large numbers of unique payloads; that
trade-off is recorded in the ADR rather than decided here.

## Interaction with sibling work

- Compression (the `improve-store-efficiency` change) is
  orthogonal and composes: a dictionary entry is itself a store
  variable, so chunking/deflate apply to it like any other.
- Append mode (`add-append-mode`) shares the savepoint-group
  scanning this design extends; the dictionary reference is
  written by the same path that writes the savepoint variable
  today.
