# Spec Delta

## Purpose

Extend opt-in compression to the nczarr-v2 backend via a Zarr codec, removing the up-front rejection, so both storage backends support compressed field writes.

## MODIFIED Requirements

### Requirement: Variable storage layout

Store variables SHALL support opt-in chunked and compressed storage on both backends: a field registered with a compression request SHALL be created as a chunked, compressed variable — deflated on the `netcdf4` backend, carrying a Zarr codec recorded in the array metadata on `nczarr-v2` — while default registrations SHALL remain contiguous and uncompressed so existing stores are byte-identical.

#### Scenario: Default registration unchanged

- **WHEN** a field is registered without a compression request
- **THEN** the store variable is created contiguous and uncompressed, matching existing stores

#### Scenario: Compressed registration round-trips

- **WHEN** a field is registered through the Fortran registration API with a compression request and written
- **THEN** the store variable is chunked and compressed, and the field round-trips through the Python support reader with identical values

#### Scenario: NCZarr compressed round-trip

- **WHEN** `compression>0` is combined with `backend=nczarr-v2`
- **THEN** the store is written with a codec recorded in the Zarr array metadata and round-trips losslessly, rather than aborting at initialization
