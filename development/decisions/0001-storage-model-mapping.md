---
status: proposed
date: 2026-05-12
decision-makers: preserf maintainers
consulted: Serialbox documentation, Zarr V2 specification, NetCDF / NCZarr documentation
informed: preserf users (Fortran application developers)
---

# Storage model: map Serialbox data model onto NetCDF4 and Zarr V2 via NCZarr

## Context and Problem Statement

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

How should the Serialbox data model be laid out in NetCDF4 / Zarr V2 so that:

1. Every Serialbox concept (global metainfo, savepoint vector, field map,
   per-savepoint field snapshots, typed scalar / array metainfo) has a
   well-defined, lossless landing spot;
2. Both formats are produced by the **same** Fortran helper-module source
   code, so preserf does not need a second backend implementation;
3. The on-disk artifacts are idiomatic enough to be opened by xarray /
   netCDF4-python / zarr-python without preserf-specific tooling.

## Decision Drivers

* **Fidelity** to the Serialbox data model — no lossy coercion. Heterogeneous
  savepoints (different fields at different savepoints, repeated savepoint
  names distinguished only by metainfo) must round-trip.
* **Single Fortran codebase**: avoid maintaining one helper module per
  physical format.
* **Standard tooling reachability**: outputs must be openable by ecosystem
  tools (xarray, zarr-python, ncdump) without custom readers.
* **Forward path to Zarr V3** without rewriting the Fortran layer.
* **Type preservation**: Serialbox metainfo supports bool / i32 / i64 /
  f32 / f64 / string and arrays of each — all of these must round-trip with
  their type.

## Considered Options

* **NCZarr (Zarr V2 backed) + NetCDF4, unified through `netcdf-fortran`**
* **Two separate backends**: native HDF5 calls for NetCDF4, direct Zarr
  writes (e.g. via a C library) for Zarr V2.
* **Time-series-per-field** layout: one variable per registered field along
  an unlimited `savepoint` dimension, with auxiliary coordinate variables for
  savepoint metainfo.
* **Group-per-savepoint** layout: one subgroup per savepoint, with one
  variable per field present at that savepoint.

## Decision Outcome

Chosen options:

1. **Backend**: NCZarr-unified through `netcdf-fortran`. preserf's Fortran
   helper module calls `nf90_*` only. The physical format is selected by the
   file URL / mode string passed at `ppser_initialize` time:
   * `<dir>/<prefix>.nc` → NetCDF4 (HDF5).
   * `file://<dir>/<prefix>.zarr#mode=nczarr,zarr2` → Zarr V2 store.
   When the netcdf-c Zarr V3 PR is merged, the same code path will gain
   `#mode=nczarr,zarr3` with no Fortran changes.

2. **Layout**: **Group-per-savepoint**. The root group carries `global_meta_info`
   as typed attributes. A `/_fields` subgroup mirrors Serialbox's `field_map`
   with one dummy scalar variable per registered field (`NF90_INT`, value `0`,
   used only as an attribute carrier), whose attributes
   hold the field's type id, dims and halos. A `/savepoints` subgroup contains
   one ordered subgroup per savepoint (`sp_000000`, `sp_000001`, …) whose
   attributes hold the savepoint's name and metainfo, and which contains one
   variable per field actually written at that savepoint.

Rationale: option (1) collapses the "two formats" requirement into a single
parameterised Fortran implementation, because NCZarr exposes Zarr V2 stores
through the standard netCDF API; option (2) is the only layout that preserves
Serialbox's heterogeneous-fields-per-savepoint semantics without introducing
fill values or padding.

The concrete mapping (attribute names, dtype encoding, ordering rules) is
documented separately in `development/references/storage_mapping.md`.

### Consequences

* Good, because a single `m_preserf` / `utils_preserf` Fortran module covers
  both target formats; the user-visible choice is one URL string.
* Good, because Serialbox's typed metainfo (including arrays) maps 1:1 onto
  netCDF attributes, which are natively vector-valued in both backends.
* Good, because the layout is openable by xarray (`xr.open_datatree`) and
  zarr-python (`zarr.open_consolidated`) without any preserf code.
* Good, because the Zarr V3 migration is a future configuration change, not
  a code change.
* Neutral, because Serialbox's per-field offset table and checksum machinery
  is not reproduced — integrity is delegated to the underlying format
  (HDF5 / Zarr per-chunk hashing if enabled).
* Bad, because pure append workloads (Serialbox `MODE_APPEND`) carry a
  modest rewrite cost under NCZarr V2 compared to Serialbox's offset-append
  binary archive. Acceptable for pp_ser-driven coarse-grained workflows.
* Bad, because we depend on the `netcdf-c` build having NCZarr enabled
  (default in recent releases) — this is now a hard build requirement for
  the Fortran helper layer.

### Confirmation

The mapping is validated by a round-trip test (`tests/test_round_trip.py`) that:

1. Builds an in-memory `SerialboxDump` covering the parts of the Serialbox
   data model relevant to v1 of the mapping: all six metainfo `TypeID`s in
   scalar and array form, repeated savepoint names distinguished by metainfo,
   heterogeneous fields-per-savepoint, and multi-dimensional field arrays;
2. Translates the dump into a preserf NetCDF4 store and a preserf NCZarr-V2
   store following this ADR's layout;
3. Re-reads both stores and reconstructs the dump bit-identical to the
   original — including the `TypeID` integers (which preserf preserves
   verbatim via the `__preserf_type_id` shadow attribute).

A separate `test_serialbox_disk_round_trip` exercises the in-memory dump
through `SerialboxDump.write` / `SerialboxDump.read` on the disk format
described by `BinaryArchive.cpp`, giving an isolated sanity check on the
fixture builder before the preserf storage layer is involved.

Validation against a real Serialbox dump (produced by an actual Serialbox
run rather than by `SerialboxDump.write`) and a Fortran-side smoke test
against the new helper module are tracked as follow-ups and will be added
once the `m_preserf` / `utils_preserf` modules land.

## Pros and Cons of the Options

### NCZarr-unified through `netcdf-fortran`

* Good, because the Fortran helper module is implemented once.
* Good, because both formats receive the same fixes and feature work.
* Good, because the upcoming Zarr V3 NCZarr support is a free upgrade.
* Neutral, because the URL / mode string vocabulary is a netcdf-c concept
  that preserf users have to learn (small surface).
* Bad, because preserf inherits whatever NCZarr V2 limitations exist in the
  installed netcdf-c version.

### Two separate backends (HDF5 + direct Zarr)

* Good, because each backend can be tuned to its native format's idioms.
* Bad, because two Fortran implementations to maintain and test.
* Bad, because direct Zarr writes from Fortran require a separate C/Fortran
  shim — the very thing NCZarr already provides.
* Bad, because behavioural drift between backends becomes likely.

### Group-per-savepoint layout

* Good, because heterogeneous fields-per-savepoint is the natural shape — no
  fill values, no padding, no fictitious dimensions.
* Good, because savepoint metainfo lives exactly where it semantically
  belongs (on the savepoint group).
* Good, because field-level static metadata (type id, dims, halos) is
  centralised in `/_fields` and not duplicated on every snapshot.
* Neutral, because xarray prefers time-series layouts; opening with
  `xr.open_datatree` works but per-savepoint analysis takes one extra
  indexing step.
* Bad, because writing many savepoints produces many small groups — fine for
  HDF5 and Zarr, but visually noisier than a flat time-series.

### Time-series-per-field layout

* Good, because the result looks like a conventional netCDF / Zarr dataset
  with a `savepoint` dimension; trivial to load into xarray.
* Bad, because it forces every field to be present at every savepoint
  (introducing fill values for missing fields) — a *semantic* change from
  Serialbox.
* Bad, because savepoints sharing a name but differing in metainfo must be
  reconciled via composite coordinate variables, complicating the schema.
* Bad, because k-buffer writes (`DATA_KBUFF`) interact awkwardly with an
  unlimited leading dimension.

## More Information

* Serialbox JSON metadata schema: `src/serialbox/core/SerializerImpl.cpp:39-70`,
  `src/serialbox/core/SavepointVectorSerializer.cpp:15-32`,
  `src/serialbox/core/FieldMetainfoImplSerializer.cpp:15-19`,
  `src/serialbox/core/SavepointImplSerializer.cpp:15-18`.
* Serialbox metainfo type system: `src/serialbox/core/MetainfoValueImpl.h:141-157`,
  `src/serialbox/core/Type.h:55-74`.
* Serialbox binary archive layout: `src/serialbox/core/archive/BinaryArchive.cpp:171-325`.
* Serialbox Fortran helper API used by the preprocessor:
  `src/serialbox-fortran/m_serialize.f90`, `src/serialbox-fortran/utils_ppser.f90`.
* Zarr V2 specification: <https://zarr-specs.readthedocs.io/en/latest/v2/v2.0.html>.
* NCZarr (Zarr support inside netcdf-c): <https://docs.unidata.ucar.edu/nug/current/nczarr_head.html>.
* Concrete attribute / group naming conventions:
  `development/references/storage_mapping.md`.

Revisit when: the netcdf-c Zarr V3 PR is merged, or if a downstream user
requests the time-series-per-field layout as a secondary output mode.
