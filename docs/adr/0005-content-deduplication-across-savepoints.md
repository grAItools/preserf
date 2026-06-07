# 5. Content deduplication of identical field writes across savepoints

## Status

Proposed

## Context

preserf stores **every `(savepoint, field)` write as its own netCDF
variable** under `/savepoints/sp_NNNNNN/<fieldname>` (ADR
[0002](0002-storage-model-mapping.md); `docs/references/storage_mapping.md`
§6). A field whose value is unchanged across many savepoints is therefore
stored once per savepoint. Serialbox, by contrast, content-**deduplicates**:
it checksums each write and, when the checksum already exists, records a
_reference_ to the stored copy instead of writing the bytes again.

The size impact is large and measured, not hypothetical. For the icon4py
reference dataset `exclaim_ch_r04b09_dsl`, single rank
(`mpitask1_…_v04`), analysed from Serialbox's own `ArchiveMetaData` plus the
savepoint table (reported in issue #47):

- 96 savepoints, **2077 `(savepoint, field)` write references**,
- collapsing to **789 unique stored versions** (checksum-based; 0 duplicate
  checksums in `fields_table`),
- i.e. **2.63×** — about 62% of writes are redundant copies.

On disk for that experiment: Serialbox **11 GB** vs preserf **31.7 GB**
(all 2077 writes, uncompressed). The ~2.9× gap is essentially this
deduplication plus NetCDF4/HDF5 per-object overhead. This is the headline
blocker for evaluating preserf as a Serialbox2 replacement in ICON, where
the reference data is regenerated and stored repeatedly.

Deduplication is **not transparently available** in either target format,
which is why this is an architecture decision rather than a localized change:

- **NetCDF4 data model:** no content dedup. Two identical variables always
  occupy separate storage; there is no "store-once, reference-many" concept
  in the netCDF object model.
- **HDF5 hard links** _would_ give true in-file dedup — one refcounted
  dataset reachable from many group paths. But **netcdf-c does not expose
  HDF5 link creation**, and performing raw-HDF5 link surgery on a file that
  netcdf-c manages is unsupported and fragile (it can desynchronise
  netcdf-c's internal model of the file). So the one mechanism that would be
  "free" is not reachable through the API preserf commits to (`nf90_*`
  only, ADR 0002).
- **NCZarr** has no native chunk deduplication either. Identical chunks are
  written to distinct keys in the store.

This interacts with two other concerns:

- **Self-describing savepoint groups.** ADR 0002's central property is that
  a savepoint group _is_ the data: `xr.open_datatree` / `zarr.open_group`
  reads a store with no preserf-specific tooling
  (`storage_mapping.md` §2, ADR 0002 Consequences). Any deduplication that
  replaces a savepoint's data variable with a _reference_ to bytes stored
  elsewhere breaks that property: a naive reader sees a reference, not the
  field. Whatever is decided must state explicitly what a naive reader sees.
- **Chunking and compression** are themselves currently
  implementation-defined and deferred to a follow-up ADR
  (`storage_mapping.md` §6, §9; sibling issue #46). Compression is the
  orthogonal, lower-effort size lever; deduplication is the structural one.
  A dedup scheme that addresses content at the _chunk_ level (rather than the
  whole-variable level) interacts directly with the chunk shape that #46
  will fix, so the two decisions are coupled and should be sequenced
  deliberately.

The Serialbox numbers establish that deduplication is the single largest
size lever, and the format constraints establish that capturing it requires
a schema-level decision. This ADR frames that decision and recommends a
direction; it does **not** implement a content-addressed store.

### Data-model constraints (summary)

| Constraint                                    | Consequence for dedup                                       |
| --------------------------------------------- | ----------------------------------------------------------- |
| netCDF model has no store-once/reference-many | Dedup must be encoded _on top of_ the model, in schema      |
| HDF5 hard links not exposed by netcdf-c       | The "free" in-file dedup mechanism is unreachable           |
| Raw-HDF5 surgery on a netcdf file is fragile  | Reaching links anyway risks corrupting the store            |
| NCZarr has no native chunk dedup              | Same schema burden as NetCDF4; no format shortcut           |
| Self-describing savepoint groups (ADR 0002)   | References break naive reads unless carefully designed      |
| Per-object HDF5 overhead is non-trivial       | Favour few large objects (a pool) over many tiny ones       |
| `_preserf_schema_version` is currently `1`    | Any non-additive change must bump it (storage_mapping §3.1) |

## Decision

### Options considered

**Option A — In-file content-addressed blob pool + per-savepoint
references.** Add a reserved top-level group (e.g. `/_blobs`) holding a
small number of growable datasets plus an index, and a content hash →
`(blob, offset, length)` map kept **inside** the file. Each savepoint field
"write" that matches an existing checksum stores a _reference_ (the content
hash, or a `(blob, offset, length)` tuple) as a reserved attribute on a
placeholder variable instead of the data. New content is appended to the
pool.

- _Pros:_ captures the full 2.63× (whole-variable dedup, possibly chunk-level
  later); the dedup index lives **inside** the file, so the store stays a
  single self-contained artifact (Serialbox keeps its index external only
  because its archive is flat `.dat`); a pool avoids HDF5 per-object overhead
  by using few large datasets.
- _Cons:_ the largest reader-complexity cost — a reader must resolve
  references through the pool, so `xr.open_datatree` no longer yields field
  data directly; this **breaks the self-describing savepoint-group property**
  that is ADR 0002's core value, unless preserf ships (and downstream tools
  adopt) a resolving reader. It is a non-additive schema change
  (`_preserf_schema_version` bump). Interacts with chunking/compression
  (#46): a pool wants its own chunk shape and filter pipeline.

**Option B — Dataset-per-content-hash (HDF5 object per unique version).**
Store each unique field version once as a dataset named by its content hash
(e.g. `/_content/<hash>`), and have each savepoint field reference the hash.

- _Pros:_ conceptually simple addressing; each unique version is still an
  ordinary, independently-readable variable.
- _Cons:_ 789 unique versions in the sample experiment means up to 789
  extra HDF5 objects, each with per-object overhead — exactly the overhead
  the issue flags. At larger scale this overhead grows with the _number of
  unique versions_ and can erode the dedup win. Same reader-resolution and
  self-describing-loss costs as Option A, with worse object-count scaling.

**Option C — Rely on filesystem-level deduplication (reflinks / ZFS).**
Leave the schema unchanged and lean on XFS/btrfs reflinks or ZFS block-level
dedup to coalesce identical bytes underneath preserf.

- _Pros:_ zero schema change, zero reader complexity, the store stays fully
  self-describing.
- _Cons:_ **storage-system-dependent and outside the format** — it does not
  help on ext4, network filesystems, object stores, or when the store is
  copied/`tar`red/transferred (the canonical use of reference data). It also
  depends on byte-identical alignment, which HDF5 per-object layout and
  chunking can defeat. Cannot be relied on for portable reference data.

**Option D — Do nothing (status quo); lean on compression instead.** Accept
the current per-write storage and address size via compression (#46) only.

- _Pros:_ no new complexity; preserves ADR 0002 exactly; compression is a
  smaller, orthogonal change that helps every store.
- _Cons:_ compression does **not** recover cross-savepoint redundancy — it
  re-compresses each identical copy independently, so the structural 2.63×
  remains. Leaves the headline ICON size gap largely open.

### Recommendation

**Adopt Option A (in-file content-addressed blob pool + per-savepoint
references) as the target direction, but do not implement it yet.** It is
the only option that (1) captures the full structural redundancy, (2) keeps
the store a single self-contained file, and (3) controls HDF5 per-object
overhead via a pool. Option B is dominated by A on object-count scaling;
Option C is unusable for portable reference data; Option D leaves the
headline gap open.

Adoption is **gated** on three things being settled first, because Option A
is the most invasive change preserf can make to its read contract:

1. **Sequencing after #46 (chunking/compression).** Compression is the
   cheap, orthogonal, fully-self-describing lever and should land first; it
   also fixes the chunk shape that a future _chunk-level_ dedup would key on.
   Pursue compression (#46) before building the blob pool.
2. **A resolving reference reader is part of the deliverable, not a
   follow-up.** Because Option A breaks naive self-describing reads, the
   implementing slice MUST ship a preserf reader (and document the on-disk
   reference encoding) so the store remains usable. The schema should keep
   the _placeholder_ variable carrying enough metadata (`type_id`, `dims`,
   shape) that a naive reader can still enumerate _what_ exists at each
   savepoint even if it cannot resolve the _bytes_.
3. **A schema-version bump.** Deduplication via references is **not** an
   additive change — it changes what a savepoint variable means. It MUST
   bump `_preserf_schema_version` (currently `1`,
   `storage_mapping.md` §3.1) and reuse the reserved `_preserf_*` /
   `_blobs` namespaces so pre-bump readers fail loudly rather than silently
   returning reference handles as data.

Until those gates are met, the **interim** posture is Option D + compression
(#46): the status quo schema plus compression, which is self-describing and
recovers some (not the structural) size. This ADR records the decision to
_pursue_ Option A and the constraints any implementation must satisfy; the
concrete on-disk encoding (blob-pool layout, hash algorithm, reference
attribute schema, chunk-level vs whole-variable granularity) is left to a
follow-up spec + ADR that supersedes the relevant parts of this one once the
gates are cleared.

## Consequences

- **Direction is recorded; code is not committed.** Implementers have a
  ratified target (Option A) and an explicit gate list, so the eventual
  implementation PR is a realisation of an agreed design rather than a venue
  to relitigate the storage model.
- **Self-describing reads are explicitly at stake.** Option A trades ADR
  0002's "the savepoint group _is_ the data" property for size. The gate
  list keeps that trade honest: a resolving reader ships with the schema,
  and placeholder variables keep savepoint _enumeration_ working for naive
  tools even when _byte resolution_ requires preserf.
- **Coupled to #46.** Compression (#46) is sequenced first as the cheap,
  orthogonal lever and as a prerequisite for any chunk-level dedup, so the
  two size levers are not designed in conflict.
- **Schema-version discipline.** When Option A lands it bumps
  `_preserf_schema_version` and lives in the reserved `_preserf_*` / `_blobs`
  namespaces; pre-bump readers reject the new stores rather than
  misinterpreting references as data.
- **Interim stores are unchanged.** Until the gates are met, preserf keeps
  writing one variable per `(savepoint, field)`; existing stores and readers
  are unaffected by this ADR.

Revisit when: compression (#46) has landed; a downstream ICON evaluation
requires the dedup size win; or a follow-up spec proposes the concrete
blob-pool encoding (at which point a new ADR supersedes the relevant parts
of this one).

## References

- ADR [0002](0002-storage-model-mapping.md) — storage model and the
  group-per-savepoint, self-describing layout this decision must protect.
- [`docs/references/storage_mapping.md`](../references/storage_mapping.md) —
  §3.1 reserved `_preserf_*` namespace and `_preserf_schema_version`; §6
  per-savepoint field-data variables; §9 deferred chunking/compression.
- Issue #47 — the measured 2.63× / 11 GB vs 31.7 GB evidence and the
  data-model constraints that make this an ADR.
- Issue #46 — sibling chunking/compression decision (the orthogonal,
  lower-effort size lever, sequenced first).
- Serialbox content-dedup: checksum-keyed `fields_table` in
  `ArchiveMetaData`, resolved against the binary archive in
  `src/serialbox/core/archive/BinaryArchive.cpp` (function and file names
  are the stable anchors; line ranges drift) in
  [GridTools/serialbox](https://github.com/GridTools/serialbox).
