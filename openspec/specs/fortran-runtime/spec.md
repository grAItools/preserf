# Fortran Runtime Specification

## Purpose

The Fortran helper modules shipped as source inside the wheel: the canonical `fs_*` serialization API, the `ppser_*` lifecycle and module-level state, and the alias modules that let legacy pp_ser-generated code compile unchanged.

## Requirements

### Requirement: Canonical serialization API

`m_preserf` SHALL export `fs_register_field`, `fs_create_savepoint`, `fs_add_savepoint_metainfo` / `fs_add_serializer_metainfo`, `fs_write_field` / `fs_read_field`, `fs_write_kbuff`, `fs_Option`, `fs_enable_serialization` / `fs_disable_serialization` / `fs_serialization_status`, and the tracer write API (`fs_RegisterAllTracers`, `ppser_register_tracer`, `ppser_write_tracer_by_name/_by_idx/_all`).

#### Scenario: Enable/disable

- **WHEN** serialization is disabled via `fs_disable_serialization` and a field write is issued
- **THEN** the write is a no-op, and `fs_serialization_status` reports disabled

### Requirement: Field type/rank coverage

`fs_write_field` and `fs_read_field` SHALL cover boolean, int32, int64, real32, and real64 in ranks 0D to 4D via generic interfaces; string data fields are deferred past v1.0 (tracked in ADR 0010 and `dev/references/storage_mapping.md`). `fs_read_field` SHALL additionally provide perturb variants for the read-perturb path.

#### Scenario: Generic dispatch

- **WHEN** a `real64` 2D array and an `int32` scalar are written through the same `fs_write_field` interface
- **THEN** both dispatch to the correct concrete routine without caller-side type switches

### Requirement: Metainfo coverage

`fs_add_savepoint_metainfo` and `fs_add_serializer_metainfo` SHALL accept logical, int32, int64, real32, real64, and string scalars, plus 1D arrays of every kind except string arrays.

#### Scenario: Scalar and array metainfo

- **WHEN** metainfo of any supported kind is attached to a savepoint or the serializer
- **THEN** it is written to the store and round-trips through the Python support reader

### Requirement: String-array metainfo deferral

1D string-array metainfo SHALL NOT be provided by the runtime; the netCDF Fortran API has no vector-of-strings attribute path, so callers must store strings as scalars or one attribute per element. The deferred work is tracked in the `add-string-array-metainfo` change.

#### Scenario: String-array limitation

- **WHEN** a 1D string metainfo is requested
- **THEN** the runtime does not provide the routine

### Requirement: Lifecycle and module state

`utils_preserf` SHALL provide `ppser_initialize` / `ppser_finalize`, `ppser_set_mode` / `ppser_get_mode` (write / read / read-perturb), and the module-level state pp_ser-generated code relies on (`ppser_serializer`, `ppser_serializer_ref`, `ppser_savepoint`, `ppser_zrperturb`, type/length constants), with `ppser_realtype` / `ppser_reallength` updateable from initialization.

#### Scenario: Mode switch

- **WHEN** `ppser_set_mode` sets read mode and generated code issues a `!$SER DATA` expansion
- **THEN** the expansion reads fields back instead of writing them

### Requirement: Kbuffer serialization

`fs_write_kbuff` SHALL serialize 1D/2D/3D `real64` buffers (the `!$SER DATA_KBUFF` target) into the current savepoint.

#### Scenario: DATA_KBUFF expansion

- **WHEN** a `!$SER DATA_KBUFF` directive names a `real64` 1D buffer
- **THEN** the generated `fs_write_kbuff` call writes it and the store round-trips its values

### Requirement: Tracer serialization

The tracer API SHALL register and write tracers by name, index, or all-at-once, supporting the `!$SER REGISTERTRACERS` / `!$SER TRACER` directives with their `#tens`/`#bd`/`#surf`/`#sedimvel` suffix and optional `@<timelevel>` specifier, which the expansion emits as a `timelevel=...` argument on the generated call.

#### Scenario: Write all tracers

- **WHEN** `ppser_write_tracer_all` is called after `fs_RegisterAllTracers`
- **THEN** every registered tracer lands in the current savepoint under its declared name

#### Scenario: Time-level specifier

- **WHEN** a `!$SER TRACER t@2` directive is expanded
- **THEN** the generated call passes `timelevel=2` for that tracer

### Requirement: Legacy alias modules

`m_serialize` and `utils_ppser` SHALL re-export the preserf API symbols so pp_ser-generated Fortran compiles unchanged against preserf.

#### Scenario: Unmodified legacy source

- **WHEN** a pp_ser-annotated source that `USE m_serialize` / `USE utils_ppser` is expanded and compiled against preserf
- **THEN** it builds and runs without edits to its serialization calls
