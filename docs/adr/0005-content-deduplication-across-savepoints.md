# 5. Content deduplication of identical field writes across savepoints and fields

## Status

Proposed

## Context

preserf stores **every `(savepoint, field)` write as its own netCDF
variable** under `/savepoints/sp_NNNNNN/<fieldname>` (ADR
[0002](0002-storage-model-mapping.md);
[`docs/references/storage_mapping.md`](../references/storage_mapping.md) §6,
worked example §8). Identical bytes are therefore stored once per write, in
two distinct ways:

- **across savepoints** — a field unchanged over many savepoints is stored
  once per savepoint (the dominant case); and
- **across fields** — two _different_ fields that happen to hold identical
  bytes (most commonly same-shaped fields that are all-zero / constant at
  init) are each stored in full.

Serialbox, by contrast, content-**deduplicates** on both axes at once: it
checksums each write and, when the checksum already exists _anywhere_,
records a _reference_ to the stored copy instead of writing the bytes again.
Its checksum table is global, so it is blind to which field produced a given
buffer.

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
plus NetCDF4/HDF5 per-object overhead. Because Serialbox's table is global,
the 2.63× already folds in **both** the cross-savepoint and cross-field axes;
a preserf scheme that wants to match it must capture both. This is the
headline blocker for evaluating preserf as a Serialbox2 replacement in ICON,
where the reference data is regenerated and stored repeatedly.

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
  link reached through a second group does **not** carry valid netCDF4
  dimensions there, and Unidata's own documentation warns that editing
  dimension-scale attributes outside the HDF5 dimension-scale API breaks
  netCDF4 readability. The one mechanism that would be "free" is unreachable
  without fragile surgery on exactly the metadata that is most load-bearing.
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
- An **integer index into an ordinary array** — the distinct values are
  stored once in a normal array, and each use records which row it wants. A
  reader resolves this with **standard fancy indexing** (`array[index]`),
  which every numpy / xarray / zarr / netCDF4 user already does. **No preserf
  code is required.**

This is the classic **dictionary encoding** used by Parquet/Arrow, pandas
`Categorical`, and (in spirit) CF "compression by gathering": store unique
values once, plus an index that scatters them back. It is idiomatic in both
target formats because both are, at bottom, the same n-dimensional-array +
index-variable model. It is also a faithful mirror of Serialbox's _own_
model, which already references field versions by `fieldID`
(`fields_per_savepoint[i][field] = fieldID`) into a checksum-keyed table
(storage_mapping §7).

The index-into-an-array trick captures redundancy on **whatever axis the
pooled array spans**. The only real design choice is therefore *how to
partition the pooled bytes so each pool stays an ordinary, standard-indexable
array while spanning as many duplicates as possible*:

- One array **per field** → captures cross-savepoint duplicates only.
- One **global** array → would capture cross-field duplicates too, but fields
  have heterogeneous shapes and dtypes, which do not fit one rectangular
  array; a truly global pool is therefore a flat byte buffer addressed by
  `(offset, length)` — i.e. the opaque handle that breaks transparent reads.
- One array **per `(dtype, shape)` bucket** → the sweet spot: every member of
  a bucket has identical shape by construction, so the pool is a clean
  rectangular array _and_ it is shared across all fields of that shape,
  capturing cross-field duplicates. The decisive fact is that **identical
  bytes require identical byte length** — two buffers can only be equal if
  they have the same element count and dtype — so bucketing by `(dtype,
  shape)` puts every realistically-collidable pair of writes into the same
  pool, from *either* field, from *any* savepoint.

This ADR therefore pools by `(dtype, shape)`.

## Decision

Adopt **dictionary-encoded, `(type_id, shape)`-keyed version pools** as the
deduplication mechanism. Store each _distinct content buffer_ once in a pool
shared by all fields of its dtype and shape, and have each `(savepoint,
field)` write reference its version by an **integer index** into that pool.
This deduplicates **both** axes — across savepoints and across fields —
while every pool remains an ordinary array a stock reader resolves by
indexing, with no preserf resolving library.

### 1. A reserved `/_field_versions` group holds shape-keyed pools

A new top-level group `/_field_versions`, sibling to `/_fields` and
`/savepoints`, is created lazily the first time a field is written under
dedup. It holds two kinds of reserved variables:

- **Pools, one per `(type_id, shape)` bucket.** A variable
  `/_field_versions/pool_t<type_id>_<shape>` (e.g. `pool_t6_65x80` for a
  `float64` field of C-order shape `65×80`; `pool_t6_scalar` for a scalar).
  Its shape is `(<bucket>_version, <spatial dims…>)`, dtype derived from
  `type_id`. Slice `v` along the leading **`<bucket>_version`** dimension is
  the `v`-th _distinct_ buffer ever written with that dtype and shape, **by
  any field, at any savepoint**. The spatial dimensions are defined **once**
  per bucket and shared across all versions and all member fields — which is
  sound precisely because bucket membership _is_ "same shape", and which also
  resolves the §9 "shared dimensions" open question for pooled data.
  `<bucket>_version` is an **unlimited / resizable** dimension so new versions
  append via `nf90_put_var(..., start=[v, 1, …], count=[1, …])`.
- **Per-field indices.** A variable `/_field_versions/<name>__index`, integer
  (`NF90_INT`), shape `(savepoint,)`. Entry `k` is the version slice — within
  the field's bucket — that field `<name>` used at savepoint `k`, or `-1`
  where the field was not written at that savepoint. This is the
  authoritative, vectorised-read index.

The `pool_*` names and the `<name>__index` suffix join the reserved namespace
and are rejected as user field names (the same way `__preserf_type_id` is
reserved, storage_mapping §3.3).

### 2. Fields point at their bucket; the per-savepoint data variable moves

A field resolves to its bucket via its existing `/_fields/<name>` carrier:
`type_id` + `dims` already determine the bucket, and the carrier additionally
records `_preserf_version_pool = "<bucket name>"` (an `NF90_CHAR` attribute)
so a reader never has to reconstruct the bucket-naming convention itself.

Under dedup, a `!$SER DATA` / `!$SER TRACER` write at a savepoint no longer
creates `/savepoints/sp_NNNNNN/<name>`; the bytes live in the bucket
(decision 1). For browsability, the savepoint group gains an **optional**
reserved attribute

```
_preserf_field_versions = [name0, ver0, name1, ver1, …]
```

(a length-2N string vector, mirroring the existing `_preserf_field_ids`
convention, storage_mapping §7), where `verK` is the version of `nameK`
within its bucket, so a savepoint remains self-documenting about _which_
versions it holds. A reader never needs this attribute to reconstruct data —
the `__index` array (decision 1) is sufficient — but it keeps the savepoint
group enumerable by eye and by naive tools.

This is the one property ADR 0002 gives up: a naive browser of
`/savepoints/sp_000010/` no longer finds `u` as a directly-named data
variable there. It finds the savepoint's metainfo and, via the index and the
field's bucket, the pooled bytes. The trade is deliberate and is what buys
transparent, portable, both-axis dedup (see Consequences and Alternatives).

### 3. Standard-reader reconstruction (no preserf library)

```python
ds     = xr.open_datatree("store.nc")          # or zarr.open_group(...)
pool   = ds["/_field_versions"]
bucket = ds["/_fields"]["u"].attrs["_preserf_version_pool"]   # "pool_t6_65x80"
vdim   = f"{bucket}_version"

u_all     = pool[bucket].isel({vdim: pool["u__index"]})       # u over all savepoints
u_at_sp10 = pool[bucket].isel({vdim: int(pool["u__index"][10])})
```

Pure xarray / numpy indexing, identical for NetCDF4 and NCZarr, on local disk
or an object store. Cross-field dedup is invisible to the reader: if field
`v` shares `u`'s bucket and reused version 3, then `v__index` simply points
at the same slice — the reader indexes it the same way and gets the right
bytes. The only knowledge required is a documented _layout convention_ —
exactly as a reader today must know data lives at `/savepoints/sp_N/<field>`.
No new runtime dependency, no resolving library, no kerchunk/fsspec.

### 4. Write-time dedup in the Fortran helper (runtime, no post-process)

Because the encoding is expressible in plain `nf90_*` calls, dedup happens
**live** during the run, with no offline compaction step. At the existing
field-write hook (`src/preserf-fortran/preserf_write_field.inc`, between
`ensure_variable` and `nf90_put_var`):

1. Derive the bucket from the write's `(type_id, shape)`; ensure the bucket
   pool and the field's `_preserf_version_pool` attribute exist.
2. Compute a strong content hash of the data buffer. A small self-contained
   Fortran hash routine is added (e.g. FNV-1a / xxHash); it introduces **no
   external dependency**, so no new-dependency ADR is required. An optional
   byte-verify-on-hash-match guards against collisions behind a flag.
3. Consult a **per-bucket** in-memory `hash → version` map (module state in
   `utils_preserf.f90`). On a **miss**, append the buffer as the next
   `<bucket>_version` slice and record the mapping; on a **hit** — whether
   the matching buffer was first written by this field or another field of
   the same shape — reuse the existing version and write no data.
4. Record `<name>__index[savepoint] = version` and append the savepoint
   browse attribute (decision 2).

Keying the map per bucket (not per field) is exactly what makes the dedup
cross-field: the first field to write an all-zero `65×80` buffer populates
the slice, and every later field of that shape with the same bytes hits it.
The maps store hashes and integers, **not** the field bytes, and there is one
per bucket (buckets ≈ number of distinct `(dtype, shape)` combinations, a
small number), so memory cost is small. Read mode is the mirror: resolve
`<name>__index[savepoint]`, read that slice of the field's bucket back into
the host array — a contained change to the helper's read path.

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

- **Per-field version pools (one pool per field, keyed by field name).** The
  simpler variant of the chosen scheme: `/_field_versions/<name>` holds only
  that field's distinct versions, indexed by `<name>__index`. Equally
  transparent (same indexing reconstruction) and slightly simpler — no bucket
  naming, the index is a bare version. Rejected as the primary scheme because
  it captures **cross-savepoint duplicates only**: two distinct fields with
  identical bytes are stored twice, leaving the cross-field component of the
  measured 2.63× on the table. Bucketing by `(type_id, shape)` recovers that
  component at negligible extra cost (a derived bucket name and a per-field
  `_preserf_version_pool` attribute) while keeping every pool an ordinary
  array, so there is no transparency reason to prefer per-field pooling. The
  per-field layout is the natural _fallback_ if the bucketed indexing proves
  awkward in practice, and is a localized de-generalization of decision 1, not
  a different schema direction.
- **In-file content-addressed blob pool + opaque references.** A reserved
  `/_blobs` pool plus per-savepoint `(blob, offset, length)` reference
  attributes. Being a _single global_ content-addressed store, it dedups on
  both axes — including the degenerate cross-shape case the bucketed pool
  misses (different shapes whose flattened bytes coincide) — and keeps the
  store a single artifact. Rejected because the reference is an _opaque
  handle_: `xr.open_datatree` yields a handle, not a field, so the store is
  unreadable without a preserf resolving reader — the exact cost this
  decision exists to avoid. The `(type_id, shape)` pool gives up only that
  degenerate cross-shape case (vanishingly rare for real array data, since
  equal bytes almost always implies equal shape) to keep stock-reader reads.
- **HDF5 hard links (netCDF4 only).** Fully transparent and refcounted _for
  HDF5 readers_, so the savepoint path would stay byte-identical. Rejected:
  `nf90_*` cannot create links (needs an offline h5py/libhdf5 pass); a link
  reached through a second group carries no valid netCDF4 dimensions, and
  fixing that means dimension-scale surgery Unidata explicitly warns against;
  and there is **no portable Zarr analog**, so it fails the "idiomatic in both
  formats" bar.
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

- **Dedup is transparent and portable, on both axes.** Any stock reader
  reconstructs field data with standard array indexing — including across
  fields, which is invisible to it — identically for NetCDF4 and NCZarr, on
  disk or in object storage, in a single self-contained artifact. No preserf
  reader, no kerchunk/fsspec, no filesystem tricks.
- **Self-describing reads are preserved in substance, relocated in form.**
  All data remains ordinary, independently-readable arrays; what changes is
  that a field is read from its `(type_id, shape)` pool via an index rather
  than from `/savepoints/.../<name>` directly. The savepoint browse attribute
  keeps savepoints enumerable. This is the deliberate trade against ADR
  0002's "the savepoint group _is_ the data" property.
- **Coverage vs. the global figure.** The bucketed pool captures every
  cross-savepoint duplicate and every cross-field duplicate _of equal shape_
  — which, because equal bytes implies equal byte length, is essentially all
  real duplication. The only thing it cannot collapse is the degenerate case
  of equal bytes across _different_ shapes; only the rejected global opaque
  blob pool catches that, at the cost of a special reader. So the achievable
  dedup is at or near the global 2.63×, not a cross-savepoint-only lower
  bound.
- **Live, low-memory write path.** Dedup runs inside the existing Fortran
  helper with plain `nf90_*` calls; the per-bucket hash maps hold hashes and
  integers, not bytes, and there are only as many maps as distinct
  `(dtype, shape)` combinations. No offline compaction tool is introduced.
- **Coupled to #46.** Compression is the orthogonal lever and the interim
  posture while dedup is opt-in; the pools also give compression a clean,
  deduplicated array to filter, so the two size levers compose rather than
  conflict. Chunk-level (rather than whole-version) dedup is a possible future
  refinement that would key on the chunk shape #46 fixes.
- **Schema-version discipline.** v2 stores live in the reserved
  `_field_versions` / `_preserf_*` namespaces and pre-bump readers reject
  them; v1 stores are unaffected while dedup stays opt-in.
- **Reader and tests follow.** The Python reference reader
  (`tests/_support/storage.py`) gains a `/_field_versions` + bucket + `__index`
  resolution path; dedicated tests reconstruct fields with **stock xarray**
  (no preserf code) to keep the transparency claim honest — one asserting a
  field constant across savepoints pools to a single version, and one
  asserting two distinct same-shaped fields with identical bytes share a
  single pooled slice — alongside a size-regression assertion on a
  repeated-field fixture.

Revisit when: an ICON evaluation requires flipping dedup on by default;
compression (#46) lands and chunk-level dedup becomes worth specifying; or
string/extended-dtype data fields land (storage_mapping §9), which the pools
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
