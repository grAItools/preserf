# preserf Storage Mapping Reference

**Status**: Draft, accompanies ADR
`development/decisions/0001-storage-model-mapping.md`.

This document specifies the concrete on-disk layout that `preserf` uses to
represent a Serialbox-equivalent dump. The same layout is produced for both
target formats:

* NetCDF4 (HDF5-backed): a single `.nc` file.
* Zarr V2 (via NCZarr): a `.zarr` directory store.

The Fortran helper modules in preserf write to either via the `netcdf-fortran`
`nf90_*` API; the physical format is selected by the URL / mode string at
initialisation time.

---

## 1. Source-of-truth schema

The mapping is derived from the four Serialbox JSON producers:

| Serialbox JSON node                       | C++ producer                                          |
|-------------------------------------------|-------------------------------------------------------|
| `serialbox_version`, `prefix`             | `SerializerImpl::toJSON` (`SerializerImpl.cpp:39-57`) |
| `global_meta_info`                        | `MetainfoMapImplSerializer.cpp`                       |
| `savepoint_vector.savepoints[]`           | `SavepointImplSerializer.cpp:15-18`                   |
| `savepoint_vector.fields_per_savepoint[]` | `SavepointVectorSerializer.cpp:15-32`                 |
| `field_map.<field>`                       | `FieldMetainfoImplSerializer.cpp:15-19`               |

The eight Serialbox `TypeID` values (`src/serialbox/core/Type.h:55-74`) are:

| TypeID | Meaning  | preserf netCDF type | Notes                          |
|--------|----------|---------------------|--------------------------------|
| 0      | Invalid  | —                   | rejected at write time         |
| 1      | Boolean  | `NF90_BYTE`         | 0/1 encoding                   |
| 2      | Int32    | `NF90_INT`          |                                |
| 3      | Int64    | `NF90_INT64`        |                                |
| 4      | Float32  | `NF90_FLOAT`        |                                |
| 5      | Float64  | `NF90_DOUBLE`       |                                |
| 6      | String   | `NF90_STRING`       | variable-length string         |
| array  | of above | vector attribute    | netCDF attrs are natively vectors |

---

## 2. Top-level layout

```
<store>                               (root of the netCDF file or NCZarr store)
├── (root attributes — see §3)
├── /_fields                          (group; mirrors Serialbox field_map)
│   ├── <fieldname>                   (dummy scalar variable per registered field;
│   │   │                              carries field schema as attributes, value 0)
│   │   └── attributes: type_id, dims, halos, user metainfo (§4)
│   └── …
└── /savepoints                       (group; ordered savepoint vector)
    ├── /sp_000000                    (one subgroup per savepoint, zero-padded index)
    │   ├── attributes: name, metainfo (§5)
    │   └── <fieldname> variables     (one per field actually written at this savepoint, §6)
    ├── /sp_000001
    └── …
```

The store-as-a-whole carries identifying attributes on the root group.

---

## 3. Root group: `global_meta_info`

Two kinds of root attributes are written:

### 3.1 preserf housekeeping (reserved namespace `_preserf_*`)

| Attribute name             | Type       | Value                                            |
|----------------------------|------------|--------------------------------------------------|
| `_preserf_schema_version`  | `NF90_INT` | `1` (this document's schema version)             |
| `_preserf_serialbox_prefix`| `NF90_STRING` | the `prefix` argument from `ppser_initialize` |
| `_preserf_savepoint_count` | `NF90_INT` | number of savepoint subgroups under `/savepoints` |
| `_preserf_writer`          | `NF90_STRING` | `"preserf <version>"`                          |

Reading code MUST ignore any `_preserf_*` attribute it does not recognise.

### 3.2 User metainfo (Serialbox `global_meta_info`)

Each key in Serialbox's `global_meta_info` becomes one root attribute with
the **same name** and a netCDF type chosen per §1. Array-valued metainfo is
stored as a vector attribute (netCDF attributes are vector-valued natively;
this carries through NCZarr V2 unchanged).

User metainfo keys are **rejected** at write time with a `ValueError` if they:

* start with the prefix `_preserf_` (collides with preserf housekeeping
  attributes — see §3.1, §5), or
* end with the suffix `__preserf_type_id` (collides with the per-attribute
  shadow tag preserf writes alongside every typed metainfo entry to preserve
  the original Serialbox `TypeID` — see §3.3).

Callers must rename the offending key before serialising. (An earlier draft
of this document proposed an automatic `__`-prefix escape; that was dropped
because it complicates the read path and the directives never produce
colliding keys in practice.)

### 3.3 Type-id shadow tags

Every typed metainfo attribute `<key>` is accompanied by a sibling attribute
`<key>__preserf_type_id` (`NF90_INT`) holding the original Serialbox
`TypeID` integer. This is what lets the reader distinguish e.g. `Int32`
from `Int64` even after the value has been round-tripped through netCDF /
Zarr type promotion. Readers MUST skip any attribute whose name ends in
`__preserf_type_id` when collecting user metainfo.

---

## 4. `/_fields/<fieldname>`: registered field metadata

Each field registered via `!$SER REGISTER` (`fs_register_field`) produces a
**scalar variable** (rank-0, dtype `NF90_INT`, value `0`) named after the
field, under `/_fields`. The variable exists only to carry attributes; its
data is never read.

Attributes:

| Attribute        | Type              | Req? | Source                                           |
|------------------|-------------------|------|--------------------------------------------------|
| `type_id`        | `NF90_INT`        | yes  | Serialbox TypeID (1..6) — see §1                 |
| `dims`           | vector `NF90_INT` | yes  | `dims[]` from `FieldMetainfoImpl`                |
| `iminushalo`     | `NF90_INT`        | no   | halo metainfo emitted by pp_ser shortcuts        |
| `iplushalo`      | `NF90_INT`        | no   | "                                                |
| `jminushalo`     | `NF90_INT`        | no   | "                                                |
| `jplushalo`      | `NF90_INT`        | no   | "                                                |
| `kminushalo`     | `NF90_INT`        | no   | "                                                |
| `kplushalo`      | `NF90_INT`        | no   | "                                                |
| `lminushalo`     | `NF90_INT`        | no   | "                                                |
| `lplushalo`      | `NF90_INT`        | no   | "                                                |
| user metainfo    | typed             | no   | any extra `key=value` set via the field's metainfo map; same naming rules as §3.2 |

Halo attributes are **optional** and may be partially present: a writer
emits only the halos that `pp_ser` (or the caller) actually provided.
Readers MUST treat any missing halo attribute as **absent** rather than
implying a default of `0`. Whether and how absent halos translate into
runtime behaviour (e.g. zero-halo assumption inside the Fortran helper) is
defined by the consumer, not by this storage schema.

> The `bytes_per_element` attribute that the original `fs_register_field`
> can carry is intentionally **not** part of the v1 schema yet — it would
> need a corresponding field on the in-memory `FieldMetainfo` to round-trip.
> Will be added when the Fortran helper module starts emitting it.

The dimension names of actual field-data variables (§6) are **derived** from
this metadata at write time: `<fieldname>_dim0`, `<fieldname>_dim1`, …,
unless a more specific naming convention is configured (future work — see
§9).

---

## 5. `/savepoints/sp_NNNNNN`: a single savepoint

* The subgroup name is `sp_` followed by a zero-padded **6-digit** index
  (the savepoint's position in `savepoint_vector.savepoints[]`). The width
  is fixed at 6 digits, which caps a single preserf store at **1,000,000
  savepoints** and lets readers rely on lexical group-name ordering matching
  numerical ordering. Writes that would exceed this cap must fail; widening
  the field is a forwards-incompatible schema change (would require bumping
  `_preserf_schema_version`).
* The savepoint's **Serialbox `name`** is stored as the `name` attribute of
  the group (`NF90_STRING`). It is *not* used as the group identifier
  because Serialbox permits multiple savepoints to share a `name` (they are
  disambiguated by metainfo).
* Each Serialbox metainfo key on the savepoint becomes one group attribute,
  typed per §1. The reserved-namespace rule from §3.2 applies.

Reserved housekeeping attributes on a savepoint group:

| Attribute                   | Type         | Value                                         |
|-----------------------------|--------------|-----------------------------------------------|
| `_preserf_savepoint_index`  | `NF90_INT`   | the integer N matching `sp_NNNNNN`            |
| `_preserf_field_ids`        | (see §7)     | optional Serialbox `fieldID` round-trip table |

---

## 6. Per-savepoint field-data variables

For each field written at a savepoint (via `!$SER DATA`, `!$SER ACCDATA`,
`!$SER DATA_KBUFF`), preserf creates one variable inside the savepoint's
group:

* **Name** = the Serialbox `<fieldname>` (the key passed to `fs_write_field`).
* **Type** = derived from `/_fields/<fieldname>:type_id`.
* **Dimensions** = looked up by name in the savepoint group; if absent,
  preserf creates them lazily using the sizes from `/_fields/<fieldname>:dims`
  and the naming convention `<fieldname>_dim0`, `<fieldname>_dim1`, … . The
  same physical dimension is *not* shared across fields by default
  (each field owns its own dimensions) — this matches Serialbox's per-field
  metadata model where dims are field-private.
* **Chunking** (NCZarr / NetCDF4): the default is one chunk = one whole
  field write. Configurable via a future option (§9).

The k-buffer mode (`!$SER DATA_KBUFF`) writes the same variable shape but
fills it in vertical slices keyed by the `k` / `k_size` arguments; the
on-disk variable looks identical to a `DATA` write of the same field.

---

## 7. Reproducing Serialbox `fields_per_savepoint[i][field] = fieldID`

Serialbox's binary archive stores all snapshots of a field in one `.dat`
file and keys them by an integer `fieldID` — the per-field write index.
preserf does **not** need this index to read its own data back: the
savepoint group's contents already say which fields exist at that
savepoint. But it is preserved for **round-trip** with Serialbox archives:

If `_preserf_field_ids` is present on a savepoint group, its value is a
length-2N vector of strings `[fieldname0, id0, fieldname1, id1, …]` where
`idN` is the decimal string form of Serialbox's `fieldID`. Writers that
have no Serialbox provenance MUST omit this attribute; readers MUST tolerate
its absence.

A future tool `preserf import-serialbox` will populate this attribute when
translating a real Serialbox dump.

---

## 8. Worked example

Input directives (Fortran fragment):

```fortran
!$SER INIT directory='./out' prefix='foo'
!$SER METAINFO author='alice'
!$SER REGISTER u real IJK
!$SER SAVEPOINT step1 ntstep=1
!$SER DATA u=u(:,:,:,nnow)
!$SER SAVEPOINT step1 ntstep=2
!$SER DATA u=u(:,:,:,nnow)
!$SER CLEANUP
```

Resulting NetCDF4 / NCZarr store:

```
/                                       attrs: _preserf_schema_version=1,
                                                _preserf_serialbox_prefix="foo",
                                                _preserf_savepoint_count=2,
                                                author="alice"
/_fields/
  u                                     scalar NF90_INT, value 0
    attrs: type_id=5, dims=[ie,je,ke],
           iminushalo=nboundlines, iplushalo=nboundlines,
           jminushalo=nboundlines, jplushalo=nboundlines,
           kminushalo=0, kplushalo=0
/savepoints/
  sp_000000/                            attrs: name="step1", ntstep=1,
                                               _preserf_savepoint_index=0
    u                                   NF90_DOUBLE, dims [u_dim0, u_dim1, u_dim2]
  sp_000001/                            attrs: name="step1", ntstep=2,
                                               _preserf_savepoint_index=1
    u                                   NF90_DOUBLE, dims [u_dim0, u_dim1, u_dim2]
```

---

## 9. Open / deferred questions

* **Shared dimensions across fields.** Should fields with matching shape
  share a single set of named dimensions at the root (more idiomatic for
  xarray)? Default today is per-field private dimensions to match the
  Serialbox metadata model exactly. Revisit when the helper module is in
  place and we can benchmark both.
* **Chunking and compression.** Currently one chunk per field write,
  uncompressed. Both are tunable via netCDF-Fortran APIs and should be
  exposed through `!$SER OPTION` keys; defer naming to a follow-up ADR.
* **Per-rank stores under MPI.** `ppser_initialize`'s `mpi_rank` argument
  currently maps to a `_rank<n>` suffix on the store name. Parallel HDF5 /
  parallel NCZarr is a future option.
* **Zarr V3.** Layout in this document is wire-compatible with Zarr V3 —
  the only changes will be in the mode string passed to `nf90_create`.
* **String data fields.** Serialbox's `TypeID::String` for *data* (not
  metainfo) is **not yet supported** in this schema version: the reference
  implementation's `numpy_dtype_for` rejects it and there is no
  `NF90_STRING` write path for field variables. String metainfo (scalar
  and array) is fully supported. String data-field support is deferred;
  when added it will land as `NF90_STRING` variables under the same
  group-per-savepoint layout, with no schema-version bump expected.
