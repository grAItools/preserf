# Proposal

Issue: #111

## Why

Compression on the `nczarr-v2` backend is rejected at the
`ppser_initialize` boundary (`compression>0` combined with
`backend=nczarr-v2` aborts with a clear message), because the
NetCDF-4/HDF5 deflate-filter path cannot resolve on an NCZarr
store. Zarr itself supports compression natively (per-array
codecs), so the limitation is preserf's mechanism, not the
format.

## What Changes

- Attach a Zarr codec through netcdf-c's NCZarr filter API
  (`nc_def_var_filter` / the codec recorded in the Zarr array
  metadata) so `compression>0` with `backend=nczarr-v2` writes a
  readable, compressed store
- Remove, or narrow to genuinely unsupported cases, the up-front
  rejection; update `storage_mapping.md` §9 and the abort message
- Establish and document how runtime filter plugins are provided
  (build env + runtime), or pick a codec available without
  external plugins

## Out of Scope

- The netcdf4 backend path (unchanged)
- Default-on compression and wire-format changes

## Blocked

External dependency: the NCZarr codec plugins do not resolve in
the current environment (`NetCDF: Filter error: undefined filter
encountered`, netcdf-c 4.10.0). This change is born blocked per
ADR 0012's blocked/deferred state; unblocking requires an
environment where the codec plugins resolve (`HDF5_PLUGIN_PATH`
or bundled codecs).

## Capabilities

### Modified Capabilities

- `storage`: the variable-storage-layout compression requirement
  gains an nczarr-v2 scenario

## Impact

`utils_preserf.f90` (the guard), `m_preserf.F90` (the filter
path), `dev/references/storage_mapping.md` §9, the
`compression-nczarr*` negative ctest scenarios.
