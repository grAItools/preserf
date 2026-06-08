# 5. Content deduplication of identical field writes across savepoints

## Status

Proposed

## Context

preserf stores **every `(savepoint, field)` write as its own netCDF
variable** under `/savepoints/sp_NNNNNN/<fieldname>` (ADR
[0002](0002-storage-model-mapping.md);
[`docs/references/storage_mapping.md`](../references/storage_mapping.md) §6,
worked example §8). A field whose value is unchanged across many savepoints
is therefore stored once per savepoint. Serialbox, by contrast, content-
**deduplicates**: it checksums each write and, when the checksum already
exists, records a _reference_ to the stored copy instead of writing the bytes
again.

The size impact is large and measured, not hypothetical. For the icon4py
reference dataset `exclaim_ch_r04b09_dsl`, single rank (`mpitask1_…_v04`),
analysed from Serialbox's own `ArchiveMetaData` plus the savepoint table
(reported in issue #47):

- 96 savepoints, **2077 `(savepoint, field)` write references**,
- collapsing to **789 unique stored versions** (checksum-based; 0 duplicate
  checksums in `fields_table`),
- i.e. **2.63×** — about 62% of writes are redundant copies.

On disk for that experiment: Serialbox **11 GB** vs preserf **31.7 GB** (all
2077 writes, uncompressed). The ~2.9× gap is essentially this deduplication
plus NetCDF4/HDF5 per-object overhead. This is the headline blocker for
evaluating preserf as a Serialbox2 replacement in ICON, where the reference
data is regenerated and stored repeatedly.

The design constraint that governs this decision is **the reader contract**.
ADR 0002's central property is that a savepoint store _is_ self-describing:
`xr.open_datatree` / `zarr.open_group` / `netCDF4-python` read it with **no
preserf-specific tooling** (ADR 0002 Consequences; storage_mapping §2). Any
deduplication scheme must be weighed first against that property — a scheme
that requires consumers to install or vendor a preserf "resolving reader"
trades away the main reason the format was chosen.

### Why this is an architecture decision, not a localized change

Deduplication is **not transparently available** in either target format:

- **NetCDF4 / HDF5 data model:** no content dedup. Two identical variables
  always occupy separate storage; there is no native "store-once,
  reference-many" concept for variable _data_.
- **HDF5 hard links** _would_ give true in-file dedup — one refcounted
  dataset reachable from many group paths, fully transparent to any HDF5
  reader. But **netcdf-c does not expose HDF5 link creation** (only `nf90_*`
  is committed to, ADR 0002), so links can only be added by post-processing
  the closed file with raw HDF5 / h5py. Worse, preserf's dimensions are
  **per-field, per-savepoint, independent** (storage_mapping §6): a hard
  link reached through a second savepoint group does **not** carry valid
  netCDF4 dimensions there, and Unidata's own documentation warns that
  editing dimension-scale attributes outside the HDF5 dimension-scale API
  breaks netCDF4 readability. The one mechanism that would be "free" is
  unreachable without fragile surgery on exactly the metadata that is most
  load-bearing.
- **NCZarr / Zarr** has no native chunk or variable deduplication. Chunk keys
  are positional; the V3 sharding codec packs but never dedups; and the
  manifest / reference approaches (kerchunk, VirtualiZarr, Icechunk) are
  **not** readable by stock zarr-python — they require an extra resolving
  library, i.e. exactly the "special reader" this decision must avoid.
- **Filesystem-level dedup** (reflinks, hard-linked chunk files, ZFS) is
  storage-system-dependent and outside the format: it does not survive
  `cp -r`, object-store upload, or copy to ext4, and so cannot be relied on
  for portable reference data.

The Serialbox numbers establish that deduplication is the single largest size
lever; the format constraints establish that capturing it _transparently_
requires a schema-level decision. This ADR settles that decision.

### The distinction that unlocks the design

The reason dedup is usually framed as "needs a special reader" is a
conflation of two different kinds of "reference":

- An **opaque byte handle** — a `(blob, offset, length)` tuple or content
  hash stored where the data used to be. A naive reader sees a handle, not a
  field, and must run preserf code to resolve it. This _does_ break
  self-describing reads.
- An **integer index into an ordinary array** — the field's distinct values
  are stored once in a normal array, and each use records which row it wants.
  A reader resolves this with **standard fancy indexing**
  (`array[index]`), which every numpy / xarray / zarr / netCDF4 user already
  does. **No preserf code is required.**

This is the classic **dictionary encoding** used by Parquet/Arrow, pandas
`Categorical`, and (in spirit) CF "compression by gathering": store unique
values once, plus an index that scatters them back. It is idiomatic in both
target formats because both are, at bottom, the same n-dimensional-array +
index-variable model. It is also a faithful mirror of Serialbox's _own_
model, which already references field versions by `fieldID`
(`fields_per_savepoint[i][field] = fieldID`) into a checksum-keyed table
(storage_mapping §7).

## Decision

Adopt **dictionary-encoded, per-field version pools** as the deduplication
mechanism: store each field's distinct content versions once in a pooled
array and have each savepoint reference its version by **integer index**.
This supersedes the in-file content-addressed _blob pool with opaque
references_ direction that an earlier draft of this ADR recommended.

**Scope of the dedup, stated honestly.** This encoding deduplicates
**identical writes of the same field across savepoints** — the dominant
source of the measured redundancy (a field unchanged across many savepoints
is stored once). It does **not**, as specified in decisions 1–2,
deduplicate **identical bytes that originate from *different* fields**: each
field gets its own pool, so two distinct fields that happen to share content
are stored twice. The earlier blob-pool direction, being a *single* global
content-addressed store (`hash → (blob, offset, length)`, like Serialbox's
global checksum-keyed `fields_table`), is field-agnostic and so captures
cross-field duplication too — and the headline **2.63×** is itself a *global*
figure (789 globally-unique checksums out of 2077 writes), folding in both
axes. The per-field pool trades that cross-field coverage for transparent,
stock-reader reads: a *global* pool of heterogeneously-shaped fields is
naturally a flat byte buffer addressed by `(offset, length)` — i.e. exactly
the opaque handle that forces a preserf resolving reader. Keeping each pool a
clean, single-shape, standard-indexable array is *what* makes
`pool["u"].isel(...)` work without preserf code, and that requires
partitioning the content. See decision 5 for the refinement that recovers
essentially all *practically-occurring* cross-field duplication while keeping
that transparency, and the Alternatives entry for why the fully-global
opaque pool is rejected as the primary scheme.

### 1. A reserved `/_field_versions` group holds the unique versions

A new top-level group `/_field_versions`, sibling to `/_fields` and
`/savepoints`, is created lazily the first time a field is written under
dedup. For each field `<name>` it holds:

- `/_field_versions/<name>` — an ordinary variable of shape
  `(<name>_version, <spatial dims…>)`, dtype derived from
  `/_fields/<name>:type_id`. Slice `v` along the leading
  **`<name>_version`** dimension is the `v`-th _distinct_ byte-content ever
  written for that field. The spatial dimensions are defined **once** here
  and shared across all versions (this also resolves the §9 "shared
  dimensions" open question for pooled data). `<name>_version` is an
  **unlimited / resizable** dimension so new versions append via
  `nf90_put_var(..., start=[v, 1, …], count=[1, …])`.
- `/_field_versions/<name>__index` — an integer (`NF90_INT`) variable of
  shape `(savepoint,)` indexed by the global savepoint position; entry `k` is
  the version slice that savepoint `k` used, or `-1` where the field was not
  written at that savepoint. This is the authoritative, vectorised-read index.

The `<name>__index` suffix joins the reserved namespace and is rejected as a
user field name (the same way `__preserf_type_id` is reserved,
storage_mapping §3.3).

### 2. Savepoints reference versions; the per-savepoint data variable moves

Under dedup, a `!$SER DATA` / `!$SER TRACER` write at a savepoint no longer
creates `/savepoints/sp_NNNNNN/<name>`; the bytes live in the pool
(decision 1). For browsability, the savepoint group gains an **optional**
reserved attribute

```
_preserf_field_versions = [name0, ver0, name1, ver1, …]
```

(a length-2N string vector, mirroring the existing `_preserf_field_ids`
convention, storage_mapping §7) so a savepoint remains self-documenting about
_which_ versions it holds. A reader never needs this attribute to reconstruct
data — the `__index` array (decision 1) is sufficient — but it keeps the
savepoint group enumerable by eye and by naive tools.

This is the one property ADR 0002 gives up: a naive browser of
`/savepoints/sp_000010/` no longer finds `u` as a directly-named data
variable there. It finds the savepoint's metainfo and, via the index, the
pooled bytes. The trade is deliberate and is what buys transparent,
portable, both-backend dedup (see Consequences and Alternatives).

### 3. Standard-reader reconstruction (no preserf library)

```python
ds   = xr.open_datatree("store.nc")          # or zarr.open_group(...)
pool = ds["/_field_versions"]
u_all     = pool["u"].isel(u_version=pool["u__index"])      # u over all savepoints
u_at_sp10 = pool["u"].isel(u_version=int(pool["u__index"][10]))
```

Pure xarray / numpy indexing, identical for NetCDF4 and NCZarr, on local disk
or an object store. The only knowledge required is a documented _layout
convention_ — exactly as a reader today must know data lives at
`/savepoints/sp_N/<field>`. No new runtime dependency, no resolving library,
no kerchunk/fsspec.

### 4. Write-time dedup in the Fortran helper (runtime, no post-process)

Because the encoding is expressible in plain `nf90_*` calls, dedup happens
**live** during the run, with no offline compaction step. At the existing
field-write hook (`src/preserf-fortran/preserf_write_field.inc`, between
`ensure_variable` and `nf90_put_var`):

1. Compute a strong content hash of the data buffer. A small self-contained
   Fortran hash routine is added (e.g. FNV-1a / xxHash); it introduces **no
   external dependency**, so no new-dependency ADR is required. An optional
   byte-verify-on-hash-match guards against collisions behind a flag.
2. Consult a per-field in-memory `hash → version` map (module state in
   `utils_preserf.f90`). On a **miss**, append the buffer as the next
   `<name>_version` slice and record the mapping; on a **hit**, reuse the
   existing version and write no data.
3. Record `<name>__index[savepoint] = version` and append the savepoint
   browse attribute (decision 2).

The map stores hashes and integers, **not** the field bytes, so the memory
cost is small. Read mode is the mirror: resolve `<name>__index[savepoint]`
then read that pool slice back into the host array — a contained change to
the helper's read path.

### 5. Optional refinement — pool by `(type_id, shape)` to recover cross-field dedup

The per-field pool (decisions 1–4) misses duplication between *distinct*
fields that share content. A **`(type_id, shape)`-keyed pool** recovers
essentially all of it while keeping every pool a clean, standard-indexable
array:

- Replace per-field `/_field_versions/<name>` with shape-bucketed pools
  `/_field_versions/pool_<type_id>_<shape>` (a stable, derived bucket name).
  Every field with that dtype and shape shares the bucket, so an all-zero
  version written by `u` and by `v` collapses to one slice.
- The index becomes a `(pool, version)` pair rather than a bare version: a
  field's `<name>__index` still gives the version, and the field's
  `/_fields/<name>` carrier records which bucket it resolves against (its
  `type_id` + `dims` already determine it). Reconstruction stays pure
  indexing — `pool.isel(version=…)` — just against a shared array.

The decisive observation: **identical bytes require identical byte length**,
so two fields can only collide if they have the same element count and dtype.
Bucketing by `(type_id, shape)` therefore catches every realistic cross-field
collision — most importantly the **all-zero / constant-init** case, where
many distinct same-shaped fields share content at early savepoints. The
*only* duplication it still misses is between fields whose shapes differ but
whose flattened bytes coincide (e.g. `(10,20)` vs `(200,)` of the same
dtype) — degenerate for real array data and not worth a flat byte pool to
catch. This refinement is thus strictly more general than per-field pooling
and strictly more transparent than the global opaque blob pool, recovering
near-all cross-field redundancy with no special reader.

Whether to ship decision 5 from the start or as a follow-up depends on how
much of the measured redundancy is cross-field — a question the issue #47
data does not yet break down (it would require grouping the 789 unique
checksums by how many distinct field names map to each). The per-field pool
(decisions 1–4) is the floor; the bucketed pool is the natural upgrade if
that breakdown shows material cross-field collision, and it is a localized
change (bucket naming + a `(pool, version)` index) rather than a new schema
direction.

### Schema version

This changes what a savepoint variable means and where field data lives, so
it is **non-additive**: it bumps `_preserf_schema_version` to **2**
(storage_mapping §3.1) and lives entirely in the reserved `_field_versions`
group / `_preserf_*` / `__index` namespaces. Pre-bump readers reject a v2
store loudly rather than misinterpreting an index for data, per the existing
reserved-namespace rule.

### Rollout

Dedup ships **opt-in, default off**, behind a `!$SER INIT dedup=` keyword
(threaded through `ppser_initialize`, `src/preserf-fortran/utils_preserf.f90`).
With it off, preserf writes the schema-v1 per-savepoint layout unchanged, so
existing stores and readers are untouched. The default flips to on only after
an ICON validation run confirms the size win and round-trip fidelity. This
mirrors how chunking/compression are slated to arrive as `!$SER OPTION` knobs
(storage_mapping §9, sibling issue #46).

### Alternatives considered

- **In-file content-addressed blob pool + opaque references (the earlier
  recommendation).** A reserved `/_blobs` pool plus per-savepoint
  `(blob, offset, length)` reference attributes. Being a *single global*
  content-addressed store, it dedups on **both** axes — cross-savepoint *and*
  cross-field — so it captures the full *global* 2.63× and keeps the store a
  single artifact. That cross-field coverage is its one genuine advantage
  over the per-field dictionary encoding (decisions 1–4); the
  `(type_id, shape)`-bucketed refinement (decision 5) closes most of that gap
  transparently. Rejected as the primary scheme because the reference is an
  _opaque handle_: `xr.open_datatree` yields a handle, not a field, so the
  store is unreadable without a preserf resolving reader — the exact cost
  this decision exists to avoid. The dictionary encoding gives up full
  cross-field coverage to keep stock-reader reads.
- **HDF5 hard links (netCDF4 only).** Fully transparent and refcounted _for
  HDF5 readers_, so the savepoint path would stay byte-identical. Rejected:
  `nf90_*` cannot create links (needs an offline h5py/libhdf5 pass); a link
  reached through a second savepoint group carries no valid netCDF4
  dimensions, and fixing that means dimension-scale surgery Unidata
  explicitly warns against; and there is **no portable Zarr analog**, so it
  fails the "idiomatic in both formats" bar.
- **Filesystem hard links / reflinks on Zarr chunk files.** Transparent only
  at the OS level and zarr-unaware; destroyed by `cp -r` and object-store
  upload (survives only `tar`). Unusable for portable reference data.
- **Kerchunk / VirtualiZarr / Icechunk manifests; Zarr V3 sharding.**
  Manifests express dedup but are not readable by stock zarr-python (require
  kerchunk/fsspec/Icechunk and are not yet in the core spec); sharding packs
  but never dedups. Both fail the no-special-reader constraint.
- **Do nothing; lean on compression only (#46).** Compression is the cheap,
  orthogonal, fully self-describing lever and should land regardless, but it
  re-compresses each identical copy independently and so cannot recover the
  structural 2.63×. It is the correct _interim_ posture while dedup is
  opt-in, not a substitute.

## Consequences

- **Dedup is transparent and portable.** Any stock reader reconstructs field
  data with standard array indexing, identically for NetCDF4 and NCZarr, on
  disk or in object storage, in a single self-contained artifact. No preserf
  reader, no kerchunk/fsspec, no filesystem tricks.
- **Self-describing reads are preserved in substance, relocated in form.**
  All data remains ordinary, independently-readable arrays; what changes is
  that a field is read from `/_field_versions/<name>` via an index rather
  than from `/savepoints/.../<name>` directly. The savepoint browse attribute
  keeps savepoints enumerable. This is the deliberate trade against ADR
  0002's "the savepoint group _is_ the data" property.
- **Live, low-memory write path.** Dedup runs inside the existing Fortran
  helper with plain `nf90_*` calls; the per-field hash map holds hashes and
  integers, not bytes. No offline compaction tool is introduced.
- **Cross-field duplication is out of scope by default.** The per-field pool
  (decisions 1–4) captures cross-savepoint redundancy only — the dominant
  source — and stores identical bytes originating from *different* fields
  twice, unlike the global blob pool. The `(type_id, shape)`-bucketed pool
  (decision 5) recovers essentially all *practically-occurring* cross-field
  duplication (notably all-zero / constant-init fields) while keeping reads
  transparent, and is the planned upgrade if the #47 data shows material
  cross-field collision. So the per-field figure is a *lower bound* on the
  achievable dedup, not the full global 2.63×.
- **Coupled to #46.** Compression is the orthogonal lever and the interim
  posture while dedup is opt-in; the version pool also gives compression a
  clean, deduplicated array to filter, so the two size levers compose rather
  than conflict. Chunk-level (rather than whole-version) dedup is a possible
  future refinement that would key on the chunk shape #46 fixes.
- **Schema-version discipline.** v2 stores live in the reserved
  `_field_versions` / `_preserf_*` namespaces and pre-bump readers reject
  them; v1 stores are unaffected while dedup stays opt-in.
- **Reader and tests follow.** The Python reference reader
  (`tests/_support/storage.py`) gains a `/_field_versions` + `__index`
  resolution path; a dedicated test reconstructs fields with **stock
  xarray** (no preserf code) to keep the transparency claim honest, alongside
  a size-regression assertion on a repeated-field fixture.

Revisit when: an ICON evaluation requires flipping dedup on by default;
compression (#46) lands and chunk-level dedup becomes worth specifying; or
string/extended-dtype data fields land (storage_mapping §9), which the pool
must then accommodate.

## References

- ADR [0002](0002-storage-model-mapping.md) — storage model and the
  group-per-savepoint, self-describing layout this decision must protect.
- [`docs/references/storage_mapping.md`](../references/storage_mapping.md) —
  §1 types, §1.1 axis order, §3.1 reserved `_preserf_*` namespace and
  `_preserf_schema_version`, §6 per-savepoint field-data variables, §7
  Serialbox `fieldID` indirection, §8 worked example, §9 deferred
  chunking/compression and shared dimensions.
- Issue #47 — the measured 2.63× / 11 GB vs 31.7 GB evidence and the
  data-model constraints that make this an ADR.
- Issue #46 — sibling chunking/compression decision (the orthogonal,
  lower-effort size lever).
- Serialbox content-dedup: checksum-keyed `fields_table` in
  `ArchiveMetaData`, resolved against the binary archive in
  `src/serialbox/core/archive/BinaryArchive.cpp` in
  [GridTools/serialbox](https://github.com/GridTools/serialbox) (function and
  file names are the stable anchors; line ranges drift).
- Dictionary-encoding prior art: Apache Parquet / Arrow dictionary encoding,
  pandas `Categorical`, and CF "compression by gathering" — store unique
  values once plus an index that scatters them back.
