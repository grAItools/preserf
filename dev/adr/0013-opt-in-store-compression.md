# 13. Opt-in store compression: the request surface is a store-wide knob

## Status

Accepted

## Context

Three candidate surfaces existed for requesting field-write
compression, and the repository's artifacts disagreed about which
one to use:

- PR #53 (the implementation) used a store-wide `compression=`
  keyword on `ppser_initialize`, mirroring the existing `backend=`
  keyword, plus a `PRESERF_COMPRESSION` environment variable.
- The storage reference (`dev/references/storage_mapping.md` §9)
  suggested `!$SER OPTION` keys and deferred naming.
- The `improve-store-efficiency` change originally pinned the
  Fortran registration API (`fs_register_field` and the
  auto-registration path).

The registration-API surface is not implementable as written:
`!$SER REGISTER` rejects key=value pairs, `!$SER OPTION` accepts
only `verbosity`, and the auto-registration path carries no
caller-supplied metadata — so a per-field request requires
preprocessor work the design explicitly ruled out. Meanwhile the
issue body (#46) and the nczarr follow-up change (for #111)
describe the store-wide knob; the storage reference deferred the
name.

## Decision

- The compression request surface is a store-wide default at
  `ppser_initialize`: a `compression=` keyword (mirroring `backend=`)
  plus a `PRESERF_COMPRESSION` environment variable, with module
  state and `eff_backend`-aware validation, as PR #53 implements.
- A per-field override through `fs_register_field` is an explicit
  follow-up, not part of this decision.
- Chunk shapes are derived from the registered dims and bounded,
  not whole-variable (HDF5 aborts above 4 GiB per chunk, and one
  chunk per field defeats partial reads).
- Tracer data follows the global knob: tracer variables are store
  variables like any other.
- The NCZarr combination (`compression>0` + `backend=nczarr-v2`)
  is rejected at initialization until the codec follow-up (#111)
  lands.

## Consequences

- The spec layer now matches the surface PR #53 implements,
  narrowing the drift between `improve-store-efficiency` and
  PR #53 to the chunk-shape and bounded-chunk corrections its
  rebase must apply.
- Per-field granularity is deferred until a caller-supplied
  metadata path exists on the auto-registration route.
- PR #53's mechanism (chunking + deflate plumbing, level
  precedence, the backend guard) is the starting point for the
  change's apply step; its surface decision is no longer carried
  by a PR but by this record.
- The `nczarr-compression-codec` change's premise (rejection at
  the `ppser_initialize` boundary) is consistent with this
  decision.
