"""Serialbox on-disk format reader / writer (test-time reference).

Implements the JSON schemas and per-field binary layout used by
Serialbox's ``BinaryArchive``. The data model is mirrored as small
typed dataclasses so it can be round-tripped through the preserf
storage layout (see ``tests._storage``).

Lives under ``tests/`` rather than ``src/preserf/`` because this is a
reference implementation used only by the round-trip test. It depends
on ``numpy``, which is a dev-only dependency, and it is never imported
by preserf's public API or installed entry points.

References (from the cloned Serialbox sources):
* ``src/serialbox/core/Type.h`` for the ``TypeID`` enum.
* ``src/serialbox/core/MetainfoMapImplSerializer.cpp`` for metainfo JSON.
* ``src/serialbox/core/FieldMetainfoImplSerializer.cpp`` for field metadata.
* ``src/serialbox/core/SavepointImplSerializer.cpp`` and
  ``src/serialbox/core/SavepointVectorSerializer.cpp`` for the savepoint vector.
* ``src/serialbox/core/archive/BinaryArchive.cpp`` for the binary archive layout.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from enum import IntEnum
from typing import TYPE_CHECKING, Any

import numpy as np

if TYPE_CHECKING:
    from pathlib import Path


class TypeID(IntEnum):
    Invalid = 0
    Boolean = 1
    Int32 = 2
    Int64 = 3
    Float32 = 4
    Float64 = 5
    String = 6
    Array = 0x10
    ArrayOfBoolean = 0x10 | 1
    ArrayOfInt32 = 0x10 | 2
    ArrayOfInt64 = 0x10 | 3
    ArrayOfFloat32 = 0x10 | 4
    ArrayOfFloat64 = 0x10 | 5
    ArrayOfString = 0x10 | 6


_PRIMITIVE_TO_NUMPY: dict[TypeID, np.dtype[Any]] = {
    TypeID.Boolean: np.dtype(np.int8),
    TypeID.Int32: np.dtype(np.int32),
    TypeID.Int64: np.dtype(np.int64),
    TypeID.Float32: np.dtype(np.float32),
    TypeID.Float64: np.dtype(np.float64),
}


def is_array_type(tid: TypeID) -> bool:
    return bool(int(tid) & int(TypeID.Array))


def primitive_of(tid: TypeID) -> TypeID:
    return TypeID(int(tid) & ~int(TypeID.Array))


def array_of(tid: TypeID) -> TypeID:
    return TypeID(int(tid) | int(TypeID.Array))


def numpy_dtype_for(tid: TypeID) -> np.dtype[Any]:
    """Numpy dtype for a primitive field TypeID. String is not handled here."""
    prim = primitive_of(tid)
    if prim == TypeID.String:
        raise ValueError("string fields are not supported by numpy_dtype_for")
    if prim not in _PRIMITIVE_TO_NUMPY:
        raise ValueError(
            f"TypeID {int(tid)} ({tid.name}) has no numpy dtype mapping; "
            "expected one of Boolean/Int32/Int64/Float32/Float64"
        )
    return _PRIMITIVE_TO_NUMPY[prim]


# ---------------------------------------------------------------------------
# Typed metainfo values
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class MetainfoValue:
    """A single value in a Serialbox metainfo map, tagged with its TypeID."""

    type_id: TypeID
    value: Any

    @classmethod
    def from_json(cls, node: dict[str, Any]) -> MetainfoValue:
        tid = TypeID(int(node["type_id"]))
        raw = node["value"]
        return cls(type_id=tid, value=_coerce_from_json(tid, raw))

    def to_json(self) -> dict[str, Any]:
        return {
            "type_id": int(self.type_id),
            "value": _coerce_to_json(self.type_id, self.value),
        }


def _coerce_from_json(tid: TypeID, raw: Any) -> Any:
    prim = primitive_of(tid)
    if is_array_type(tid):
        if prim == TypeID.String:
            return [str(v) for v in raw]
        return [_coerce_scalar(prim, v) for v in raw]
    return _coerce_scalar(prim, raw)


def _coerce_scalar(prim: TypeID, raw: Any) -> Any:
    if prim == TypeID.Boolean:
        return bool(raw)
    if prim in (TypeID.Int32, TypeID.Int64):
        return int(raw)
    if prim in (TypeID.Float32, TypeID.Float64):
        return float(raw)
    if prim == TypeID.String:
        return str(raw)
    raise ValueError(f"unsupported primitive TypeID: {prim!r}")


def _coerce_to_json(tid: TypeID, value: Any) -> Any:
    prim = primitive_of(tid)
    if is_array_type(tid):
        if prim == TypeID.String:
            return [str(v) for v in value]
        return [_to_json_scalar(prim, v) for v in value]
    return _to_json_scalar(prim, value)


def _to_json_scalar(prim: TypeID, value: Any) -> Any:
    if prim == TypeID.Boolean:
        return bool(value)
    if prim in (TypeID.Int32, TypeID.Int64):
        return int(value)
    if prim in (TypeID.Float32, TypeID.Float64):
        return float(value)
    if prim == TypeID.String:
        return str(value)
    raise ValueError(f"unsupported primitive TypeID: {prim!r}")


MetainfoMap = dict[str, MetainfoValue]


def metainfo_from_json(node: dict[str, Any] | None) -> MetainfoMap:
    if not node:
        return {}
    return {key: MetainfoValue.from_json(sub) for key, sub in node.items()}


def metainfo_to_json(mi: MetainfoMap) -> dict[str, Any]:
    return {key: val.to_json() for key, val in mi.items()}


# ---------------------------------------------------------------------------
# Field metainfo, Savepoint, Serializer
# ---------------------------------------------------------------------------


@dataclass
class FieldMetainfo:
    type_id: TypeID
    dims: list[int]
    meta_info: MetainfoMap = field(default_factory=dict)

    @classmethod
    def from_json(cls, node: dict[str, Any]) -> FieldMetainfo:
        return cls(
            type_id=TypeID(int(node["type_id"])),
            dims=[int(d) for d in node["dims"]],
            meta_info=metainfo_from_json(node.get("meta_info")),
        )

    def to_json(self) -> dict[str, Any]:
        return {
            "type_id": int(self.type_id),
            "dims": list(self.dims),
            "meta_info": metainfo_to_json(self.meta_info),
        }

    def element_dtype(self) -> np.dtype[Any]:
        return numpy_dtype_for(self.type_id)

    def element_count(self) -> int:
        n = 1
        for d in self.dims:
            n *= int(d)
        return n


@dataclass
class Savepoint:
    name: str
    meta_info: MetainfoMap = field(default_factory=dict)
    # field-name -> per-field fieldID (index into BinaryArchive offset table)
    fields: dict[str, int] = field(default_factory=dict)


@dataclass
class FieldOffsetEntry:
    offset: int
    checksum: str


@dataclass
class SerialboxDump:
    """In-memory representation of a Serialbox dump on disk."""

    prefix: str
    serialbox_version: int = 200  # 100*MAJ + 10*MIN + PATCH
    global_meta_info: MetainfoMap = field(default_factory=dict)
    savepoints: list[Savepoint] = field(default_factory=list)
    field_map: dict[str, FieldMetainfo] = field(default_factory=dict)

    # Archive metadata (BinaryArchive)
    archive_name: str = "Binary"
    archive_version: int = 0
    hash_algorithm: str = "MD5"
    # field -> ordered list of (offset, checksum)
    fields_table: dict[str, list[FieldOffsetEntry]] = field(default_factory=dict)

    # Raw data: field -> id -> numpy array
    field_data: dict[str, dict[int, np.ndarray]] = field(default_factory=dict)

    # Metadata-only `!$SER INIT` keywords pp_ser passes through, recorded
    # by the Fortran helper in the `_preserf_*` root attribute namespace
    # (Slice D Phase 3). `archive` here is the INIT `archive=` keyword and
    # is distinct from `archive_name` above, which comes from the Serialbox
    # ArchiveMetaData JSON path. Defaults match the Fortran PPSER_DEFAULT_*
    # constants so older stores lacking the attrs decode to the same values.
    singlefile: bool = False
    archive: str = "Binary"
    unique_id: int = 0

    # `!$SER OPTION verbosity=` value (Slice C / ADR 0003 §4), recorded by
    # the Fortran helper as the reserved `_preserf_option_verbosity` root
    # attribute. None when the option was never set.
    option_verbosity: int | None = None

    # ---- Tracers (Slice C / ADR 0003, storage_mapping.md §4a) ----
    # Tracer descriptors mirror /_fields entries (type_id + dims via
    # FieldMetainfo); tracer_stype / tracer_index carry the two extra
    # /_tracers attributes. Per-savepoint tracer snapshots are keyed by
    # savepoint index (one snapshot per (savepoint, tracer), last-wins per
    # ADR 0003 §2); tracer_timelevel records the optional integer timelevel
    # from `!$SER TRACER ...@<tl>` (None when the write carried none).
    tracer_map: dict[str, FieldMetainfo] = field(default_factory=dict)
    tracer_stype: dict[str, str] = field(default_factory=dict)
    tracer_index: dict[str, int] = field(default_factory=dict)
    tracer_data: dict[str, dict[int, np.ndarray]] = field(default_factory=dict)
    tracer_timelevel: dict[str, dict[int, int | None]] = field(default_factory=dict)

    # ---- I/O ----

    @classmethod
    def read(cls, directory: Path, prefix: str) -> SerialboxDump:
        with (directory / f"MetaData-{prefix}.json").open(encoding="utf-8") as f:
            meta = json.load(f)
        with (directory / f"ArchiveMetaData-{prefix}.json").open(encoding="utf-8") as f:
            arch = json.load(f)

        sv = meta.get("savepoint_vector", {}) or {}
        sp_nodes = sv.get("savepoints", []) or []
        fps_nodes = sv.get("fields_per_savepoint", []) or []

        savepoints: list[Savepoint] = []
        for idx, sp_node in enumerate(sp_nodes):
            name = sp_node["name"]
            sp = Savepoint(
                name=name, meta_info=metainfo_from_json(sp_node.get("meta_info"))
            )
            if idx < len(fps_nodes):
                inner = fps_nodes[idx].get(name)
                if inner:
                    sp.fields = {k: int(v) for k, v in inner.items()}
            savepoints.append(sp)

        field_map = {
            name: FieldMetainfo.from_json(node)
            for name, node in (meta.get("field_map") or {}).items()
        }

        fields_table: dict[str, list[FieldOffsetEntry]] = {}
        for fname, entries in (arch.get("fields_table") or {}).items():
            fields_table[fname] = [
                FieldOffsetEntry(offset=int(e[0]), checksum=str(e[1])) for e in entries
            ]

        dump = cls(
            prefix=str(meta.get("prefix", prefix)),
            serialbox_version=int(meta.get("serialbox_version", 200)),
            global_meta_info=metainfo_from_json(meta.get("global_meta_info")),
            savepoints=savepoints,
            field_map=field_map,
            archive_name=str(arch.get("archive_name", "Binary")),
            archive_version=int(arch.get("archive_version", 0)),
            hash_algorithm=str(arch.get("hash_algorithm", "MD5")),
            fields_table=fields_table,
        )

        # Slurp raw .dat blobs into numpy arrays using FieldMap dims.
        for fname, entries in fields_table.items():
            info = field_map.get(fname)
            if info is None:
                raise ValueError(f"field '{fname}' missing from field_map")
            dtype = info.element_dtype()
            shape = tuple(int(d) for d in info.dims)
            elt_count = info.element_count()
            elt_bytes = dtype.itemsize * elt_count
            path = directory / f"{prefix}_{fname}.dat"
            blob = path.read_bytes()
            dump.field_data[fname] = {}
            for idx, entry in enumerate(entries):
                buf = blob[entry.offset : entry.offset + elt_bytes]
                if len(buf) != elt_bytes:
                    raise ValueError(
                        f"truncated read for field {fname}: got {len(buf)} bytes, "
                        f"need {elt_bytes}"
                    )
                arr = (
                    np.frombuffer(buf, dtype=dtype).reshape(shape)
                    if shape
                    else np.frombuffer(buf, dtype=dtype).reshape(())
                )
                dump.field_data[fname][idx] = arr.copy()

        return dump

    def write(self, directory: Path) -> None:
        directory.mkdir(parents=True, exist_ok=True)
        meta = {
            "serialbox_version": int(self.serialbox_version),
            "prefix": self.prefix,
            "global_meta_info": metainfo_to_json(self.global_meta_info),
            "savepoint_vector": {
                "savepoints": [
                    {"name": sp.name, "meta_info": metainfo_to_json(sp.meta_info)}
                    for sp in self.savepoints
                ],
                "fields_per_savepoint": [
                    {sp.name: (dict(sp.fields) if sp.fields else None)}
                    for sp in self.savepoints
                ],
            },
            "field_map": {
                name: info.to_json() for name, info in self.field_map.items()
            },
        }
        arch = {
            "serialbox_version": int(self.serialbox_version),
            "archive_name": self.archive_name,
            "archive_version": int(self.archive_version),
            "hash_algorithm": self.hash_algorithm,
            "fields_table": {
                fname: [[entry.offset, entry.checksum] for entry in entries]
                for fname, entries in self.fields_table.items()
            },
        }
        (directory / f"MetaData-{self.prefix}.json").write_text(
            json.dumps(meta, indent=2), encoding="utf-8"
        )
        (directory / f"ArchiveMetaData-{self.prefix}.json").write_text(
            json.dumps(arch, indent=2), encoding="utf-8"
        )

        # Re-pack the .dat blobs in fieldID order, computing offsets as we go.
        for fname, info in self.field_map.items():
            data_by_id = self.field_data.get(fname, {})
            if not data_by_id:
                continue
            ordered_ids = sorted(data_by_id.keys())
            # Serialbox guarantees fieldIDs are dense 0..N-1 (BinaryArchive.cpp:323
            # assigns id = fieldOffsetTable.size() on each append). Refuse to
            # write malformed sparse maps loudly instead of silently leaving
            # zero-offset placeholders behind.
            if ordered_ids != list(range(len(ordered_ids))):
                raise ValueError(
                    f"field '{fname}' has non-dense fieldIDs {ordered_ids}; "
                    f"Serialbox requires 0..{len(ordered_ids) - 1}"
                )
            expected_count = info.element_count()
            payload = bytearray()
            offsets: list[int] = []
            for fid in ordered_ids:
                offsets.append(len(payload))
                raw = data_by_id[fid]
                if raw.size != expected_count:
                    raise ValueError(
                        f"field '{fname}' snapshot {fid} has size {raw.size} "
                        f"but FieldMetainfo declares dims {info.dims} "
                        f"({expected_count} elements)"
                    )
                arr = np.ascontiguousarray(raw, dtype=info.element_dtype())
                payload += arr.tobytes(order="C")
            # Rebuild fields_table from ordered_ids so it exactly reflects the
            # on-disk layout we just wrote — stale entries left over from a
            # previous larger payload would otherwise mislead the reader into
            # expecting more snapshots than the .dat file actually contains.
            prior = {i: e for i, e in enumerate(self.fields_table.get(fname, []))}
            self.fields_table[fname] = [
                FieldOffsetEntry(
                    offset=off,
                    checksum=prior[fid].checksum if fid in prior else "",
                )
                for fid, off in zip(ordered_ids, offsets, strict=True)
            ]
            (directory / f"{self.prefix}_{fname}.dat").write_bytes(bytes(payload))

        # Re-write archive metadata now that offsets are final.
        arch["fields_table"] = {
            fname: [[entry.offset, entry.checksum] for entry in entries]
            for fname, entries in self.fields_table.items()
        }
        (directory / f"ArchiveMetaData-{self.prefix}.json").write_text(
            json.dumps(arch, indent=2), encoding="utf-8"
        )
