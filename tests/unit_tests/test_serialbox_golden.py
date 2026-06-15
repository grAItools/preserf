"""Decode a real Serialbox dump with preserf's reference reader (issue #68).

``tests/_support/serialbox.py`` is a hand re-implementation of Serialbox's
JSON metadata + ``BinaryArchive`` on-disk format. Validated only by a
self-round-trip, a writer + reader that agreed on a *wrong* interpretation of
the format would still pass. This test pins the reader against external
ground truth: a small dump produced by upstream Serialbox (``serialbox4py``
2.6.3), committed under ``tests/_support/fixtures/serialbox_golden/`` together
with the script and provenance notes that generated it.

The fixture deliberately includes a multi-dimensional, multi-snapshot field
(``u``); decoding it correctly requires honouring Serialbox's column-major
on-disk element order, which a naive C-order reshape gets wrong for rank >= 2
fields. The expected values below are exactly what the upstream Serialbox
reader returns for the same dump.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from tests._support.serialbox import SerialboxDump, TypeID

GOLDEN_DIR = (
    Path(__file__).resolve().parent.parent
    / "_support"
    / "fixtures"
    / "serialbox_golden"
)
GOLDEN_PREFIX = "golden"


def test_serialbox_reader_decodes_golden_dump() -> None:
    """preserf's Serialbox reader decodes a real upstream dump correctly."""
    dump = SerialboxDump.read(GOLDEN_DIR, GOLDEN_PREFIX)

    # --- top-level provenance metadata -------------------------------------
    assert dump.prefix == GOLDEN_PREFIX
    assert dump.serialbox_version == 263  # Serialbox 2.6.3
    assert dump.archive_name == "Binary"
    assert dump.hash_algorithm == "SHA256"

    # --- global metainfo: mixed scalar types + ArrayOfString ---------------
    gm = dump.global_meta_info
    assert gm["author"].type_id == TypeID.String
    assert gm["author"].value == "serialbox-golden"
    assert gm["schema_version"].type_id == TypeID.Int32
    assert gm["schema_version"].value == 7
    assert gm["use_gpu"].type_id == TypeID.Boolean
    assert gm["use_gpu"].value is True
    assert gm["tags"].type_id == TypeID.ArrayOfString
    assert gm["tags"].value == ["alpha", "beta", "gamma"]

    # --- field registry: mixed dtypes / ranks ------------------------------
    assert set(dump.field_map) == {"u", "nlevels", "ftol"}
    assert dump.field_map["u"].type_id == TypeID.Float64
    assert dump.field_map["u"].dims == [4, 3, 2]
    assert dump.field_map["nlevels"].type_id == TypeID.Int32
    assert dump.field_map["nlevels"].dims == [3]
    assert dump.field_map["ftol"].type_id == TypeID.Float32
    assert dump.field_map["ftol"].dims == [2]

    # --- savepoint vector: two savepoints sharing a name -------------------
    assert [sp.name for sp in dump.savepoints] == ["step", "step"]
    sp0, sp1 = dump.savepoints
    assert sp0.meta_info["ntstep"].value == 1
    assert sp0.meta_info["t"].value == 0.5
    assert sp0.fields == {"u": 0, "nlevels": 0}
    assert sp1.meta_info["ntstep"].value == 2
    assert sp1.meta_info["t"].value == 1.0
    assert sp1.fields == {"u": 1, "ftol": 0}

    # --- field data: the multi-dim, multi-snapshot field is the crux -------
    # Upstream Serialbox reads `u` snapshot 0 back as arange(24).reshape(4,3,2)
    # and snapshot 1 as that plus 100. A C-order reshape of the column-major
    # .dat blob would transpose these (the bug this fixture exists to catch).
    expected_u = np.arange(24, dtype=np.float64).reshape(4, 3, 2)
    np.testing.assert_array_equal(dump.field_data["u"][0], expected_u)
    np.testing.assert_array_equal(dump.field_data["u"][1], expected_u + 100.0)
    assert dump.field_data["u"][0].dtype == np.float64

    np.testing.assert_array_equal(
        dump.field_data["nlevels"][0], np.array([10, 20, 30], dtype=np.int32)
    )
    np.testing.assert_array_equal(
        dump.field_data["ftol"][0], np.array([1.5, 2.5], dtype=np.float32)
    )


def test_golden_dump_disk_round_trips_through_reference_writer() -> None:
    """Re-writing the decoded golden dump reproduces byte-identical payloads.

    The reference writer must lay the multi-dimensional `u` field back out in
    the same column-major order upstream Serialbox used; comparing the raw
    `.dat` bytes guards the write path symmetrically with the read assertions
    above (a C-order write would silently transpose rank >= 2 fields).
    """
    import tempfile

    dump = SerialboxDump.read(GOLDEN_DIR, GOLDEN_PREFIX)
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp)
        dump.write(out)
        for fname in ("u", "nlevels", "ftol"):
            original = (GOLDEN_DIR / f"{GOLDEN_PREFIX}_{fname}.dat").read_bytes()
            rewritten = (out / f"{GOLDEN_PREFIX}_{fname}.dat").read_bytes()
            assert rewritten == original, (
                f"field '{fname}' .dat payload changed on rewrite"
            )
