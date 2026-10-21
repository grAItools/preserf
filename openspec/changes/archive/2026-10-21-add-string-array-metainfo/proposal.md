# Proposal: add string-array metainfo support

## Why

`fs_add_savepoint_metainfo` / `fs_add_serializer_metainfo` accept 1D arrays
for every supported kind except strings. The gap was deferred during the
type-coverage-matrix slice ("Slice B′") because the netCDF Fortran API has no
clean vector-of-strings `nf90_put_att` path, and the deferral was recorded in
the legacy specs tree that this migration retires. Porting it here keeps the
tracked work visible in `openspec list` instead of losing it with the old
specs directory.

## What Changes

Add a `_s_1d` metainfo overload that writes a 1D string metainfo attribute
(`NC_STRING`), round-trips it through the Python support reader, and removes
the string-array limitation note from the fortran-runtime spec.

## Out of Scope

- Any change to field (non-metainfo) serialization
- New backends or storage layout changes
