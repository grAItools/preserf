"""preserf storage layout (group-per-savepoint) on NetCDF4 / NCZarr V2.

Implements the schema documented in
``development/references/storage_mapping.md``. Driven by ``netCDF4`` so the
same code path produces either a NetCDF4/HDF5 file or a Zarr V2 store via
NCZarr (selected by the URL / mode string).

This module is a Python reference implementation used by the round-trip
test. The eventual Fortran helper module mirrors this layout via
``netcdf-fortran``.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any, Literal

import netCDF4 as nc
import numpy as np

if TYPE_CHECKING:
    from pathlib import Path

from ._serialbox import (
    FieldMetainfo,
    MetainfoMap,
    MetainfoValue,
    Savepoint,
    SerialboxDump,
    TypeID,
    array_of,
    is_array_type,
    numpy_dtype_for,
    primitive_of,
)

SCHEMA_VERSION = 1


_PRIMITIVE_DTYPE: dict[TypeID, np.dtype[Any]] = {
    TypeID.Boolean: np.dtype(np.int8),
    TypeID.Int32: np.dtype(np.int32),
    TypeID.Int64: np.dtype(np.int64),
    TypeID.Float32: np.dtype(np.float32),
    TypeID.Float64: np.dtype(np.float64),
}


NetCDFFormat = Literal[
    "NETCDF4",
    "NETCDF4_CLASSIC",
    "NETCDF3_CLASSIC",
    "NETCDF3_64BIT_OFFSET",
    "NETCDF3_64BIT_DATA",
]


def open_url_for(
    directory: Path, prefix: str, backend: str
) -> tuple[str, NetCDFFormat]:
    """Return (url, format) tuple for a backend choice.

    ``backend`` is one of ``"netcdf4"`` or ``"nczarr-v2"``. The returned
    ``url`` is what gets passed to ``netCDF4.Dataset(...)``.
    """
    directory.mkdir(parents=True, exist_ok=True)
    if backend == "netcdf4":
        return str(directory / f"{prefix}.nc"), "NETCDF4"
    if backend == "nczarr-v2":
        store = (directory / f"{prefix}.zarr").resolve()
        # Use as_uri() so the URL is well-formed on Windows too
        # (file:///C:/... rather than the broken file://C:\...).
        return f"{store.as_uri()}#mode=nczarr,zarr2", "NETCDF4"
    raise ValueError(f"unknown backend: {backend!r}")


# ---------------------------------------------------------------------------
# Metainfo <-> netCDF attribute encoding
# ---------------------------------------------------------------------------


def _set_typed_attr(
    target: nc.Dataset | nc.Group | nc.Variable[Any], key: str, mv: MetainfoValue
) -> None:
    """Write a Serialbox MetainfoValue as a typed netCDF attribute.

    Strategy: write the value with an explicit numpy dtype (so netCDF stores
    the correct nc type), and shadow it with ``<key>__preserf_type_id``
    holding the Serialbox TypeID so the original distinction (e.g. Int32 vs
    Int64) round-trips losslessly through both backends.
    """
    prim = primitive_of(mv.type_id)
    if prim == TypeID.Invalid:
        raise ValueError(
            f"metainfo key '{key}' has TypeID.Invalid; this is not serialisable"
        )
    if prim == TypeID.String:
        # netCDF strings: store scalars as plain str, arrays as Python lists
        # of str (netCDF4 stores them as NC_STRING vector).
        if is_array_type(mv.type_id):
            target.setncattr(key, list(mv.value))
        else:
            target.setncattr(key, str(mv.value))
    else:
        if prim not in _PRIMITIVE_DTYPE:
            raise ValueError(
                f"metainfo key '{key}' has unsupported TypeID "
                f"{int(mv.type_id)} ({mv.type_id.name})"
            )
        dtype = _PRIMITIVE_DTYPE[prim]
        if is_array_type(mv.type_id):
            arr = np.asarray(mv.value, dtype=dtype)
            target.setncattr(key, arr)
        else:
            target.setncattr(key, dtype.type(mv.value))
    target.setncattr(f"{key}__preserf_type_id", np.int32(int(mv.type_id)))


def _read_typed_attr(
    target: nc.Dataset | nc.Group | nc.Variable[Any], key: str
) -> MetainfoValue:
    type_attr = f"{key}__preserf_type_id"
    if type_attr not in target.ncattrs():
        raise ValueError(f"attribute '{key}' has no '{type_attr}' tag")
    tid = TypeID(int(target.getncattr(type_attr)))
    raw = target.getncattr(key)
    prim = primitive_of(tid)
    if prim == TypeID.String:
        if is_array_type(tid):
            value: Any = [str(v) for v in raw]
        else:
            value = str(raw)
    elif is_array_type(tid):
        value = [_scalar_python(prim, v) for v in np.atleast_1d(raw).tolist()]
    else:
        # Scalar; netCDF4 may return a numpy scalar or a 0-d array.
        scalar = raw.item() if isinstance(raw, np.generic) else raw
        if isinstance(scalar, np.ndarray):
            scalar = scalar.item()
        value = _scalar_python(prim, scalar)
    return MetainfoValue(type_id=tid, value=value)


def _scalar_python(prim: TypeID, raw: Any) -> Any:
    if prim == TypeID.Boolean:
        return bool(raw)
    if prim in (TypeID.Int32, TypeID.Int64):
        return int(raw)
    if prim in (TypeID.Float32, TypeID.Float64):
        return float(raw)
    if prim == TypeID.String:
        return str(raw)
    raise ValueError(f"unsupported primitive TypeID: {prim!r}")


def _write_metainfo_attrs(
    target: nc.Dataset | nc.Group | nc.Variable[Any],
    mi: MetainfoMap,
    reserved: frozenset[str] = frozenset(),
) -> None:
    for key, val in mi.items():
        if key.startswith("_preserf_") or key.endswith("__preserf_type_id"):
            raise ValueError(
                f"user metainfo key '{key}' collides with reserved namespace "
                "(prefix '_preserf_' or suffix '__preserf_type_id')"
            )
        if key in reserved:
            raise ValueError(
                f"user metainfo key '{key}' collides with a reserved "
                f"schema attribute name ({sorted(reserved)})"
            )
        _set_typed_attr(target, key, val)


_RESERVED_FIELD_REGISTRY = frozenset({"type_id", "dims"})
_RESERVED_SAVEPOINT = frozenset({"name"})


def _read_metainfo_attrs(
    target: nc.Dataset | nc.Group | nc.Variable[Any],
    reserved: frozenset[str] = frozenset(),
) -> MetainfoMap:
    out: MetainfoMap = {}
    for name in target.ncattrs():
        if name.startswith("_preserf_") or name.endswith("__preserf_type_id"):
            continue
        if name in reserved:
            continue
        out[name] = _read_typed_attr(target, name)
    return out


# ---------------------------------------------------------------------------
# Writer
# ---------------------------------------------------------------------------


def write_dump(dump: SerialboxDump, directory: Path, *, backend: str) -> str:
    """Translate a SerialboxDump into a preserf store.

    Returns the URL that was opened (useful for re-opening in tests).
    """
    url, fmt = open_url_for(directory, dump.prefix, backend)
    root = nc.Dataset(url, "w", format=fmt)
    try:
        root.setncattr("_preserf_schema_version", np.int32(SCHEMA_VERSION))
        root.setncattr("_preserf_serialbox_prefix", str(dump.prefix))
        root.setncattr("_preserf_savepoint_count", np.int32(len(dump.savepoints)))
        root.setncattr("_preserf_writer", "preserf round-trip test 0.1")
        _write_metainfo_attrs(root, dump.global_meta_info)

        fields_grp = root.createGroup("_fields")
        for fname, info in dump.field_map.items():
            _write_field_registry(fields_grp, fname, info)

        savepoints_grp = root.createGroup("savepoints")
        for idx, sp in enumerate(dump.savepoints):
            _write_savepoint(savepoints_grp, idx, sp, dump)
    finally:
        root.close()
    return url


def _write_field_registry(parent: nc.Group, fname: str, info: FieldMetainfo) -> None:
    var = parent.createVariable(fname, "i4", ())
    var[...] = np.int32(0)
    var.setncattr("type_id", np.int32(int(info.type_id)))
    var.setncattr("dims", np.asarray(info.dims, dtype=np.int32))
    _write_metainfo_attrs(var, info.meta_info, reserved=_RESERVED_FIELD_REGISTRY)


_SAVEPOINT_INDEX_LIMIT = 1_000_000  # see storage_mapping.md §5


def _write_savepoint(
    parent: nc.Group, idx: int, sp: Savepoint, dump: SerialboxDump
) -> None:
    if idx >= _SAVEPOINT_INDEX_LIMIT:
        raise ValueError(
            f"savepoint index {idx} exceeds the schema cap of "
            f"{_SAVEPOINT_INDEX_LIMIT}; bump _preserf_schema_version to widen"
        )
    name = f"sp_{idx:06d}"
    grp = parent.createGroup(name)
    grp.setncattr("_preserf_savepoint_index", np.int32(idx))
    grp.setncattr("name", sp.name)
    _write_metainfo_attrs(grp, sp.meta_info, reserved=_RESERVED_SAVEPOINT)

    if sp.fields:
        field_id_pairs: list[str] = []
        for fname, fid in sp.fields.items():
            info = dump.field_map[fname]
            arr = dump.field_data.get(fname, {}).get(fid)
            if arr is None:
                raise ValueError(
                    f"savepoint #{idx} references field '{fname}' id={fid} "
                    "with no data in the dump"
                )
            _write_field_variable(grp, fname, info, arr)
            field_id_pairs.extend([fname, str(fid)])
        grp.setncattr("_preserf_field_ids", field_id_pairs)


def _write_field_variable(
    grp: nc.Group, fname: str, info: FieldMetainfo, data: np.ndarray
) -> None:
    dtype = numpy_dtype_for(info.type_id)
    expected_count = info.element_count()
    if data.size != expected_count:
        raise ValueError(
            f"field '{fname}' write got array of size {data.size} (shape "
            f"{data.shape}) but FieldMetainfo declares dims {info.dims} "
            f"({expected_count} elements)"
        )
    dim_names: list[str] = []
    for axis, size in enumerate(info.dims):
        dname = f"{fname}_dim{axis}"
        if dname not in grp.dimensions:
            grp.createDimension(dname, int(size))
        dim_names.append(dname)
    if not dim_names:
        # 0-D / scalar variable.
        var = grp.createVariable(fname, dtype, ())
        var[...] = data.astype(dtype, copy=False)
    else:
        var = grp.createVariable(fname, dtype, tuple(dim_names))
        var[...] = data.astype(dtype, copy=False).reshape([int(d) for d in info.dims])


# ---------------------------------------------------------------------------
# Reader
# ---------------------------------------------------------------------------


def read_dump(url: str) -> SerialboxDump:
    root = nc.Dataset(url, "r")
    try:
        if "_preserf_schema_version" not in root.ncattrs():
            raise ValueError(
                f"{url}: missing required '_preserf_schema_version' attribute; "
                "this does not look like a preserf store"
            )
        version = int(root.getncattr("_preserf_schema_version"))
        if version != SCHEMA_VERSION:
            raise ValueError(
                f"{url}: unsupported preserf schema version {version}; "
                f"this build supports version {SCHEMA_VERSION}"
            )
        prefix = str(root.getncattr("_preserf_serialbox_prefix"))
        dump = SerialboxDump(prefix=prefix)
        dump.global_meta_info = _read_metainfo_attrs(root)

        fields_grp = root.groups["_fields"]
        for fname, var in fields_grp.variables.items():
            tid = TypeID(int(var.getncattr("type_id")))
            dims_attr = var.getncattr("dims")
            dims = [int(d) for d in np.atleast_1d(dims_attr).tolist()]
            info = FieldMetainfo(
                type_id=tid,
                dims=dims,
                meta_info=_read_metainfo_attrs(var, reserved=_RESERVED_FIELD_REGISTRY),
            )
            dump.field_map[fname] = info

        # Build savepoints in index order; group names are sorted lexically.
        sp_grp = root.groups["savepoints"]
        for name in sorted(sp_grp.groups):
            grp = sp_grp.groups[name]
            sp = Savepoint(
                name=str(grp.getncattr("name")),
                meta_info=_read_metainfo_attrs(grp, reserved=_RESERVED_SAVEPOINT),
            )
            field_ids_attr = (
                grp.getncattr("_preserf_field_ids")
                if "_preserf_field_ids" in grp.ncattrs()
                else None
            )
            id_map: dict[str, int] = {}
            if field_ids_attr is not None:
                flat = list(field_ids_attr)
                if len(flat) % 2 != 0:
                    raise ValueError(
                        f"savepoint '{name}': _preserf_field_ids has odd "
                        f"length {len(flat)}; expected pairs of (fieldname, id)"
                    )
                for i in range(0, len(flat), 2):
                    id_map[str(flat[i])] = int(flat[i + 1])

            for fname, var in grp.variables.items():
                info = dump.field_map[fname]
                arr = np.asarray(var[...]).astype(info.element_dtype(), copy=False)
                if info.dims:
                    arr = arr.reshape([int(d) for d in info.dims])
                fid = id_map.get(fname, len(dump.field_data.get(fname, {})))
                sp.fields[fname] = fid
                dump.field_data.setdefault(fname, {})[fid] = arr
            dump.savepoints.append(sp)
    finally:
        root.close()

    # Reconstruct fields_table with offsets computed in fieldID order.
    for fname, info in dump.field_map.items():
        data_by_id = dump.field_data.get(fname, {})
        if not data_by_id:
            continue
        ordered_ids = sorted(data_by_id.keys())
        entries = []
        offset = 0
        elt_bytes = info.element_dtype().itemsize * info.element_count()
        for _fid in ordered_ids:
            entries.append((offset, ""))
            offset += elt_bytes
        from ._serialbox import FieldOffsetEntry

        dump.fields_table[fname] = [
            FieldOffsetEntry(offset=o, checksum=c) for (o, c) in entries
        ]
    return dump


__all__ = [
    "SCHEMA_VERSION",
    "array_of",  # re-exported for callers
    "open_url_for",
    "read_dump",
    "write_dump",
]
