# Spec Delta

## Purpose

Make the Fortran runtime's boundary guards and read-path validation uniform so no silent int64-to-int32 wrap path remains, and pin k-buffer validation parity with the field read path.

## MODIFIED Requirements

### Requirement: Canonical serialization API

`m_preserf` SHALL export `fs_register_field`, `fs_create_savepoint`, `fs_add_savepoint_metainfo` / `fs_add_serializer_metainfo`, `fs_write_field` / `fs_read_field`, `fs_write_kbuff`, `fs_Option`, `fs_enable_serialization` / `fs_disable_serialization` / `fs_serialization_status`, and the tracer write API (`fs_RegisterAllTracers`, `ppser_register_tracer`, `ppser_write_tracer_by_name/_by_idx/_all`). Every user-supplied integer that lands in a wire attribute SHALL be range-checked at both bounds, and write entry points on read-only serializers SHALL abort with the same friendly lifecycle message.

#### Scenario: Enable/disable

- **WHEN** serialization is disabled via `fs_disable_serialization` and a field write is issued
- **THEN** the write is a no-op, and `fs_serialization_status` reports disabled

#### Scenario: Out-of-range option value aborts

- **WHEN** `fs_Option` is called with a verbosity below the int32 lower bound (for example −2⁴⁰ under a 64-bit default-integer build)
- **THEN** it aborts with a clear message naming the field and value instead of silently wrapping onto the wire

#### Scenario: Write on a read-only handle

- **WHEN** `fs_write_field` is issued on a serializer opened read-only
- **THEN** it aborts with the read-only lifecycle message rather than a raw netCDF permission error

## ADDED Requirements

### Requirement: K-buffer validation parity

The k-buffer read path SHALL consult the `/_fields` registry for shape and type agreement before loading, mirroring the field read path, so a store whose registry and variables disagree is rejected loudly on both paths.

#### Scenario: Registry-mismatched store

- **WHEN** a store's `/_fields` registry and its k-buffer variable disagree on shape
- **THEN** the k-buffer read aborts with a clear message just as the field read path would
