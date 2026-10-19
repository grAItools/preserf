# Design: add string-array metainfo support

## Context

The netCDF Fortran API provides `nf90_put_att_text` (single text) but no
vector form; NC_STRING attributes with multiple values are writable from
C (`nc_put_att_string`) but the Fortran bindings expose only character
literals. `docs/references/storage_mapping.md` §1 pins the on-disk contract:
array string-tagged attributes (TypeID 22) are always `NC_STRING` vectors —
`NC_CHAR` has no shape rule that round-trips a vector of strings. The Python
support reader already decodes that encoding
(`tests/_support/storage.py`).

## Goals / Non-Goals

- Goal: `_s_1d` overloads exist and round-trip end-to-end (Fortran write,
  Python `tests/_support/storage.py` read).
- Non-goal: changing the on-disk attribute encoding of existing kinds.

## Decisions

- The on-disk encoding is fixed by the existing contract: the Fortran side
  must produce the same `NC_STRING` vector attributes the Python reader
  already supports — via the C interop path if the Fortran bindings cannot
  express it. No alternative encoding (e.g. concatenation) is in scope; the
  compatibility contract in `storage_mapping.md` §1 wins.

## Risks / Trade-offs

- The C-interop path adds an `iso_c_binding` dependency to the metainfo
  writer; keep it isolated so backends without the symbol still build.

## Open Questions

- None blocking.
