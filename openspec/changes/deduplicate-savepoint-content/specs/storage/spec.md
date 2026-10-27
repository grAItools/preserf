# Spec Delta

## Purpose

Add opt-in cross-savepoint content deduplication without changing the default wire format, so workloads whose fields are unchanged across savepoints store each unique payload once while existing stores stay byte-identical.

## ADDED Requirements

### Requirement: Cross-savepoint content deduplication

The runtime SHALL support opt-in content deduplication across savepoints: when enabled for a store, identical field payloads SHALL be stored once as dictionary entries and referenced by every savepoint that writes them, while default stores SHALL remain one-dataset-per-write so existing stores are byte-identical.

#### Scenario: Default store unchanged

- **WHEN** a store is created without the dedup option
- **THEN** every (savepoint, field) write lands as its own dataset, matching existing stores

#### Scenario: Identical payloads stored once

- **WHEN** dedup is enabled and the same field payload is written at two savepoints
- **THEN** the payload is stored once as a dictionary entry and both savepoints reference it

#### Scenario: Deduplicated store round-trips

- **WHEN** a deduplicated store is read by the Python support reader
- **THEN** every savepoint resolves its dictionary references to identical values
