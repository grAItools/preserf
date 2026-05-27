# Slice D (open work): `ppser_initialize` widening + end-to-end test

## Problem

`ppser_initialize` accepts only `directory`, `prefix`, `mode`,
`directory_ref`, and `prefix_ref`. Serialbox accepts additionally
`singlefile`, `mpi_rank`, `rprecision`, `rperturb`, `realtype`,
`archive`, and `unique_id`. pp_ser passes those through verbatim from
`!$SER INIT` directives, so generated source linking against preserf
fails to compile (or silently drops the keyword) when the source
template uses any of them.

Several of these keywords are _not_ purely metadata:

- `mpi_rank` — per `storage_mapping.md` §9 maps to a `_rank<n>` suffix
  on the store name. `preserf_open_serializer` must apply the suffix,
  otherwise parallel runs would clobber each other's stores.
- `realtype` / `rprecision` — pp_ser-generated REGISTER calls pass
  `ppser_realtype` / `ppser_reallength` for `real` fields. The helper
  currently exposes those as fixed constants; the port must let
  `ppser_initialize` update them so single-precision `real` fields
  get registered with the right type metadata.
- `rperturb` — threads through to the read-perturb path in Slice A-2.
- `singlefile`, `archive`, `unique_id` — metadata-only on the
  preserf side; record in root attributes for round-trip fidelity.

(The preprocessor _port_ itself — `src/preserf/preprocessor.py`,
`cli.py`, `errors.py` — already landed in [#6](https://github.com/grAItools/preserf/pull/6).
This spec covers only the open work that remained after that PR.)

## Goal

`ppser_initialize` accepts every keyword pp_ser emits, and the
preprocessor's generated output compiles + runs against the helper
end-to-end on a representative `!$SER`-annotated Fortran source.

## Non-goals

- The preprocessor port itself — already done in #6.
- Implementing read-perturb — Slice A-2 (which depends on this
  slice's `rperturb` threading).
- Backend selector — Slice E (which also threads through this
  signature, but as a separate keyword).

## Success criteria

- `ppser_initialize` accepts every Serialbox-compatible keyword:
  `singlefile`, `mpi_rank`, `rprecision`, `rperturb`, `realtype`,
  `archive`, `unique_id`.
- `mpi_rank` correctly suffixes the store name with `_rank<n>` per
  `storage_mapping.md` §9; parallel runs produce one store per rank.
- `realtype` / `rprecision` update `ppser_realtype` /
  `ppser_reallength` so pp_ser-emitted REGISTER calls pick up
  single-precision real metadata correctly.
- `rperturb` is wired through to `ppser_zrperturb` (consumed by
  Slice A-2's read-perturb).
- `singlefile`, `archive`, `unique_id` are recorded in root
  attributes for round-trip fidelity.
- End-to-end test: run the preprocessor on a representative
  `!$SER`-annotated Fortran source, compile the generated output
  against preserf's helpers, run it, and read the resulting store
  back with `tests/_support/storage.py`.
