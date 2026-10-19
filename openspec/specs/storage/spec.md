# Storage Specification

## Purpose

The on-disk serialization format written by the Fortran runtime and read by the Python test support: group-per-savepoint layout, dtype mapping, backend selection, and round-trip behavior. The concrete attribute and TypeID mapping is `docs/references/storage_mapping.md`.

## Requirements

### Requirement: Backend selection

The runtime SHALL write to NetCDF4 (default, `<dir>/<prefix>.nc`) or NCZarr V2 (`<dir>/<prefix>.zarr`, directory store via the `file://<path>#mode=nczarr,zarr2` URL), selected by the `backend=` keyword on `ppser_initialize` and overridable at runtime by the `PRESERF_BACKEND` environment variable. Both backends SHALL use the same `nf90_*` code path and group layout.

#### Scenario: Backend override

- **WHEN** the process runs with `PRESERF_BACKEND=nczarr-v2`
- **THEN** initialization opens a `.zarr` store instead of `.nc`, with identical group structure

### Requirement: Group layout

Each store SHALL contain a `/_fields` registry group and one group per savepoint under `/savepoints/sp_NNNNNN`, with fields written as variables inside the savepoint groups.

#### Scenario: Savepoint sequence

- **WHEN** a run creates two savepoints and writes a field to each
- **THEN** the store contains `/savepoints/sp_000000` and `/savepoints/sp_000001` with the field as a variable in each

### Requirement: Type coverage

Fields of boolean, int32, int64, real32, and real64 in ranks 0D to 4D SHALL round-trip through the store with their dtype preserved per the TypeID mapping in `docs/references/storage_mapping.md`.

#### Scenario: Cross-language round-trip

- **WHEN** the Fortran runtime writes a `real64` 3D field and the Python support reader (`tests/_support/storage.py`) reads it back
- **THEN** the array shape, dtype, and values match, in both write and read direction

### Requirement: Initialization keyword coverage

`ppser_initialize` SHALL accept every Serialbox-compatible keyword: `directory`, `prefix`, `mode`, `directory_ref`, `prefix_ref`, `singlefile`, `mpi_rank`, `rprecision`, `rperturb`, `realtype`, `archive`, `unique_id`, with defaults matching Serialbox so existing call sites are unaffected.

#### Scenario: Keyword acceptance

- **WHEN** `ppser_initialize` is called with any subset of the Serialbox-compatible keywords
- **THEN** the call compiles and the omitted keywords keep Serialbox's default behavior

### Requirement: Rank-suffixed stores

The `mpi_rank` initialization keyword SHALL apply a `_rank<n>` suffix to the store name so parallel runs produce one store per rank.

#### Scenario: Parallel rank suffix

- **WHEN** two serializers open with `mpi_rank=0` and `mpi_rank=1`
- **THEN** two distinct stores exist, suffixed `_rank0` and `_rank1`

### Requirement: Initialization state threading

The `realtype`/`rprecision`, and `rperturb` initialization keywords SHALL update the runtime state that generated code reads: `realtype`/`rprecision` set `ppser_realtype`/`ppser_reallength` (so pp_ser-emitted REGISTER calls pick up single-precision metadata), and `rperturb` sets `ppser_zrperturb` consumed by the read-perturb path.

#### Scenario: Single-precision registration

- **WHEN** `ppser_initialize` runs with `rprecision=real32` and a `real` field is registered
- **THEN** the field's type metadata records the single-precision TypeID

### Requirement: Initialization metadata round-trip

The `singlefile`, `archive`, and `unique_id` initialization keywords SHALL be recorded as root attributes of the store and SHALL surface on the Python dump unchanged.

#### Scenario: Metadata round-trip

- **WHEN** `singlefile`/`archive`/`unique_id` are set at initialization
- **THEN** the Python reader surfaces them on the dump with matching values

### Requirement: Perturbed reads

The runtime SHALL support read-perturb mode: `fs_read_field_*_perturb` SHALL apply the perturbation scale from `ppser_zrperturb` to real-valued fields during deserialization.

#### Scenario: Read-perturb applies scale

- **WHEN** a field is read with a non-zero `rperturb`
- **THEN** the returned values differ from the stored values by the configured perturbation

### Requirement: Serialbox wire compatibility

Where Serialbox defines equivalent behavior, stores SHALL be byte-compatible with the Serialbox `BinaryArchive`/`MetaData` reference layout for the golden fixtures, so serialbox4py can read preserf dumps and vice versa (column-major element order, declaration-order dims).

#### Scenario: Golden fixture

- **WHEN** the golden serialbox fixtures are read through `tests/_support/serialbox.py`
- **THEN** every field decodes with the reference values, including multi-dimensional arrays in Fortran order
