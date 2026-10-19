# Design: add string-array metainfo support

## Context

The netCDF Fortran API provides `nf90_put_att_text` (single text) but no
vector form; NC_STRING attributes with multiple values are writable from
C (`nc_put_att_string`) but the Fortran bindings expose only character
literals. `docs/references/storage_mapping.md` §1 carries the original note.

## Goals / Non-Goals

- Goal: `_s_1d` overload exists and round-trips end-to-end (Fortran write,
  Python `tests/_support/storage.py` read, and the reverse direction where
  applicable).
- Non-goal: changing the on-disk attribute encoding of existing kinds.

## Decisions

- Serialize the 1D string array as a single `NC_STRING`-typed attribute via
  the C-interop path or as an `_preserf_*` housekeeping-encoded concatenation
  if the C interop proves too invasive — decide at implementation time with a
  note in `docs/references/storage_mapping.md`, which is the mapping of
  record.

## Risks / Trade-offs

- Cross-language round-trip fidelity for string arrays depends on the
  `netcdf4` Python package's NC_STRING support; verify on the pinned
  versions in `pixi.toml`.

## Open Questions

- None blocking; the encoding choice is intentionally deferred to
  implementation.
