# Spec Delta

## Purpose

Extend opt-in compression to the nczarr-v2 backend via a Zarr codec, removing the up-front rejection, so both storage backends support compressed field writes.

## MODIFIED Requirements

### Requirement: Variable storage layout

Store variables SHALL support opt-in chunked and compressed storage on both backends: when a store-wide compression level is requested through the `ppser_initialize` keyword (or the `PRESERF_COMPRESSION` env var), field and tracer data variables SHALL be created as chunked, compressed variables — deflated on the `netcdf4` backend, carrying a Zarr codec recorded in the array metadata on `nczarr-v2` — with a chunk shape derived from the registered dims and bounded, while stores created without a compression request SHALL remain contiguous and uncompressed so existing stores are byte-identical.

#### Scenario: Default store unchanged

- **WHEN** a store is initialized without a compression request
- **THEN** the store variable is created contiguous and uncompressed, matching existing stores

#### Scenario: Compressed store round-trips

- **WHEN** a store is initialized with a compression request and a field is written
- **THEN** the store variable is chunked and compressed, and the field round-trips through the Python support reader with identical values

#### Scenario: NCZarr compressed round-trip

- **WHEN** `compression>0` is combined with `backend=nczarr-v2`
- **THEN** the store is written with a codec recorded in the Zarr array metadata and round-trips losslessly, rather than aborting at initialization
