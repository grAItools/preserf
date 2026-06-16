#!/usr/bin/env python3
"""Regenerate the golden Serialbox dump under this directory.

This script produces a *real* Serialbox ``BinaryArchive`` dump using the
upstream Python bindings (``serialbox4py``), NOT preserf's reimplementation
in ``tests/_support/serialbox.py``. The committed output is the external
ground truth that ``test_serialbox_reader_decodes_golden_dump`` decodes — it
is what guards preserf's reader against agreeing with its own writer on a
wrong interpretation of the format (issue #68).

Provenance
----------
* Producer:      serialbox4py (GridTools/serialbox) — the upstream C++
                 Serialbox runtime exposed through its Python bindings.
* Version:       Serialbox 2.6.3 (``serialbox4py==2.6.3`` from PyPI;
                 ``serialbox_version`` field in the JSON reads ``263``).
* Archive:       ``Binary`` (BinaryArchive), ``hash_algorithm = SHA256``.

How it was generated (one-off, NOT part of `pixi`)
--------------------------------------------------
``serialbox4py`` is a heavy, prebuilt-binary, non-preserf dependency and is
deliberately NOT added to ``pixi.toml``; the fixture is committed instead so
the test suite needs no network or extra toolchain. To regenerate (e.g. to
bump the Serialbox version), in a throwaway environment::

    pip install serialbox4py==2.6.3 numpy
    python tests/_support/fixtures/serialbox_golden/generate_golden.py \
        tests/_support/fixtures/serialbox_golden

Then re-run ``pixi run test-py-unit`` and update the version notes above /
in ``README.md`` if anything in the on-disk shape changed.

Coverage (chosen to stress the format, per issue #68)
-----------------------------------------------------
* Two savepoints sharing a name (``step``), distinguished by metainfo.
* Mixed dtypes / ranks: ``u`` (Float64, rank 3), ``nlevels`` (Int32, rank 1),
  ``ftol`` (Float32, rank 1).
* A multi-snapshot field (``u`` written at both savepoints) — this is the
  case that exposed the column-major storage-order bug the golden fixture
  was added to catch.
* Global metainfo of mixed scalar types plus an ``ArrayOfString`` entry
  (``tags``), exercising the array-metainfo path.
"""

from __future__ import annotations

import sys

import numpy as np
import serialbox as ser


def main(out_dir: str) -> None:
    serializer = ser.Serializer(ser.OpenModeKind.Write, out_dir, "golden", "Binary")

    serializer.global_metainfo.insert("author", "serialbox-golden")
    serializer.global_metainfo.insert("schema_version", np.int32(7))
    serializer.global_metainfo.insert("use_gpu", True)
    serializer.global_metainfo.insert("tags", ["alpha", "beta", "gamma"])

    u = np.arange(24, dtype=np.float64).reshape(4, 3, 2)
    nlevels = np.array([10, 20, 30], dtype=np.int32)
    ftol = np.array([1.5, 2.5], dtype=np.float32)

    sp1 = ser.Savepoint("step", {"ntstep": np.int32(1), "t": 0.5})
    serializer.write("u", sp1, u)
    serializer.write("nlevels", sp1, nlevels)

    sp2 = ser.Savepoint("step", {"ntstep": np.int32(2), "t": 1.0})
    serializer.write("u", sp2, u + 100.0)
    serializer.write("ftol", sp2, ftol)

    del serializer  # flush metadata on destruction
    print(f"wrote golden Serialbox dump to {out_dir}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
