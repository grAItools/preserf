"""Round-trip test: Serialbox dump <-> preserf store.

A hand-built ``SerialboxDump`` exercises the full set of metainfo types
(scalar + array, all six TypeIDs minus ``Invalid``), repeated-name
savepoints distinguished by metainfo, heterogeneous fields per savepoint,
and multi-dimensional field data. The same dump is round-tripped through
both supported backends (NetCDF4 file and NCZarr V2 store) and the
reconstructed dump must match the original byte-for-byte for data and
field-for-field for metadata.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import numpy as np
import pytest

if TYPE_CHECKING:
    from pathlib import Path

from preserf._serialbox import (
    FieldMetainfo,
    MetainfoValue,
    Savepoint,
    SerialboxDump,
    TypeID,
)
from preserf._storage import read_dump, write_dump


def _make_dump() -> SerialboxDump:
    dump = SerialboxDump(prefix="toy")

    dump.global_meta_info = {
        "author": MetainfoValue(TypeID.String, "alice"),
        "schema_version": MetainfoValue(TypeID.Int32, 7),
        "wallclock_ns": MetainfoValue(TypeID.Int64, 1_700_000_000_000_000_000),
        "tolerance": MetainfoValue(TypeID.Float64, 1.0e-9),
        "tolerance32": MetainfoValue(TypeID.Float32, 1.0e-3),
        "use_gpu": MetainfoValue(TypeID.Boolean, True),
        "tags": MetainfoValue(TypeID.ArrayOfString, ["alpha", "beta", "gamma"]),
        "shape": MetainfoValue(TypeID.ArrayOfInt32, [4, 3, 2]),
        "weights": MetainfoValue(TypeID.ArrayOfFloat64, [0.1, 0.2, 0.7]),
    }

    dump.field_map = {
        "u": FieldMetainfo(
            type_id=TypeID.Float64,
            dims=[4, 3, 2],
            meta_info={
                "iminushalo": MetainfoValue(TypeID.Int32, 1),
                "iplushalo": MetainfoValue(TypeID.Int32, 1),
                "long_name": MetainfoValue(TypeID.String, "velocity-u"),
            },
        ),
        "nlevels": FieldMetainfo(
            type_id=TypeID.Int32,
            dims=[3],
            meta_info={},
        ),
        "scalar_flag": FieldMetainfo(
            type_id=TypeID.Boolean,
            dims=[1],
            meta_info={},
        ),
    }

    u0 = np.arange(24, dtype=np.float64).reshape(4, 3, 2)
    u1 = (u0 + 100.0).astype(np.float64)
    u2 = (u0 - 50.0).astype(np.float64)
    levels0 = np.array([10, 20, 30], dtype=np.int32)
    levels1 = np.array([11, 22, 33], dtype=np.int32)
    flag0 = np.array([1], dtype=np.int8)

    dump.field_data = {
        "u": {0: u0, 1: u1, 2: u2},
        "nlevels": {0: levels0, 1: levels1},
        "scalar_flag": {0: flag0},
    }

    dump.savepoints = [
        Savepoint(
            name="step",
            meta_info={
                "ntstep": MetainfoValue(TypeID.Int32, 1),
                "t": MetainfoValue(TypeID.Float64, 0.5),
            },
            fields={"u": 0, "nlevels": 0, "scalar_flag": 0},
        ),
        Savepoint(
            name="step",  # same name, different metainfo
            meta_info={
                "ntstep": MetainfoValue(TypeID.Int32, 2),
                "t": MetainfoValue(TypeID.Float64, 1.0),
            },
            fields={"u": 1, "nlevels": 1},  # heterogeneous: no scalar_flag here
        ),
        Savepoint(
            name="extra",
            meta_info={"note": MetainfoValue(TypeID.String, "middle")},
            fields={"u": 2},
        ),
    ]

    # Build a plausible fields_table; offsets will be re-computed on write.
    from preserf._serialbox import FieldOffsetEntry

    for fname, data_by_id in dump.field_data.items():
        dump.fields_table[fname] = [
            FieldOffsetEntry(offset=0, checksum="") for _ in sorted(data_by_id)
        ]

    return dump


# ---------------------------------------------------------------------------
# Equality helpers
# ---------------------------------------------------------------------------


def _assert_metainfo_equal(a, b, ctx: str) -> None:
    assert set(a.keys()) == set(b.keys()), (
        f"{ctx}: metainfo keys differ {set(a)} vs {set(b)}"
    )
    for key in a:
        va, vb = a[key], b[key]
        assert va.type_id == vb.type_id, (
            f"{ctx}[{key}]: type_id {va.type_id} != {vb.type_id}"
        )
        if va.type_id in (TypeID.Float32, TypeID.ArrayOfFloat32):
            np.testing.assert_allclose(
                np.asarray(va.value, dtype=np.float32),
                np.asarray(vb.value, dtype=np.float32),
                rtol=0,
                atol=0,
            )
        else:
            assert va.value == vb.value, f"{ctx}[{key}]: {va.value!r} != {vb.value!r}"


def _assert_dumps_equal(a: SerialboxDump, b: SerialboxDump) -> None:
    assert a.prefix == b.prefix
    _assert_metainfo_equal(a.global_meta_info, b.global_meta_info, "global_meta_info")

    assert set(a.field_map.keys()) == set(b.field_map.keys())
    for fname, fa in a.field_map.items():
        fb = b.field_map[fname]
        assert fa.type_id == fb.type_id, f"field {fname} type"
        assert fa.dims == fb.dims, f"field {fname} dims"
        _assert_metainfo_equal(
            fa.meta_info, fb.meta_info, f"field_map[{fname}].meta_info"
        )

    assert len(a.savepoints) == len(b.savepoints)
    for i, (spa, spb) in enumerate(zip(a.savepoints, b.savepoints, strict=True)):
        assert spa.name == spb.name, f"savepoint {i} name"
        _assert_metainfo_equal(
            spa.meta_info, spb.meta_info, f"savepoints[{i}].meta_info"
        )
        assert spa.fields == spb.fields, (
            f"savepoint {i} fields {spa.fields} vs {spb.fields}"
        )

    assert set(a.field_data.keys()) == set(b.field_data.keys())
    for fname, by_id_a in a.field_data.items():
        by_id_b = b.field_data[fname]
        assert set(by_id_a.keys()) == set(by_id_b.keys()), f"field {fname} ids"
        for fid, arr_a in by_id_a.items():
            arr_b = by_id_b[fid]
            assert arr_a.dtype == arr_b.dtype, f"field {fname}[{fid}] dtype"
            np.testing.assert_array_equal(
                arr_a, arr_b, err_msg=f"field {fname}[{fid}] data"
            )


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("backend", ["netcdf4", "nczarr-v2"])
def test_round_trip(tmp_path: Path, backend: str) -> None:
    """preserf store round-trips a Serialbox dump losslessly."""
    original = _make_dump()
    url = write_dump(original, tmp_path / backend, backend=backend)
    reconstructed = read_dump(url)
    _assert_dumps_equal(original, reconstructed)


def test_serialbox_disk_round_trip(tmp_path: Path) -> None:
    """The SerialboxDump reader/writer itself round-trips through disk.

    Useful sanity check: it ensures our fixture-builder is self-consistent
    before blaming the preserf storage layer for any failure.
    """
    original = _make_dump()
    sb_dir = tmp_path / "serialbox"
    original.write(sb_dir)
    reloaded = SerialboxDump.read(sb_dir, original.prefix)
    _assert_dumps_equal(original, reloaded)
