# Proposal

## Why

The runtime's int32 boundary guards are inconsistent: `m_preserf`'s
private `require_fits_int32` checks only the upper bound while
`utils_preserf`'s same-named guard checks both, and `fs_Option`
already violates the "callers reject negatives first" precondition the
`m_preserf` copy documents — a silent int64-to-int32 wrap path onto a
wire attribute under `-fdefault-integer-8` builds
(`m_preserf.F90:2445-2455`, `:1331-1333`). Related gaps: k-buffer
reads skip the `/_fields` registry cross-check the field read path
performs; `fs_write_field` lacks the friendly read-only abort; and two
stale doc claims understate coverage that exists.

## What Changes

- Make both private int32 guards check both bounds so no caller can inherit the wrap class
- Route the k-buffer read path through registry validation before loading
- Add the read-only-handle abort to the write template
- Refresh the stale doc claims to state actual coverage

## Out of Scope

- Append mode and string-array metainfo (tracked in their own changes)
- Wire-format changes, new public API, thread-safety work, and non-ASCII path hardening

## Capabilities

### Modified Capabilities

- `fortran-runtime`: the canonical serialization API gains uniform boundary-guard and handle-state scenarios; a new k-buffer validation-parity requirement pins registry consultation on the k-buffer read path

## Impact

`m_preserf.F90`, `utils_preserf.f90`, both `.inc` templates, the runtime README, `tests/fortran/e2e/e2e_fixture.f90.in`, native ctest scenarios, CHANGELOG.
