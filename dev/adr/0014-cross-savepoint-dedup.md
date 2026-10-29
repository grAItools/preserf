# 14. Opt-in cross-savepoint content deduplication via dictionary encoding

## Status

Accepted

## Context

preserf stores every `(savepoint, field)` write as its own dataset under
`/savepoints/sp_NNNNNN/<fieldname>` (ADR 0002, storage_mapping.md §6).
Serialbox, by contrast, content-deduplicates identical writes by
checksum: its binary archive stores each unique field version once and
has every savepoint that wrote an identical payload reference the same
stored version. On the icon4py `exclaim_ch_r04b09_dsl` reference run this
is a measured 2.63x difference — 2077 write references collapse to 789
unique stored versions (issue #47). For workloads whose fields are
unchanged across many savepoints, a preserf store is substantially larger
than the Serialbox equivalent for the same data.

There is no transparent content deduplication in the NetCDF4 or NCZarr
data models: two identical variables always occupy separate storage. HDF5
hard links would give true in-file dedup (one refcounted dataset, many
group paths), but netcdf-c does not expose them, and raw-HDF5 link surgery
on a netcdf-managed file is unsupported and fragile. So dedup has to be
modelled explicitly, above the netCDF layer, in a form both the Fortran
helper and the Python reference reader can produce/resolve.

PRs #50 and #54 deliberated this without a resolution vehicle, and #144
deferred it pending a content-addressed store. Two shapes were on the
table:

- **Dictionary encoding** (the #54 line): one dataset per unique field
  payload, kept in a dedicated group; each savepoint stores a reference to
  the dictionary entry instead of the payload. Transparent to a reader
  that resolves a single indirection; keeps per-field, self-describing
  datasets.
- **Content-addressed blob pool** (the framing #144 defers against): one
  growable dataset plus an `(offset, len)` index, with per-savepoint
  references into the pool. Cheaper per object than many tiny datasets,
  but loses self-describing savepoint groups and moves reader complexity
  up a notch (pool-plus-offset arithmetic rather than one lookup).

## Decision

Add **opt-in cross-savepoint content deduplication using dictionary
encoding**, default **off** so existing stores stay byte-identical.

- When dedup is enabled for a store, each unique field payload is written
  once as a normal, named dataset in a lazily-created `/_dict` group
  (`/_dict/d<K>`, `K` a store-global 0-based counter). The entry name is a
  short global id rather than the field name so that the entry's dimension
  names (`d<K>_dim<j>`) stay within netCDF's 256-byte `NC_MAX_NAME` cap
  even for a near-limit field name; it is collision-free within `/_dict`.
  Every savepoint that writes that payload stores a scalar `NF90_INT`
  carrier variable named `<fieldname>` carrying a `_preserf_dict_ref`
  string attribute naming the dictionary entry, instead of the payload
  itself. A reader resolves one indirection: savepoint variable →
  `_preserf_dict_ref` → `/_dict/<entry>`.
- Deduplication is keyed by a content checksum over the raw payload bytes,
  combined with the byte length, matching Serialbox's "dedup identical
  writes by checksum" semantics. The checksum is a double modular
  polynomial hash (two independent primes near 2^31 combined into a 62-bit
  digest): every intermediate stays below 2^41, so it never relies on
  signed-integer overflow wraparound (which Fortran does not guarantee —
  an overflow-trapping build could abort), and it uses an int64 length and
  loop index so payloads larger than 2 GiB hash correctly. (An earlier
  draft used 64-bit FNV-1a, whose multiply overflows the signed range.)
  The checksum→entry map is a write-time, in-memory accelerator and is
  never persisted; the durable index lives _inside the store_ as the
  per-savepoint `_preserf_dict_ref` references plus the `/_dict` datasets
  (Serialbox keeps its index external only because its binary archive is
  flat `.dat` files).
- The option is threaded from `ppser_initialize` (a `dedup` keyword,
  resolved from the `PRESERF_DEDUP` environment variable when omitted, else
  the default), mirroring how `backend` is threaded, and recorded on the
  root group as `_preserf_dedup` (`NF90_BYTE`, `1`) **only when enabled**.
  A default store omits the attribute entirely — its absence means off —
  so a non-deduplicated store stays byte-identical to a pre-dedup build.
- A deduplicated store advertises a distinct **`_preserf_schema_version`
  of `2`** (default stores keep `1`). A dedup savepoint variable is a
  scalar reference carrier, not the payload, so a reader that ignores
  `_preserf_dict_ref` would silently return the carrier value instead of
  the data; the version bump makes such a reader reject the store at its
  version check rather than return wrong data. Both bundled readers (the
  Fortran `fs_read_field` path and `tests/_support/storage.py`) accept
  versions `1` and `2`.

Dictionary encoding is chosen over the blob pool for three reasons:

1. **Reader complexity is bounded** — one indirection (savepoint variable
   → dictionary entry), not pool-plus-offset arithmetic; the Python
   support reader resolves it with a single lookup per field.
2. **The self-describing layout survives** — each dictionary entry is a
   normal, named dataset, so a reader that ignores the dedup reference
   still sees a coherent store, which keeps the wire-compat test suite
   honest.
3. **It composes with append mode** — the dictionary grows by unique
   payload; the savepoint-group scanning append mode already requires
   extends naturally to reference the dictionary.

The content-addressed blob pool is recorded here as the **fallback** if
dictionary metadata overhead (many tiny datasets) measures poorly for very
large numbers of unique payloads. That trade-off is deferred, not decided
here.

## Consequences

- Default stores are unchanged and byte-identical: the dedup branch is
  gated on the opt-in flag, so the netcdf4/nczarr wire format for existing
  callers does not move.
- A deduplicated store is readable by any consumer that resolves the single
  `_preserf_dict_ref` indirection. The Python reference reader
  (`tests/_support/storage.py`) and the Fortran `fs_read_field` path both
  resolve it; a reader that does not understand the reference sees the
  scalar carrier variables and the `/_dict` group as ordinary, if
  uninterpreted, datasets rather than corrupt data.
- Dedup is scoped to `!$SER DATA` field writes. Tracer and k-buffer writes
  are not deduplicated (they remain one-dataset-per-write); extending to
  them is a future additive change.
- The write-time checksum index is in-memory and per-session. Within one
  session, identical payloads collapse. **Cross-session append-mode dedup**
  (rebuilding the in-memory index from an existing `/_dict` on an append
  open, so a resumed run dedups against previously written entries) is not
  implemented in this change — an appended session starts its index empty
  and may therefore write a duplicate of a payload a previous session
  already stored. This is a size inefficiency, never wrong data, and is
  tracked as follow-up work.
- Dedup trusts the checksum, as Serialbox does. A collision of the 62-bit
  digest between two genuinely different payloads of equal byte length
  would mis-dedup; the probability is negligible at realistic unique-version
  counts (hundreds to low thousands). The recorded blob-pool fallback,
  were it ever adopted, would be the place to add a byte-exact comparison
  on checksum match if a workload ever needed that guarantee.

Supersedes the undecided deliberations in PRs #50 / #54 and the deferral
in #144. Builds on ADR 0002 (storage model) and composes with the
compression work (a dictionary entry is itself a store variable, so
chunking/deflate apply to it like any other).
