# Slice G plan: Append mode

## Phase 1 — Savepoint group resumption

**Scope.** On `ppser_initialize(..., mode='a')`, open the existing
file and resume the savepoint group index so subsequent
`fs_create_savepoint` calls start at the right `sp_NNNNNN`.

**Steps.**

1. Replace the current outright-reject branch in
   `preserf_open_serializer` (or `ppser_initialize`) with an open
   path that uses `nf90_open` + write mode flags.
2. Use `nf90_inq_grps` to enumerate the existing `/savepoints/sp_*`
   groups and set `next_sp_index` to the next free index.
3. Confirm `fs_create_savepoint` picks up the resumed counter
   correctly (it should already; this is a smoke check).

**Tests.**

- Native scenario: write a store with 3 savepoints, close, re-open
  in append mode, write a 4th savepoint, close, re-open in read
  mode, assert all 4 savepoints exist in order.

**Exit criteria.** Append + read-back round-trip passes; existing
write-only and read-only tests still pass.

## Phase 2 — Housekeeping sanity check

**Scope.** Reject append against a store whose `_preserf_*`
housekeeping attributes disagree with what the new run would write.

**Steps.**

1. Read the existing `_preserf_*` root attributes (per
   `docs/references/storage_mapping.md` §1).
2. Compare against what the current `ppser_initialize` arguments
   would produce (schema version, type-id encoding,
   `_preserf_singlefile` / `_preserf_archive` / `_preserf_unique_id`
   from Slice D Phase 3 if those have landed).
3. Mismatch → `error stop` with a clear message naming the
   offending attribute. Don't silently fork the store.

**Tests.**

- Native negative scenario: create a store, manually mutate one
  `_preserf_*` attribute, attempt append, assert the abort message.

**Exit criteria.** Append refuses to corrupt mismatched stores.
