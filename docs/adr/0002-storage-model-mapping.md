# 2. Storage model: map Serialbox data model onto NetCDF4 and Zarr V2 via NCZarr

## Status

Accepted

## Context

`preserf` reimplements the Fortran helper modules that the `pp_ser` directives
expand into. The original Serialbox helpers wrote a custom on-disk format
(`MetaData-<prefix>.json` + `ArchiveMetaData-<prefix>.json` + per-field `.dat`
files for the binary archive, or per-field `.nc` files for the NetCDF archive).
preserf must instead store **exactly the same logical data and metadata** —
global metainfo, savepoint sequence with typed metainfo, registered field
metadata (type, dims, halos), and the per-savepoint field snapshots — using
standard formats that the broader scientific Python / Fortran ecosystem can
read directly.

The two target formats are NetCDF4 (HDF5-backed) and Zarr V2. Zarr V3 support
is being added to `netcdf-c` (NCZarr) in an open PR and is deferred until that
work lands.

The mapping must satisfy:

1. Every Serialbox concept (global metainfo, savepoint vector, field map,
   per-savepoint field snapshots, typed scalar / array metainfo) has a
   well-defined, lossless landing spot. Heterogeneous savepoints (different
   fields at different savepoints, repeated savepoint names distinguished
   only by metainfo) must round-trip.
2. Both formats are produced by the **same** Fortran helper-module source
   code, so preserf does not need a second backend implementation.
3. The on-disk artifacts are idiomatic enough to be opened by xarray /
   netCDF4-python / zarr-python without preserf-specific tooling.
4. There is a forward path to Zarr V3 without rewriting the Fortran layer.

### Alternatives considered

**Backend choice:**

- _NCZarr (Zarr V2 backed) + NetCDF4, unified through `netcdf-fortran`_ —
  one Fortran codebase parameterised by a URL / mode string. Inherits any
  NCZarr V2 limitations in the installed netcdf-c.
- _Two separate backends_ — native HDF5 calls for NetCDF4, direct Zarr
  writes (via a C library) for Zarr V2. Each backend can be tuned, but two
  Fortran implementations to maintain and behavioural drift becomes likely.

**Layout choice:**

- _Group-per-savepoint_ — one subgroup per savepoint, with one variable per
  field actually written at that savepoint. Heterogeneous fields-per-savepoint
  is natural; many small groups but tooling handles them fine.
- _Time-series-per-field_ — one variable per registered field along an
  unlimited `savepoint` dimension. Looks like a conventional netCDF dataset
  but forces every field to be present at every savepoint (semantic change
  from Serialbox), and composite coordinate variables are needed to
  disambiguate savepoints sharing a name.

## Decision

1. **Backend:** NCZarr-unified through `netcdf-fortran`. preserf's Fortran
   helper module calls `nf90_*` only. The physical format is selected by the
   file URL / mode string passed at `ppser_initialize` time:
   - `<dir>/<prefix>.nc` → NetCDF4 (HDF5).
   - `file://<dir>/<prefix>.zarr#mode=nczarr,zarr2` → Zarr V2 store.
     When the netcdf-c Zarr V3 PR is merged, the same code path will gain
     `#mode=nczarr,zarr3` with no Fortran changes.

2. **Layout:** group-per-savepoint. The root group carries `global_meta_info`
   as typed attributes. A `/_fields` subgroup mirrors Serialbox's `field_map`
   with one dummy scalar variable per registered field (`NF90_INT`, value
   `0`, used only as an attribute carrier) whose attributes hold the field's
   type id, dims and halos. A `/savepoints` subgroup contains one ordered
   subgroup per savepoint (`sp_000000`, `sp_000001`, …) whose attributes hold
   the savepoint's name and metainfo, and which contains one variable per
   field actually written at that savepoint.

Option 1 collapses the "two formats" requirement into a single parameterised
Fortran implementation, because NCZarr exposes Zarr V2 stores through the
standard netCDF API. Option 2 is the only layout that preserves Serialbox's
heterogeneous-fields-per-savepoint semantics without introducing fill values
or padding.

The concrete mapping (attribute names, dtype encoding, ordering rules) is
documented separately in
[`development/references/storage_mapping.md`](../../development/references/storage_mapping.md).

## Consequences

- A single `m_preserf` / `utils_preserf` Fortran module covers both target
  formats; the user-visible choice is one URL string.
- Serialbox's typed metainfo (including arrays) maps 1:1 onto netCDF
  attributes, which are natively vector-valued in both backends.
- The layout is openable by xarray (`xr.open_datatree`) and zarr-python
  (`zarr.open_group`) without any preserf code. Stores written through
  NCZarr are _not_ consolidated by default — readers that prefer
  `zarr.open_consolidated` need to either consolidate the metadata
  themselves (`zarr.consolidate_metadata(...)`) or have preserf opt in to
  writing `.zmetadata` at close time (tracked as future work).
- Zarr V3 migration is a future configuration change, not a code change.
- Serialbox's per-field offset table and checksum machinery is not
  reproduced — integrity is delegated to the underlying format (HDF5 / Zarr
  per-chunk hashing if enabled).
- Pure append workloads (Serialbox `MODE_APPEND`) carry a modest rewrite
  cost under NCZarr V2 compared to Serialbox's offset-append binary archive.
  Acceptable for pp_ser-driven coarse-grained workflows.
- preserf depends on the `netcdf-c` build having NCZarr enabled (default in
  recent releases) — a hard build requirement for the Fortran helper layer.

The mapping is validated by `tests/unit_tests/test_storage_round_trip.py`,
which builds an in-memory `SerialboxDump` covering all six metainfo
`TypeID`s in scalar and array form, repeated savepoint names, heterogeneous
fields-per-savepoint, and multi-dimensional field arrays, then round-trips
it through both backends bit-identical.

Revisit when: the netcdf-c Zarr V3 PR is merged, or if a downstream user
requests the time-series-per-field layout as a secondary output mode.

## References

The `src/serialbox/...` and `src/serialbox-fortran/...` paths below refer
to files in the upstream [GridTools/serialbox](https://github.com/GridTools/serialbox)
repository, not to this repo. Line ranges were taken against `master` at
the time the ADR was drafted and may drift; the file and function names
are the stable anchors.

- Serialbox JSON metadata schema: `src/serialbox/core/SerializerImpl.cpp`
  (≈L39-70), `src/serialbox/core/SavepointVectorSerializer.cpp` (≈L15-32),
  `src/serialbox/core/FieldMetainfoImplSerializer.cpp` (≈L15-19),
  `src/serialbox/core/SavepointImplSerializer.cpp` (≈L15-18).
- Serialbox metainfo type system: `src/serialbox/core/MetainfoValueImpl.h`
  (≈L141-157), `src/serialbox/core/Type.h` (≈L55-74).
- Serialbox binary archive layout:
  `src/serialbox/core/archive/BinaryArchive.cpp` (≈L171-325).
- Serialbox Fortran helper API used by the preprocessor:
  `src/serialbox-fortran/m_serialize.f90`,
  `src/serialbox-fortran/utils_ppser.f90`.
- Zarr V2 specification: <https://zarr-specs.readthedocs.io/en/latest/v2/v2.0.html>.
- NCZarr (Zarr support inside netcdf-c): <https://docs.unidata.ucar.edu/nug/current/nczarr_head.html>.
