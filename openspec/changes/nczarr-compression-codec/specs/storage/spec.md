# Spec Delta

## Purpose

Extend opt-in compression to the nczarr-v2 backend via a Zarr codec, removing the up-front rejection, so both storage backends support compressed field writes.

## MODIFIED Requirements

### Requirement: Compressed variable layout

Store variables SHALL support opt-in chunked and compressed storage on both backends: when a store-wide compression level is requested through the `ppser_initialize` keyword (or the `PRESERF_COMPRESSION` env var), field and tracer data variables SHALL be created as chunked, compressed variables — deflated on the `netcdf4` backend, carrying a Zarr codec recorded in the array metadata on `nczarr-v2` — with a chunk shape derived from the registered dims.

#### Scenario: Compressed store round-trips

- **WHEN** a store is initialized with a compression request and a multi-element field is written
- **THEN** the store variable is chunked with a bounded (not whole-variable) chunk shape and compressed, and the field round-trips through the Python support reader with identical values

#### Scenario: NCZarr compressed round-trip

- **WHEN** `compression>0` is combined with `backend=nczarr-v2`
- **THEN** the store is written with a codec recorded in the Zarr array metadata and round-trips losslessly, rather than aborting at initialization

### Requirement: Bounded chunk shape

Chunk shapes created under a compression request SHALL be bounded on both backends: no chunk may exceed 4 GiB of uncompressed data (the cap the base `Bounded chunk shape` requirement also enforces; Zarr chunk sizes are not governed by the HDF5 per-chunk limit, so the shared bound is this byte cap), and whole-variable chunks are not permitted except for single-element variables, where the only legal chunk is the whole variable.

#### Scenario: Huge dims derive a bounded chunk shape

- **WHEN** the registered dims would make the whole variable exceed 4 GiB of uncompressed data
- **THEN** the derived chunk shape stays under the byte cap and is not the whole variable

### Requirement: Uncompressed scalar fields

Rank-0 (scalar) fields SHALL remain uncompressed with the backend's default layout (netCDF cannot chunk a scalar).

#### Scenario: Scalar fields stay uncompressed

- **WHEN** a store is initialized with a compression request and a rank-0 (scalar) field is written
- **THEN** the scalar variable is created with the backend's default layout, uncompressed, and round-trips identically

### Requirement: Default store layout

Stores created without a compression request SHALL keep the backend's default layout — contiguous on the `netcdf4` backend, the backend's default chunking on `nczarr-v2` — and stay uncompressed, so existing stores are byte-identical.

#### Scenario: Default store unchanged

- **WHEN** a store is initialized without a compression request and a field is written
- **THEN** the store variable is created with the backend's default layout — contiguous and uncompressed on `netcdf4`, the backend's default chunking, uncompressed, on `nczarr-v2` — matching existing stores
