# 3. Tracer descriptor storage, the tracer-registry binding, k-buffer flush, and the OPTION surface

## Status

Accepted

## Context

Slice C (`specs/2026-05-fortran-tracers-kbuff-option/`) implements the four
directives that the Python preprocessor already expands but the v0.1 Fortran
helper cannot link against:

- `!$SER REGISTERTRACERS` → `call fs_RegisterAllTracers()`
- `!$SER TRACER` → `ppser_write_tracer_by_name` / `_by_idx` / `_all`
- `!$SER DATA_KBUFF` → `fs_write_kbuff(..., k=, k_size=, mode=)`
- `!$SER OPTION` → `fs_Option(<key>=<value>, …)`

Before that code lands, four storage / API questions need a ratified answer
so the implementation PR is a mechanical realisation rather than a venue for
relitigating layout. This ADR settles them. It builds on ADR
[0002](0002-storage-model-mapping.md) (group-per-savepoint layout, one
parameterised Fortran helper writing NetCDF4 or NCZarr through `nf90_*`) and
the concrete mapping in
[`docs/references/storage_mapping.md`](../references/storage_mapping.md).

The decisive constraint comes from the directive grammar
(`docs/references/directives_specification.md` §3.11, §3.14). pp_ser's tracer
calls carry an **identifier** (name, index, or `%all`), an **stype**
(`tens`/`bd`/`surf`/`sedimvel`, possibly empty), and an optional
**timelevel** — but **no data array and no dimensions**. In Serialbox the
tracer writers resolve the actual array from the host model's tracer module
(COSMO `src_tracer`). preserf has no host model, so it must define where
tracer data comes from before it can serialise it.

### What a tracer is, concretely

A tracer is an ordinary field (a typed, dimensioned array) that additionally
carries a storage type (`stype`) and is addressable both by name and by a
1-based index into an ordered tracer set. `fs_RegisterAllTracers()` takes no
arguments: it is a bulk "register everything the model knows about" hook.

## Decision

### 1. Tracer descriptors live under `/_tracers`, mirroring `/_fields`

`fs_RegisterAllTracers()` writes one scalar `NF90_INT` carrier variable
(value `0`) per tracer under a new top-level group `/_tracers`, exactly as
`fs_register_field` does under `/_fields` (`src/preserf-fortran/m_preserf.F90`
`fs_register_field`). Each carrier holds:

| Attribute                  | Type              | Source / meaning                                                  |
| -------------------------- | ----------------- | ----------------------------------------------------------------- |
| `type_id`                  | `NF90_INT`        | Serialbox TypeID, as for fields (storage_mapping §1)              |
| `dims`                     | vector `NF90_INT` | C-order shape, reversed from Fortran sizes (storage_mapping §1.1) |
| `*minushalo` / `*plushalo` | `NF90_INT`        | optional, via the existing `put_halo_attr` (zero omitted)         |
| `stype`                    | `NF90_CHAR`       | `tens`/`bd`/`surf`/`sedimvel`, or empty string                    |
| `tracer_index`             | `NF90_INT`        | 1-based position in the ordered tracer set                        |

The descriptor write path is the field path with two extra string/int
attributes; no new netCDF machinery is introduced.

### 2. Tracer data lands as ordinary savepoint variables

A `!$SER TRACER` write at a savepoint produces a data variable inside
`/savepoints/sp_NNNNNN/`, identical in shape and dtype to a `!$SER DATA`
write (storage_mapping §6). The variable name is the tracer name, suffixed
with the timelevel when a `@timelevel` is present, joined by an underscore:
`q_v` with `@nnow` → `q_v_nnow`; no timelevel → `q_v`. This keeps the reader's
data path unchanged — only descriptor discovery (`/_tracers`) is new.

`timelevel` is recorded **only** in the on-disk variable name, not as a
descriptor attribute, because the same tracer at different timelevels is a
distinct snapshot, not a distinct tracer.

### 3. A minimal built-in tracer registry supplies the data (load-bearing)

Because the directive surface carries no data, the helper owns a small,
fixed-capacity **tracer registry** (module state in
`src/preserf-fortran/utils_preserf.f90`). A host-side entry point — **not**
emitted by pp_ser — populates it:

```
ppser_register_tracer(name, data, stype, timelevel)
```

records a name → (data, stype, timelevel, dims, type_id) binding. Then:

- `fs_RegisterAllTracers()` iterates the registry and writes a `/_tracers`
  descriptor (decision 1) for every entry, assigning `tracer_index` from
  registration order.
- `ppser_write_tracer_by_name(name, stype, [timelevel])` resolves the entry
  by name and writes its data to the current savepoint (decision 2).
- `ppser_write_tracer_by_idx(idx, [idx2], stype, [timelevel])` resolves by
  1-based index (a range `idx..idx2` writes each).
- `ppser_write_tracer_all(stype, [timelevel])` writes every registered
  tracer (filtered by `stype` when non-empty).

**This is the central assumption of the slice.** Real Serialbox binds these
writers to the host model's tracer framework; preserf substitutes a
self-contained registry so a `!$SER`-annotated program (and the test suite)
can round-trip tracers with no external model. The registry is the preserf
analogue of "the model told us about its tracers", and it keeps the v1.0
"no `error stop` stubs" rule (`specs/README.md` DoD item 4): every generated
tracer call has a real implementation.

### 4. OPTION: fix the helper surface to `verbosity`; the port rejects the rest

Fortran cannot accept arbitrary `key=value` dummies, but the preprocessor
emits whatever keys the directive contains (`src/preserf/preprocessor.py`
`_ser_option`). Per the spec's "pick one side" instruction we fix the helper:

- `fs_Option(verbosity)` takes a single optional `integer` argument, sets a
  module-level verbosity state in `utils_preserf.f90`, and records
  `_preserf_option_verbosity` (`NF90_INT`) as a reserved root attribute so
  the value round-trips and a cross-language test can assert it.
- `_ser_option` is tightened to **reject** any key other than `verbosity`
  (case-insensitive), preserving the existing `on/off → 1/0` mapping. This is
  a smaller blast radius than reshaping emission into a generic
  `(name, value)` pair, and `verbosity` is the only key pp_ser ever
  special-cases or that the reference corpus emits.

`_preserf_option_*` joins the reserved `_preserf_*` housekeeping namespace
(storage_mapping §3.1); readers ignore unrecognised `_preserf_*` attributes.

### 5. DATA_KBUFF: accumulate per-level slices, flush at `k == k_size`

`fs_write_kbuff(serializer, savepoint, name, data, k, k_size, mode)`
accumulates the level-`k` horizontal slice into a module-held buffer keyed by
`(savepoint, field)` and writes the assembled field to the savepoint group
when the last level arrives (`k == k_size`), then clears the buffer. The
on-disk result is byte-identical to a plain `DATA` write of the same field
(storage_mapping §6 already states this). Read mode follows the Slice A-1
resolve-and-validate pattern. The exact accumulation/flush boundary is
re-derived from Serialbox's Fortran `fs_write_kbuff` (the `vendor/pp_ser.py`
port only emits the call; the buffering semantics live in the Fortran helper)
and documented in a source comment.

### Schema version

All four changes are **additive** — a new `/_tracers` group, new reserved
root attributes, and a savepoint variable indistinguishable from a `DATA`
write. No existing attribute or layout changes meaning, so
`_preserf_schema_version` stays at `1`. Readers that predate this ADR ignore
`/_tracers` and `_preserf_option_*` and continue to work.

### Alternatives considered

- **Tracers bound to a host tracer framework (no built-in registry).**
  Faithful to Serialbox, but leaves preserf unable to write a tracer without
  an external model — untestable in isolation and impossible to satisfy the
  v1.0 DoD with. Rejected.
- **Tracer descriptors inlined on each savepoint instead of a central
  `/_tracers`.** Rejected for the same reason ADR 0002 centralised field
  metadata in `/_fields`: it duplicates static metadata on every snapshot.
- **Generic `fs_Option(name, value)` surface + reshaped emission.** More
  flexible, but touches the preprocessor's emission shape and the helper for
  a single real key (`verbosity`); deferred until a second option key
  actually exists.
- **A dedicated unlimited `k` dimension for DATA_KBUFF.** Rejected: ADR 0002
  already notes k-buffer writes interact awkwardly with an unlimited leading
  dimension, and producing a variable identical to a `DATA` write keeps the
  reader path single.

## Consequences

- A new `/_tracers` top-level group and `_preserf_option_*` reserved
  attributes are added to the schema, both additive and documented in
  `docs/references/storage_mapping.md`.
- The Python reference reader (`tests/_support/storage.py` `read_dump`) gains
  a `/_tracers` discovery path; tracer **data** needs no new read path since
  it lands as ordinary savepoint variables.
- preserf carries a built-in tracer registry that real Serialbox does not —
  a deliberate, documented divergence so the helper is self-contained. If a
  downstream user needs true host-framework binding, that is a future option
  layered on the same registry entry points, not a schema change.
- `fs_Option` supports only `verbosity` today; adding a second option key is
  a localised change to the helper plus the `_ser_option` allow-list.
- No schema-version bump; pre-ADR readers remain compatible.

Revisit when: a real tracer-framework binding is requested, a second OPTION
key is needed, or string/extended-dtype tracer data lands (tracks with the
deferred string-data-field work, storage_mapping §9).

## References

- ADR [0002](0002-storage-model-mapping.md) — storage model and layout.
- [`docs/references/storage_mapping.md`](../references/storage_mapping.md) —
  concrete on-disk mapping (§1 types, §1.1 axis order, §4 `/_fields`, §6
  savepoint variables).
- Directive grammar:
  [`docs/references/directives_specification.md`](../references/directives_specification.md)
  §3.8 (OPTION), §3.11 (REGISTERTRACERS), §3.14 (TRACER), DATA_KBUFF.
- Upstream Serialbox tracer + k-buffer helper API:
  `src/serialbox-fortran/m_serialize.f90` in
  [GridTools/serialbox](https://github.com/GridTools/serialbox) (names are
  the stable anchors; line ranges drift).
