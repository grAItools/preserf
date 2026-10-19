# Storage Specification

## Purpose

The on-disk serialization format written by the Fortran runtime and read by the Python test support: group-per-savepoint layout, dtype mapping, backend selection, and round-trip behavior. The concrete attribute and TypeID mapping is `docs/references/storage_mapping.md`.

## Requirements

### Requirement: Backend selection

The runtime SHALL write to NetCDF4 (default, `<dir>/<prefix>.nc`) or NCZarr V2 (`<dir>/<prefix>.zarr`, directory store via the `file://<path>#mode=nczarr,zarr2` URL). An explicit `backend=` keyword on `ppser_initialize` SHALL take precedence over the `PRESERF_BACKEND` environment variable, which in turn overrides the default. Both backends SHALL use the same `nf90_*` code path and group layout.

#### Scenario: Explicit argument beats environment

- **WHEN** `ppser_initialize` is called with an explicit `backend=` while `PRESERF_BACKEND` is set to a different value
- **THEN** the explicit argument wins and the environment variable is ignored

#### Scenario: Environment fallback

- **WHEN** no `backend=` argument is passed and the process runs with `PRESERF_BACKEND=nczarr-v2`
- **THEN** initialization opens a `.zarr` store instead of `.nc`, with identical group structure

### Requirement: Group layout

Each store SHALL contain a `/_fields` registry group and one group per savepoint under `/savepoints/sp_NNNNNN`, with fields written as variables inside the savepoint groups.

#### Scenario: Savepoint sequence

- **WHEN** a run creates two savepoints and writes a field to each
- **THEN** the store contains `/savepoints/sp_000000` and `/savepoints/sp_000001` with the field as a variable in each

### Requirement: Type coverage

Fields of boolean, int32, int64, real32, and real64 in ranks 0D to 4D SHALL round-trip through the store with their dtype preserved per the TypeID mapping in `docs/references/storage_mapping.md`. Dimensions are recorded in netCDF C-order (slowest axis first) per `storage_mapping.md` §1.1; the Python support reader handles the axis translation.

#### Scenario: Cross-language round-trip

- **WHEN** the Fortran runtime writes a `real64` 3D field and the Python support reader (`tests/_support/storage.py`) reads it back
- **THEN** the array shape, dtype, and values match, in both write and read direction

### Requirement: Initialization keyword coverage

`ppser_initialize` SHALL require `directory` and `prefix`. The Serialbox-compatible optional keywords are `mode`, `directory_ref`+`prefix_ref` (supplied together or not at all), `singlefile`, `mpi_rank`, `rprecision`, `rperturb`, `realtype`, `archive`, `unique_id`, and `backend`. Append mode (`mode='a'`) is rejected (tracked in the `add-append-mode` change).

#### Scenario: Required and paired arguments

- **WHEN** `ppser_initialize` is called with exactly one of `directory_ref`/`prefix_ref`
- **THEN** initialization fails with a clear error instead of misbehaving

### Requirement: Rank-suffixed stores

The `mpi_rank` initialization keyword SHALL apply a `_rank<n>` suffix to the store name so parallel runs produce one store per rank.

#### Scenario: Parallel rank suffix

- **WHEN** two serializers open with `mpi_rank=0` and `mpi_rank=1`
- **THEN** two distinct stores exist, suffixed `_rank0` and `_rank1`

### Requirement: Initialization state threading

The `realtype` keyword SHALL set the type string used by `ppser_realtype`/`ppser_reallength` (e.g. `realtype='float'` registers single-precision real fields), and `rperturb` SHALL set `ppser_zrperturb` consumed by the read-perturb path. `rprecision` SHALL be accepted for Serialbox interface compatibility as a real-valued tolerance and is currently ignored — the real byte length is determined by `realtype`/the real kind.

#### Scenario: Single-precision registration

- **WHEN** `ppser_initialize` runs with `realtype='float'` and a `real` field is registered
- **THEN** the field's type metadata records the single-precision TypeID

#### Scenario: Tolerance accepted but unused

- **WHEN** `ppser_initialize` is called with a real-valued `rprecision`
- **THEN** the call succeeds and the value does not change the registered real byte length

### Requirement: Initialization metadata round-trip

The `singlefile`, `archive`, and `unique_id` initialization keywords SHALL be recorded as root attributes of the store and SHALL surface on the Python dump unchanged; they are metadata-only and do not implement Serialbox's operational semantics.

#### Scenario: Metadata round-trip

- **WHEN** `singlefile`/`archive`/`unique_id` are set at initialization
- **THEN** the Python reader surfaces them on the dump with matching values

### Requirement: Perturbed reads

The runtime SHALL support read-perturb mode: floating-point `fs_read_field_*_perturb` SHALL multiply each element by `1 + scale*(2u - 1)` with `u` uniform in [0, 1) and `scale` taken from `ppser_zrperturb`. Scale zero SHALL be an identity; zero-valued elements stay zero; rounding may leave individual values unchanged. Integer and logical perturb overloads SHALL perform an ordinary read (no-op perturbation).

#### Scenario: Read-perturb applies scale

- **WHEN** a floating-point field is read with a non-zero `rperturb`
- **THEN** each non-zero element is perturbed within the configured multiplicative bounds

#### Scenario: Zero-scale and non-floating no-op

- **WHEN** the perturbation scale is zero, an integer or logical field is read, or an element is exactly zero
- **THEN** the value is returned unchanged

### Requirement: Serialbox reference fidelity

The test-support Serialbox reader/writer (`tests/_support/serialbox.py`) SHALL decode and encode Serialbox `BinaryArchive`/`MetaData` payloads faithfully, verified against real `serialbox4py` dumps in the golden fixture test. Byte-identity SHALL be guaranteed only for those reference `.dat` payloads. Runtime stores are NetCDF4/NCZarr — they are NOT Serialbox `BinaryArchive` stores; cross-language round-trips go through the Python support adapters, not through serialbox4py.

#### Scenario: Golden fixture

- **WHEN** the golden serialbox fixtures are read through `tests/_support/serialbox.py`
- **THEN** every field decodes with the reference values, with array payloads in column-major (Fortran) element order
