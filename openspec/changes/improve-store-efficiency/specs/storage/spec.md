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

Store variables SHALL support opt-in chunked and compressed storage: a field registered through the Fortran registration API (`fs_register_field` or the auto-registration path) with a compression request SHALL be created as a chunked, deflated variable, while default registrations SHALL remain contiguous and uncompressed so existing stores are byte-identical.

#### Scenario: Default registration unchanged

- **WHEN** a field is registered without a compression request
- **THEN** the store variable is created contiguous and uncompressed, matching existing stores

#### Scenario: Compressed registration round-trips

- **WHEN** a field is registered through the Fortran registration API with a compression request and written
- **THEN** the store variable is chunked and deflated, and the field round-trips through the Python support reader with identical values
