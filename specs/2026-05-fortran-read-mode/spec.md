# Slice A-1: Read-mode create-or-resolve-and-validate

## Problem

`fs_register_field`, `fs_create_savepoint`, `fs_add_savepoint_metainfo`
and `fs_add_serializer_metainfo` unconditionally **create** their netCDF
objects. pp_ser-generated source calls these directives _outside_ the
`SELECT CASE (ppser_get_mode())` that gates DATA blocks, so pointing a
generated read run at an existing read-only store aborts at the first
create call — `fs_register_field`'s `nf90_def_var` on the registry
carrier, or `fs_create_savepoint`'s `nf90_def_grp(sp_NNNNNN)`,
whichever the generated source reaches first.

Additionally, the read path validates the registry on `s%fields_grpid`
but pulls the data variable from `sp%grpid` — `ppser_savepoint` lives
on `ppser_serializer` rather than `ppser_serializer_ref`, so an
_explicit_ reference store would validate against one file and read
from another.

## Goal

pp_ser-generated read runs against an existing store succeed end-to-end
without aborting, and explicit reference stores read from the file they
were registered against.

## Non-goals

- Read-perturb (5-arg `fs_read_field`): tracked as Slice A-2.
- Type-coverage beyond what v0.1 ships (`real64` 1D/2D/3D fields,
  scalar metainfo): tracked as Slice B.
- Backend selector / NCZarr URL targets: tracked as Slice E.

## Success criteria

- `fs_register_field` in read mode resolves the existing
  `/_fields/<name>` registry entry and aborts with a clear error on
  any mismatch in type, dims, or halos.
- `fs_create_savepoint` in read mode resolves the existing savepoint
  group and validates the runtime `name` argument against the
  group's `name` attribute (per `storage_mapping.md` §5).
- `fs_add_savepoint_metainfo` / `fs_add_serializer_metainfo` in read
  mode validate that the existing attribute's value **and**
  `__preserf_type_id` match the runtime arguments.
- The `ppser_serializer` vs `ppser_serializer_ref` savepoint-grpid
  mismatch is resolved (either savepoints carry per-serializer grpids
  or `fs_read_field` re-resolves under `s` before reading).
- A native Fortran test round-trips a write run and then a read run
  against the same store, exercising the resolve+validate branch
  end-to-end.
- A second native scenario uses an explicit
  `directory_ref` / `prefix_ref` pair (or otherwise mismatched `s`
  / `sp` pairing) so the `ppser_serializer_ref` grpid path is
  actually covered — the same-store round-trip alone hits the
  implicit-ref path.
