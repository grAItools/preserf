# 7. NCZarr-v2 compression is deferred pending NCZarr codec plugins

## Status

Proposed

## Context

[Issue #111](https://github.com/grAItools/preserf/issues/111) asks preserf to
support opt-in field-write compression on the `nczarr-v2` backend, not just on
`netcdf4`. The motivating feature — an opt-in `compression` knob on
`ppser_initialize` that drives `nf90_def_var_deflate` (NetCDF-4 / HDF5 deflate)
on the field-write path — was added in PR #46 and made opt-in in
[PR #53](https://github.com/grAItools/preserf/pull/53). That PR deliberately
**rejects** `compression>0` together with `backend=nczarr-v2` at the
`ppser_initialize` boundary, with the message:

> compression is not supported with the 'nczarr-v2' backend in this release
> (netcdf4 only)

Issue #111 is the tracked follow-up to remove or narrow that rejection by
attaching a **Zarr codec** via netcdf-c's NCZarr filter API
(`nc_def_var_filter`, which records the codec in the Zarr array metadata)
instead of the HDF5 deflate filter, so a compressed NCZarr store round-trips
losslessly.

Two facts, established while scoping #111, govern this decision.

### 1. The prerequisite (PR #53) is not yet on `main`

PR #53 (`feat(fortran): add opt-in field-write compression knob`) is **open,
not merged** (base `main`, head `claude/fix-issue-46-optin-compression`). On
`main` today there is therefore:

- no `compression` keyword on `ppser_initialize` and no `ppser_deflate_level`
  module state;
- no `nf90_def_var_deflate` / `nf90_def_var_chunking` call on the field-write
  path (`m_preserf.F90` `ensure_variable`);
- no `nczarr-v2` compression guard to relax;
- none of the `compression-nczarr*` negative tests that #111 asks to update.

Issue #111's three acceptance items ("remove the up-front rejection", "update
the negative tests", "update the §9 abort message") all reference code that
exists only inside PR #53's branch. Implementing #111 on top of `main` would
mean first re-implementing the whole of PR #53 (≈810 added lines across 10
files) — duplicating an open, unmerged PR. That is the wrong sequencing: #111
must land **after** PR #53 merges, as an edit to the guard PR #53 introduced.

### 2. The NCZarr codec layer is non-functional in the current environment

Independently of sequencing, the acceptance criterion ("`compression>0` with
`backend=nczarr-v2` writes a compressed NCZarr store that round-trips
losslessly") cannot be satisfied — or verified — with the netcdf-c build this
project pins. Reproduced empirically (conda-forge `libnetcdf` 4.10.0,
`netcdf-fortran` 4.6.2) with a minimal C program calling `nc_def_var_filter`
on a freshly created store:

| store                          | `nc_def_var_filter` result                                  |
| ------------------------------ | ----------------------------------------------------------- |
| NetCDF-4 (`.nc`), zlib id 1    | `0` OK — store round-trips losslessly                       |
| NCZarr-v2, zlib id 1 (deflate) | `-136` `NetCDF: Filter error: undefined filter encountered` |
| NCZarr-v2, zstd id 32015       | `-136` (same)                                               |
| NCZarr-v2, blosc id 32001      | `-136` (same)                                               |
| NCZarr-v2, bzip2 id 307        | `-136` (same)                                               |
| NCZarr-v2, lz4 id 32004        | `-136` (same)                                               |

This matches the failure the issue reports. The cause is environmental, not a
code defect:

- `nc-config --has-stdfilters` reports `deflate szip blosc zstd bz2`, so the
  _compression libraries_ are linked into netcdf-c. That flag is misleading
  for NCZarr: the HDF5 path can use the built-in filters, but the **NCZarr
  codec layer** resolves a numeric HDF5 filter id to a named Zarr codec via
  loadable plugin `.so` files in the netcdf-c plugin directory.
- `nc-config --plugindir` points at
  `…/.pixi/envs/default/hdf5/lib/plugin`, which **does not exist**, and
  `HDF5_PLUGIN_PATH` is unset. The conda-forge `libnetcdf` 4.10.0 package in
  this environment ships **no** NCZarr codec plugins (verified: no NCZarr
  codec `.so` anywhere under the env). With no codec plugin to resolve, every
  filter id is "undefined" for NCZarr.

Per the netcdf-c documentation, the fix is to provide the codec plugins on the
plugin search path — e.g. building netcdf-c with `--with-plugin-dir` /
`-DPLUGIN_INSTALL_DIR`, and/or installing a conda-forge package that ships the
plugins (`hdf5-external-filter-plugins` for the HDF5 side) and exporting
`HDF5_PLUGIN_PATH`. Adding such a runtime/build dependency is itself an
architectural choice that warrants its own ADR and a `pixi.toml` change, and it
must be shown to actually populate the NCZarr codec path (not just the HDF5
filter path) before the feature can be claimed.

## Decision

Defer the NCZarr-v2 compression implementation. Specifically:

1. Do **not** implement #111 against `main` now. It is a follow-up edit to
   PR #53 and must be sequenced after that PR merges, so it modifies the guard
   and tests PR #53 introduces rather than re-creating them.
2. Treat the missing NCZarr codec plugins as the real blocker. Before the
   feature can round-trip, the environment must provide loadable NCZarr codecs
   on the plugin search path. That is an environment/packaging change gated by
   its own ADR + `pixi.toml` update, and must be validated with a probe like
   the one above returning `0` (not `-136`) for at least one codec on an NCZarr
   store.
3. Keep PR #53's up-front rejection of `compression>0 + backend=nczarr-v2` as
   the correct conservative behaviour until both (1) and (2) hold: it is better
   to abort clearly at init than to silently write an unreadable store.

This ADR records the investigation so the next attempt starts from the
established root cause rather than re-discovering it.

## Consequences

- **No behaviour change ships from this ADR.** It is documentation only; the
  verification gate stays green and no runtime dependency is added.
- The codec-resolution root cause and a concrete forward path (provide NCZarr
  codec plugins via env/packaging, gated by its own ADR) are captured, so the
  eventual implementer does not have to re-run the investigation.
- The correct sequencing is recorded: #111 lands on top of a merged PR #53,
  editing its guard/tests, not duplicating them.
- When the plugins are available and PR #53 has merged, the remaining work is
  narrow: switch the NCZarr path from `nf90_def_var_deflate` to a codec via
  `nf90_def_var_filter`, relax the guard, flip the `compression-nczarr*` tests
  from "reject" to "round-trip", and update `storage_mapping.md` §9 and the
  abort message.

> The empirical probe used for the table above (a minimal C program calling
> `nc_create` + `nc_def_var_filter` + round-trip on both backends) is not
> checked in; it is reproducible from this ADR's description against the pinned
> netcdf-c, and a productised version belongs with the implementation PR
> (steps 1 + 2 above).
