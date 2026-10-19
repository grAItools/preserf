# Spec Delta

## Purpose

Support opening an existing preserf store in append mode, resuming the
savepoint sequence where the previous run left off.

## ADDED Requirements

### Requirement: Append mode

`ppser_initialize(..., mode='a')` SHALL open an existing preserf store and
append new savepoints and field writes without forking the store or
clobbering existing data.

#### Scenario: Resume savepoint index

- **WHEN** a store with savepoints `sp_000000`..`sp_000002` is re-opened with `mode='a'`
- **THEN** the next created savepoint is `sp_000003` and the existing groups are untouched

#### Scenario: Housekeeping sanity check

- **WHEN** the `_preserf_*` housekeeping attributes on the opened store disagree with what the new run would write
- **THEN** the open aborts with a clear error rather than silently forking the store

#### Scenario: Append round-trip

- **WHEN** a native test writes a store, closes it, re-opens in append mode, writes additional savepoints, and reads back
- **THEN** both the original and the appended savepoints are present and correctly ordered
