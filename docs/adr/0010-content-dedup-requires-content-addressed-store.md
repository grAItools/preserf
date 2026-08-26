# 10. Content deduplication across savepoints requires a content-addressed store (deferred)

## Status

Proposed

## Context

[Issue #47](https://github.com/grAItools/preserf/issues/47) reports that
preserf stores **every `(savepoint, field)` write as its own variable** (one
netCDF variable per field inside each savepoint group, per
`storage_mapping.md` §6), whereas Serialbox
content-**deduplicates** identical writes by checksum: a field whose
value is unchanged across savepoints is stored once and later savepoints
reference the existing copy. The result is that a preserf store is
substantially larger than the Serialbox equivalent for the same data.

### Evidence (from the issue, Serialbox's own metadata)

icon4py reference data for `exclaim_ch_r04b09_dsl`, single rank
(`mpitask1_…_v04`), analysed from `ArchiveMetaData` + the savepoint table:

- 96 savepoints, **2077 `(savepoint, field)` write references**;
- collapse to **789 unique stored versions** (checksum-based; 0 duplicate
  checksums in `fields_table`);
- → **2.63×, i.e. 62% of writes are deduplicated**.

On disk: Serialbox = **11 GB**, preserf (same experiment, all 2077 writes,
uncompressed) = **31.7 GB**. The ~2.9× gap is essentially this dedup plus
NetCDF4/HDF5 per-object overhead.

### This interacts with a decision of record

preserf's storage model is fixed by ADR
[0002](0002-storage-model-mapping.md): a **group-per-savepoint** layout in
which each savepoint subgroup holds one variable per field written at that
savepoint, self-describing and openable by xarray / zarr-python with no
preserf-specific tooling. ADR 0002 also records, as an explicit consequence,
that _"Serialbox's per-field offset table and checksum machinery is not
reproduced — integrity is delegated to the underlying format."_ Content-dedup
runs directly against both of those properties, so it is not a localized change
— it is a storage-model decision, which is why the issue is flagged for an ADR
rather than a quick fix.

### Why there is no transparent dedup to lean on

Neither target format offers content-addressed storage for free:

- **NetCDF data model** — no dedup; two identical variables always use
  separate storage.
- **HDF5 hard links** _would_ give true in-file dedup (one refcounted dataset
  reachable from many group paths), but **netcdf-c does not expose HDF5 link
  creation**, and raw-HDF5 link surgery on a netcdf-managed file is
  unsupported and fragile. This route is closed through the `nf90_*` API that
  ADR 0002 commits preserf to.
- **NCZarr** — no native chunk dedup either.

So achieving dedup means either a **schema change** (a content-addressed store
built out of ordinary datasets plus a reference index) or delegating to a
**filesystem** that dedups blocks. Both have real costs, enumerated below.

## Decision

**Defer the implementation. Do not change the storage schema in this change.**
This ADR records the analysis, the options and their tradeoffs, and a
recommended path, so the eventual implementer starts from an established
decision rather than re-deriving it. Three considerations drive the deferral:

1. **The issue itself asks for a decision, not a code drop.** A
   content-addressed store is a forwards-incompatible change to the layout ADR
   0002 established; shipping it unmeasured would be premature.

2. **Compression is the cheaper, orthogonal size lever and is not even
   landed yet.** Opt-in field-write compression is in flight but unmerged
   ([PR #53](https://github.com/grAItools/preserf/pull/53) for #46), and its
   NCZarr extension is itself blocked (issue
   [#111](https://github.com/grAItools/preserf/issues/111), deferral proposed
   in [PR #124](https://github.com/grAItools/preserf/pull/124)).
   Compression and dedup are additive — a byte-identical duplicate is _not_
   collapsed by a compressor, each copy is still stored and compressed — so
   dedup's structural cost should be weighed against the **residual** size gap
   _after_ compression is available and measured, not against the uncompressed
   31.7 GB baseline. Sequencing compression first is the correct order.

3. **Dedup forfeits properties ADR 0002 chose deliberately.** A shared/pooled
   store is no longer self-describing per savepoint, and the current read path
   (positional `sp_NNNNNN` resolution, `storage_mapping.md` §5) would need a
   reference-resolution layer. That is worth doing only once the size win is
   shown to justify the reader complexity.

### Options considered (for the eventual implementation)

Let `H(field_bytes)` be a content hash computed at write time. In every option
the dedup happens by writing the _bytes once_ and recording a _reference_
everywhere the same bytes recur. The index that maps `H → stored location` can
live **inside** the file (preserf is not constrained to Serialbox's external
index, which exists only because Serialbox's archive is a flat directory of
`.dat` files).

**Collision safety is mandatory, not optional.** These are correctness-critical
serialization payloads, so silent aliasing of two _distinct_ field values must
be impossible. The implementation MUST guarantee this by **both** of:

1. Using a **collision-resistant** digest — SHA-256 or BLAKE3 — for `H`. A fast
   non-cryptographic hash (xxHash, CityHash, etc.) MAY be used only as a cheap
   first-level bucket key, never as the sole identity of a payload.
2. On any hash match, performing a **full byte-for-byte comparison** of the
   candidate payload against the stored blob before treating them as identical.
   The bytes are collapsed only when the compare confirms equality; a hash
   match with a byte mismatch stores a new blob (a normal hash-table collision,
   not data loss). This makes correctness independent of the digest's collision
   probability — the hash is an index, the byte-compare is the arbiter.

The byte-compare is cheap relative to the write it avoids (only the colliding
candidate is compared, and only on a hash hit), and it removes any possibility
of a duplicate reference aliasing different data.

- **Option A — in-file blob pool + reference index (recommended).** One (or a
  few, keyed by dtype/rank) growable dataset per store acts as a blob pool;
  each unique field payload is appended once and identified by an
  `(offset, length)` (or a pool-local record id). A per-savepoint reference —
  an attribute or a tiny index variable in the `sp_NNNNNN` group — points at
  the pool record instead of holding a data variable. A single in-file
  `H → record` index deduplicates on write. Favoured because it amortizes HDF5
  per-object overhead across many payloads (the issue explicitly warns to
  "favour a pool over many tiny datasets"), and because the index is
  self-contained. Cost: the savepoint group is no longer a plain collection of
  named field variables, so readers must resolve references; xarray/zarr won't
  "just open" it without a shim.

- **Option B — dataset-per-content-hash.** Store each unique payload as its own
  dataset named by its hash (e.g. `/_blobs/<hash>`), and reference it from each
  savepoint. Conceptually simplest and each blob stays an ordinary,
  individually-openable dataset, but it multiplies HDF5/NCZarr per-object
  overhead across up to 789 (in the example) tiny objects and scales poorly as
  unique-version counts grow — the overhead this whole effort is trying to
  reduce. Rejected as the primary route for that reason; may be acceptable for
  NCZarr where objects are directory entries rather than HDF5 datasets.

- **Option C — filesystem-level reflink dedup.** Keep the schema exactly as-is
  and rely on block-level dedup from the storage system (XFS/btrfs reflinks,
  ZFS dedup). Zero format change and zero reader complexity, but it is
  **outside the format**: storage-system-dependent, invisible to a consumer
  copying the store onto a non-dedup filesystem, and offers no guarantee. A
  reasonable _operational stopgap_ to document, not a portable solution.

### Recommendation

When the effort is picked up — **after** compression lands and the residual gap
is measured — implement **Option A** as an **opt-in** mode gated by a new
`ppser_initialize` keyword, with a **`_preserf_schema_version` bump** and the
non-dedup group-per-savepoint layout remaining the default. This preserves
"opens in xarray/zarr with no preserf tooling" for the common case, confines
reader complexity to stores that opted in, and reintroduces a write-time
content hash **only** on that path (ADR 0002 dropped Serialbox's checksum
machinery; dedup necessarily brings a hashing step back for the dedup mode).
Document Option C as an operational note for users on dedup-capable
filesystems in the meantime.

## Consequences

- **No behaviour or schema change ships from this ADR.** It is documentation
  only; the verification gate stays green and no runtime dependency is added.
- The analysis, option tradeoffs, and the "compression first, then measure
  residual, then Option A opt-in" sequencing are recorded, so the eventual
  implementer does not re-derive them.
- The tension with ADR 0002 is made explicit: dedup is an **opt-in alternate
  mode** with its own schema version, not a change to the default
  self-describing layout — keeping existing readers working by default.
- A concrete forward path is captured: an in-file blob pool + `(offset,len)`
  reference index + in-file `H → record` map, plus a read-path
  reference-resolution layer over the positional `sp_NNNNNN` scheme
  (`storage_mapping.md` §5).
- `storage_mapping.md` §9 now cross-references this ADR next to the existing
  chunking/compression deferred question.

Revisit when: opt-in compression (PR #53 / #46) has merged and the residual
size gap on a representative dump has been measured, or if a downstream ICON
evaluation makes the store-size gap a hard blocker before then.
