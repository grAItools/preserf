# Design: add append mode

## Context

Append is currently rejected at `utils_preserf.f90` (the `'a'` case in
`preserf_open_serializer`) because resuming `next_sp_index` requires an
`nf90_inq_grps` call shape that the netcdf-fortran 4.5.x wrapper makes
awkward. The runtime README documents this as a known limitation.

## Goals / Non-Goals

- Goal: `mode='a'` opens an existing store, resumes the savepoint group
  index by scanning existing `/savepoints/sp_NNNNNN` groups, and appends.
- Goal: sanity-check the `_preserf_*` housekeeping attributes documented in
  `storage_mapping.md` §1 on open; abort on disagreement.
- Non-goal: concurrent multi-writer append (Serialbox baseline is a single
  writer at a time).

## Decisions

- Resolve the group enumeration the netcdf-fortran 4.5.x wrapper supports
  (query group count first, then query names into an allocated buffer) rather
  than parsing group names out of global attributes.
- Derive `next_sp_index` as max(existing `sp_NNNNNN` indices) + 1; validate
  that the naming is contiguous before trusting the scan.

## Risks / Trade-offs

- netcdf-fortran API shape differs across 4.5.x/4.6.x; keep the workaround
  isolated in one helper so it can be replaced when the wrapper improves.

## Open Questions

- None blocking.
