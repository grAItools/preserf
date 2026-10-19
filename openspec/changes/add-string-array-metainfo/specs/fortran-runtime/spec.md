# Spec Delta

## Purpose

Extend the metainfo coverage of the Fortran runtime to 1D string arrays,
closing the deferred gap from the legacy type-coverage-matrix slice.

## MODIFIED Requirements

### Requirement: Metainfo coverage
`fs_add_savepoint_metainfo` and `fs_add_serializer_metainfo` SHALL accept
logical, int32, int64, real32, real64, and string scalars, plus 1D arrays of
every kind, including strings.

#### Scenario: Scalar and array metainfo
- **WHEN** metainfo of any supported kind is attached to a savepoint or the serializer
- **THEN** it is written to the store and round-trips through the Python support reader

#### Scenario: String-array metainfo
- **WHEN** a 1D string metainfo is attached
- **THEN** each element round-trips through the store and the Python support
  reader surfaces it as a list of strings

## REMOVED Requirements

### Requirement: String-array metainfo deferral
