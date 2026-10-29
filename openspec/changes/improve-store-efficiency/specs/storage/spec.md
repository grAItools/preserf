# Spec Delta

## Purpose

Add opt-in compressed storage layout and batched perturb drawing without changing the default wire format, so large-field workloads gain storage efficiency while existing stores stay byte-identical.

## MODIFIED Requirements

### Requirement: Perturbed reads

The runtime SHALL support read-perturb mode: floating-point `fs_read_field_*_perturb` SHALL multiply each element by `1 + scale*(2u - 1)` with `u` uniform in [0, 1) and `scale` taken from `ppser_zrperturb`. Scale zero SHALL be an identity; zero-valued elements stay zero; rounding may leave individual values unchanged. Integer and logical perturb overloads SHALL perform an ordinary read (no-op perturbation). Random values MAY be drawn in bounded batches rather than per element, provided every element remains within the configured multiplicative bounds.

#### Scenario: Read-perturb applies scale

- **WHEN** a floating-point field is read with a non-zero `rperturb`
- **THEN** each non-zero element is perturbed within the configured multiplicative bounds

#### Scenario: Zero-scale and non-floating no-op

- **WHEN** the perturbation scale is zero, an integer or logical field is read, or an element is exactly zero
- **THEN** the value is returned unchanged

#### Scenario: Batched drawing preserves bounds

- **WHEN** perturbation values are drawn in bounded batches instead of per element
- **THEN** every element remains within the same multiplicative bounds as per-element drawing

## ADDED Requirements

### Requirement: Variable storage layout

Store variables SHALL support opt-in chunked and compressed storage: when a store-wide compression level is requested through the `ppser_initialize` keyword (or the `PRESERF_COMPRESSION` env var), field and tracer data variables SHALL be created as chunked, deflated variables with a chunk shape derived from the registered dims and bounded so that no chunk exceeds the HDF5 4 GiB per-chunk limit (whole-variable chunks are not permitted), while rank-0 (scalar) fields SHALL remain contiguous and uncompressed (netCDF cannot chunk a scalar) and stores created without a compression request SHALL remain contiguous and uncompressed so existing stores are byte-identical.

#### Scenario: Default store unchanged

- **WHEN** a store is initialized without a compression request
- **THEN** the store variable is created contiguous and uncompressed, matching existing stores

#### Scenario: Compressed store round-trips

- **WHEN** a store is initialized with a compression request and a field is written
- **THEN** the store variable is chunked with a bounded (not whole-variable) chunk shape and deflated, and the field round-trips through the Python support reader with identical values

#### Scenario: Scalar fields stay contiguous

- **WHEN** a store is initialized with a compression request and a rank-0 (scalar) field is written
- **THEN** the scalar variable is created contiguous and uncompressed, and round-trips identically
