# preserf Storage Mapping Reference

**Status**: Draft, accompanies ADR
[`docs/adr/0002-storage-model-mapping.md`](../adr/0002-storage-model-mapping.md).

This document specifies the concrete on-disk layout that `preserf` uses to
represent a Serialbox-equivalent dump. The same layout is produced for both
target formats:

- NetCDF4 (HDF5-backed): a single `.nc` file.
- Zarr V2 (via NCZarr): a `.zarr` directory store.

The Fortran helper modules in preserf write to either via the `netcdf-fortran`
`nf90_*` API; the physical format is selected by the URL / mode string at
initialisation time.

---

## 1. Source-of-truth schema

The mapping is derived from the Serialbox JSON producers listed below:

| Serialbox JSON node                       | C++ producer                                          |
| ----------------------------------------- | ----------------------------------------------------- |
| `serialbox_version`, `prefix`             | `SerializerImpl::toJSON` (`SerializerImpl.cpp:39-57`) |
| `global_meta_info`                        | `MetainfoMapImplSerializer.cpp`                       |
| `savepoint_vector.savepoints[]`           | `SavepointImplSerializer.cpp:15-18`                   |
| `savepoint_vector.fields_per_savepoint[]` | `SavepointVectorSerializer.cpp:15-32`                 |
| `field_map.<field>`                       | `FieldMetainfoImplSerializer.cpp:15-19`               |

The eight Serialbox `TypeID` values (`src/serialbox/core/Type.h:55-74`) are:

| TypeID | Meaning  | preserf netCDF type                           | Notes                             |
| ------ | -------- | --------------------------------------------- | --------------------------------- |
| 0      | Invalid  | —                                             | rejected at write time            |
| 1      | Boolean  | `NF90_BYTE`                                   | 0/1 encoding                      |
| 2      | Int32    | `NF90_INT`                                    |                                   |
| 3      | Int64    | `NF90_INT64`                                  |                                   |
| 4      | Float32  | `NF90_FLOAT`                                  |                                   |
| 5      | Float64  | `NF90_DOUBLE`                                 |                                   |
| 6      | String   | `NF90_CHAR` (scalar) / `NF90_STRING` (vector) | see note                          |
| array  | of above | vector attribute                              | netCDF attrs are natively vectors |

> **Note on String storage.** Scalar string metainfo lands on disk as
> `NC_CHAR` from both reference writers: Python's
> `netCDF4.Dataset.setncattr(key, str)` calls `nc_put_att_text` and
> produces `NC_CHAR`; the Fortran helper's
> `nf90_put_att(grpid, varid, key, character(*))` does the same. Array
> string metainfo is `NC_STRING` from the Python writer
> (`setncattr(key, list[str])`) — the Fortran helper doesn't support
> array string metainfo in v0.1.
>
> Readers MUST decode based on the `__preserf_type_id` shadow tag
> (TypeID 6 → string), not on the on-disk netCDF type. For
> **scalar** string-tagged attributes, readers MUST accept either
> `NC_CHAR` or `NC_STRING`. For **array** string-tagged attributes
> (TypeID = `0x10 | 6 = 22`), the on-disk encoding is always
> `NC_STRING` (a vector attribute) — `NC_CHAR` has no shape rule
> that round-trips a vector of strings, so writers MUST NOT use
> `NC_CHAR` for that case.

### 1.1 Axis ordering convention

The `dims[]` attribute on every `/_fields/<name>` registry entry, and the
order of dimensions on every per-savepoint field variable, are recorded in
**netCDF C-order** (slowest-varying axis first). This matches the natural
ordering for the netCDF-C, netCDF4-python and xarray ecosystems.

Serialbox's Fortran helper (`fs_register_field`) accepts sizes in the
Fortran column-major declaration order `(iSize, jSize, kSize, lSize)`.
The preserf Fortran helper transparently reverses this tuple when writing
the `dims` attribute and when declaring the data variable's dimensions,
so a rank-3 Fortran field declared as `(iSize=4, jSize=3, kSize=2)`
shows up on disk as `dims = [2, 3, 4]` and as a netCDF variable of C-shape
`(2, 3, 4)`. A Python reader sees `numpy[k_idx, j_idx, i_idx]`.

Halo attributes (§4) remain named by their Fortran direction (`i`, `j`,
`k`, `l`) regardless of the C-order axis layout — they describe the
physical halo, not the storage axis.

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
├── /_tracers                         (group; present only when a tracer is registered, §4a)
│   ├── <tracername>                  (dummy scalar variable per registered tracer;
│   │   │                              carries field schema + stype/tracer_index)
│   │   └── attributes: type_id, dims, halos, stype, tracer_index (§4a)
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

| Attribute name              | Type        | Value                                                |
| --------------------------- | ----------- | ---------------------------------------------------- |
| `_preserf_schema_version`   | `NF90_INT`  | `1` (this document's schema version)                 |
| `_preserf_serialbox_prefix` | `NF90_CHAR` | the `prefix` argument from `ppser_initialize`        |
| `_preserf_savepoint_count`  | `NF90_INT`  | number of savepoint subgroups under `/savepoints`    |
| `_preserf_writer`           | `NF90_CHAR` | `"preserf <version>"`                                |
| `_preserf_singlefile`       | `NF90_BYTE` | `!$SER INIT singlefile=` keyword (0/1); default `0`  |
| `_preserf_archive`          | `NF90_CHAR` | `!$SER INIT archive=` keyword; default `"Binary"`    |
| `_preserf_unique_id`        | `NF90_INT`  | `!$SER INIT unique_id=` keyword; default `0`         |
| `_preserf_option_verbosity` | `NF90_INT`  | `!$SER OPTION verbosity=` value; present only if set |

`_preserf_option_*` attributes record `!$SER OPTION` keys for round-trip
(§4b). Only `verbosity` is defined today; the namespace is reserved for
future option keys. Each is written with the value the directive supplied
(after the `on`/`off` → `1`/`0` mapping) and is absent when the option was
never set.

`_preserf_singlefile`, `_preserf_archive`, and `_preserf_unique_id` are
metadata-only on the preserf side: pp_ser passes
them through verbatim from `!$SER INIT`, so they are recorded for
round-trip fidelity but do not change preserf's runtime behaviour. Each
is written with its effective value — the supplied keyword, or the
Serialbox default when omitted — so readers always find a complete set.

Both reference writers (Python `netCDF4` and Fortran `netcdf-fortran`)
produce `NC_CHAR` for scalar string attributes (§1). For maximum
forward compatibility, readers SHOULD also accept `NC_STRING` on these
housekeeping attributes if a future writer chooses to emit it.

Reading code MUST ignore any `_preserf_*` attribute it does not recognise.

### 3.2 User metainfo (Serialbox `global_meta_info`)

Each key in Serialbox's `global_meta_info` becomes one root attribute with
the **same name** and a netCDF type chosen per §1. Array-valued metainfo is
stored as a vector attribute (netCDF attributes are vector-valued natively;
this carries through NCZarr V2 unchanged).

User metainfo keys are **rejected** at write time with a `ValueError` if they:

- start with the prefix `_preserf_` (collides with preserf housekeeping
  attributes — see §3.1, §5), or
- end with the suffix `__preserf_type_id` (collides with the per-attribute
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

| Attribute     | Type              | Req? | Source                                                                            |
| ------------- | ----------------- | ---- | --------------------------------------------------------------------------------- |
| `type_id`     | `NF90_INT`        | yes  | Serialbox TypeID (1..6) — see §1                                                  |
| `dims`        | vector `NF90_INT` | yes  | `dims[]` from `FieldMetainfoImpl`                                                 |
| `iminushalo`  | `NF90_INT`        | no   | halo metainfo emitted by pp_ser shortcuts                                         |
| `iplushalo`   | `NF90_INT`        | no   | "                                                                                 |
| `jminushalo`  | `NF90_INT`        | no   | "                                                                                 |
| `jplushalo`   | `NF90_INT`        | no   | "                                                                                 |
| `kminushalo`  | `NF90_INT`        | no   | "                                                                                 |
| `kplushalo`   | `NF90_INT`        | no   | "                                                                                 |
| `lminushalo`  | `NF90_INT`        | no   | "                                                                                 |
| `lplushalo`   | `NF90_INT`        | no   | "                                                                                 |
| user metainfo | typed             | no   | any extra `key=value` set via the field's metainfo map; same naming rules as §3.2 |

Halo attributes are **optional** — the schema does not assign any
default semantics to an absent halo. The two ends of the wire have
distinct, non-conflicting obligations:

- **Writers** SHOULD omit any halo attribute whose value is zero,
  purely as an on-disk-compactness convention: omitting zero-valued
  halos avoids cluttering `/_fields/<name>` with a row of "0" entries.
  The preserf Fortran helper's `put_halo_attr` follows this rule. A
  writer MAY emit zero halos explicitly if it wants the metadata to
  be unambiguous; this is conformant. The preserf Fortran helper
  emits each halo as an **unshadowed** plain `NF90_INT` attribute on
  the `/_fields/<name>` carrier — no `<name>__preserf_type_id` shadow
  tag, since the halo name already fixes the type. The Python
  reference writer in `tests/_support/storage.py` has no dedicated bare-halo
  writer path; if it ever needs to emit a halo it would go through
  the typed-metainfo channel (which also writes the shadow tag).
  Both the bare-integer and shadowed encodings are conformant
  on-disk forms.

  > **Reader-support note.** The v0.1 Python reference reader
  > (`read_dump` in `tests/_support/storage.py`) decodes _only_ shadowed
  > metainfo: `_read_metainfo_attrs` skips any attribute that has no
  > `<name>__preserf_type_id` sibling. Unshadowed halo attributes
  > therefore do **not** surface in the `FieldMetainfo` objects
  > `read_dump` returns — they are reachable only through raw netCDF
  > access. The cross-language test (`tests/integration_tests/test_fortran_wire_compat.py`)
  > accordingly asserts the Fortran-written halos directly via
  > `netCDF4.Variable.getncattr`, not through `read_dump`. So in v0.1
  > "halo round-trip" means the attributes survive on disk, not that
  > they appear in `read_dump`'s decoded output. Teaching the
  > reference reader to surface bare halo attributes (and adding a
  > matching bare-halo writer path on the Python side) is tracked as
  > a follow-up.
- **Readers** MUST treat any missing halo attribute as **absent**
  (= "this writer did not record information about this halo")
  rather than as an implicit `0`. Whether and how an absent halo
  translates into runtime behaviour (e.g. a zero-halo assumption
  inside the Fortran caller) is the consumer's policy, not part of
  this storage schema.

These two clauses do not contradict each other: writer compactness
("zero omitted") and reader semantics ("absent ≠ 0 implicitly") are
independent. A reader that needs to distinguish "writer recorded
zero" from "writer didn't record" must inspect the attribute's
presence and not assume a default.

> The `bytes_per_element` attribute that the original `fs_register_field`
> can carry is intentionally **not** part of the v1 schema yet — it would
> need a corresponding field on the in-memory `FieldMetainfo` to round-trip.
> Will be added when the Fortran helper module starts emitting it.

The dimension names of actual field-data variables (§6) are **derived** from
this metadata at write time: `<fieldname>_dim0`, `<fieldname>_dim1`, …,
unless a more specific naming convention is configured (future work — see
§9).

---

## 4a. `/_tracers/<tracername>`: registered tracer metadata

Tracers (`!$SER REGISTERTRACERS`, `!$SER TRACER`) are ordinary fields that
additionally carry a storage type and a 1-based index into an ordered tracer
set. `fs_RegisterAllTracers` writes one **scalar carrier variable** (rank-0,
`NF90_INT`, value `0`) per registered tracer under `/_tracers`, exactly as
`/_fields` carriers (§4). The `/_tracers` group is created **lazily** — only
when at least one tracer is registered — so a field-only store omits it
entirely; readers MUST tolerate its absence (as they must for stores written
before ADR 0003). See ADR
[0003](../adr/0003-tracer-storage.md) for the rationale and for the
**built-in tracer registry** that supplies tracer data (the directive surface
itself carries no data array).

Attributes:

| Attribute                  | Type              | Req? | Source                                                      |
| -------------------------- | ----------------- | ---- | ----------------------------------------------------------- |
| `type_id`                  | `NF90_INT`        | yes  | Serialbox TypeID (1..6) — see §1                            |
| `dims`                     | vector `NF90_INT` | yes  | C-order shape — see §1.1                                    |
| `*minushalo` / `*plushalo` | `NF90_INT`        | no   | optional halos, via `put_halo_attr` (zero omitted, §4)      |
| `stype`                    | `NF90_CHAR`       | yes  | one of `tens` / `bd` / `surf` / `sedimvel`, or empty string |
| `tracer_index`             | `NF90_INT`        | yes  | 1-based position in registration order                      |

Tracer **data** written at a savepoint lands as an ordinary savepoint
variable (§6) **named by the tracer name alone** (e.g. `q_v`) — identical in
shape and dtype to a `!$SER DATA` field, so readers need no new data-read
path, only `/_tracers` descriptor discovery.

When the `!$SER TRACER` write carried a `@timelevel`, the variable gains an
optional `timelevel` (`NF90_INT`) attribute recording the integer level the
snapshot came from. (At runtime the directive's `@nnow` is emitted as the
unquoted Fortran expression `timelevel=nnow`, so it reaches the helper as an
integer index, not a string — the literal `@`/`nnow` never reach disk.) The
attribute is absent when no timelevel was given; readers MUST tolerate its
absence.

Because the variable name is the tracer name alone, there is **one snapshot
per `(savepoint, tracer)`: last write wins**. Writing the same tracer at two
timelevels in one savepoint (`!$SER TRACER q_v@nnow q_v@nnew`) overwrites —
only the last snapshot and its `timelevel` attribute survive. This is an
accepted v1.0 limitation; preserving multi-timelevel fan-out as distinct data
is a future additive change (ADR [0003](../adr/0003-tracer-storage.md) §2 and
Alternatives).

---

## 4b. OPTION values (`_preserf_option_*`)

`!$SER OPTION` keys land as reserved root attributes in the `_preserf_option_*`
namespace (§3.1). v1 defines a single key:

| Attribute                   | Type       | Value                                               |
| --------------------------- | ---------- | --------------------------------------------------- |
| `_preserf_option_verbosity` | `NF90_INT` | `fs_Option(verbosity=)`; after `on`/`off` → `1`/`0` |

Only `verbosity` is supported today; the preprocessor rejects other OPTION
keys (ADR [0003](../adr/0003-tracer-storage.md) §4). The attribute is absent
when the option was never set; readers MUST tolerate its absence and MUST
ignore unrecognised `_preserf_option_*` keys.

---

## 5. `/savepoints/sp_NNNNNN`: a single savepoint

- The subgroup name is `sp_` followed by a zero-padded **6-digit** index
  (the savepoint's position in `savepoint_vector.savepoints[]`). The width
  is fixed at 6 digits, which caps a single preserf store at **1,000,000
  savepoints** and lets readers rely on lexical group-name ordering matching
  numerical ordering. Writes that would exceed this cap must fail; widening
  the field is a forwards-incompatible schema change (would require bumping
  `_preserf_schema_version`).
- The savepoint's **Serialbox `name`** is stored as the `name` attribute
  of the group (`NF90_CHAR`; both reference writers produce `NC_CHAR`
  for scalar strings — see §1). It is _not_ used as the group
  identifier because Serialbox permits multiple savepoints to share a
  `name` (they are disambiguated by metainfo).
- Each Serialbox metainfo key on the savepoint becomes one group attribute,
  typed per §1. The reserved-namespace rule from §3.2 applies.

Reserved housekeeping attributes on a savepoint group:

| Attribute                  | Type       | Value                                         |
| -------------------------- | ---------- | --------------------------------------------- |
| `_preserf_savepoint_index` | `NF90_INT` | the integer N matching `sp_NNNNNN`            |
| `_preserf_field_ids`       | (see §7)   | optional Serialbox `fieldID` round-trip table |

**Read-mode resolution (as of Slice A-1).** A read run resolves savepoints
**positionally**: the Nth `!$SER SAVEPOINT` directive resolves `sp_00000(N-1)`
and cross-checks the runtime name against the group's `name` attribute,
aborting on a mismatch. Reads therefore assume the generated source replays
savepoints in the same order they were written; out-of-order or
metainfo-keyed savepoint lookup (which Serialbox permits) is not yet
supported and a reordered run fails loudly on the name check rather than
returning wrong data.

---

## 6. Per-savepoint field-data variables

For each field written at a savepoint (via `!$SER DATA`, `!$SER ACCDATA`,
`!$SER DATA_KBUFF`), preserf creates one variable inside the savepoint's
group:

- **Name** = the Serialbox `<fieldname>` (the key passed to `fs_write_field`).
- **Type** = derived from `/_fields/<fieldname>:type_id`.
- **Dimensions** = looked up by name in the savepoint group; if absent,
  preserf creates them lazily using the sizes from `/_fields/<fieldname>:dims`
  and the naming convention `<fieldname>_dim0`, `<fieldname>_dim1`, … . The
  same physical dimension is _not_ shared across fields by default
  (each field owns its own dimensions) — this matches Serialbox's per-field
  metadata model where dims are field-private.
- **Chunking** (NCZarr / NetCDF4): **implementation-defined** unless the
  writer explicitly opts in. The reference implementation does not set
  `chunksizes`, so NetCDF4/HDF5 typically produces contiguous storage and
  NCZarr falls back to its own default chunk shape. A future option (§9)
  will expose an explicit chunking knob; until then, no chunking guarantee
  is part of the schema.

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
    attrs: type_id=5, dims=[ke,je,ie],   ! C-order, per §1.1
           iminushalo=nboundlines, iplushalo=nboundlines,
           jminushalo=nboundlines, jplushalo=nboundlines
                                          ! kminushalo / kplushalo omitted
                                          ! (zero — see §4 writer convention)
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

- **Shared dimensions across fields.** Should fields with matching shape
  share a single set of named dimensions at the root (more idiomatic for
  xarray)? Default today is per-field private dimensions to match the
  Serialbox metadata model exactly. Revisit when the helper module is in
  place and we can benchmark both.
- **Chunking and compression.** Both are currently implementation-defined
  (no `chunksizes` set, no compression filter). Both are tunable via
  netCDF-Fortran APIs and should be exposed through `!$SER OPTION` keys;
  defer naming to a follow-up ADR.
- **Per-rank stores under MPI.** `ppser_initialize`'s `mpi_rank` argument
  currently maps to a `_rank<n>` suffix on the store name. Parallel HDF5 /
  parallel NCZarr is a future option.
- **Zarr V3.** Layout in this document is wire-compatible with Zarr V3 —
  the only changes will be in the mode string passed to `nf90_create`.
- **String data fields.** Serialbox's `TypeID::String` for _data_ (not
  metainfo) is **not yet supported** in this schema version: the reference
  implementation's `numpy_dtype_for` rejects it and there is no
  `NF90_STRING` write path for field variables. String metainfo (scalar
  and array) is fully supported. String data-field support is deferred;
  when added it will land as `NF90_STRING` variables under the same
  group-per-savepoint layout, with no schema-version bump expected.
