# Proposal: add append mode

## Why

`ppser_initialize(..., mode='a')` is rejected outright rather than
half-implemented, so pp_ser-generated source that opens a store in append
mode fails at initialization. The work was speced in the legacy
`specs/2026-05-fortran-append-mode/` directory (deleted in the OpenSpec
migration) and explicitly deferred past v1.0; this change carries it forward
so the tracked work stays visible, instead of being lost with the legacy
tree.

## What Changes

Open an existing preserf store in append mode: resume the savepoint group
index by scanning the existing `/savepoints/sp_NNNNNN` groups, and append new
savepoints and field writes without forking the store or clobbering existing
data.

## Out of Scope

- Read-perturb, type-coverage, tracers, backend selector (separate slices)
- Concurrent multi-writer append; append assumes a single writer at a time
  (the Serialbox baseline)
