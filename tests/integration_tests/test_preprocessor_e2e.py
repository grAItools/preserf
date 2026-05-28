"""End-to-end pipeline test: preprocessor -> helper -> store (Slice D Phase 4).

The ``preserf_fortran_test_e2e`` binary is built from
``tests-fortran/e2e/e2e_fixture.f90.in``: at CMake build time the fixture is
run through the ``preserf`` CLI, the generated Fortran is compiled against the
helper library, and the binary writes a store. This test runs that binary and
validates the store via ``tests/_support/storage.py`` — the only test that
exercises the whole pipeline rather than a hand-written ``fs_*`` driver.

Like the wire-compat test, a missing binary skips by default and fails when
``PRESERF_REQUIRE_FORTRAN=1`` (set in CI). Build locally with
``pixi run build-fortran``.
"""

from __future__ import annotations

import subprocess
from typing import TYPE_CHECKING

import numpy as np

from tests._support.serialbox import TypeID
from tests._support.storage import read_dump

if TYPE_CHECKING:
    from pathlib import Path


def test_preprocessor_pipeline_writes_readable_store(
    tmp_path: Path, fortran_e2e_binary: Path
) -> None:
    """A `!$SER`-annotated source preprocessed, compiled, and run produces a
    store the Python reader decodes, including the Slice D init keywords."""
    out_dir = tmp_path / "e2e_out"
    out_dir.mkdir()

    result = subprocess.run(
        [str(fortran_e2e_binary), str(out_dir)],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"e2e binary exited {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert "preserf-fortran: e2e OK" in result.stdout

    dump = read_dump(str(out_dir / "e2e.nc"))

    # `!$SER INIT` widened keywords round-trip via `_preserf_*` root attrs.
    assert dump.prefix == "e2e"
    assert dump.singlefile is True
    assert dump.unique_id == 42
    assert dump.archive == "Binary"

    # `!$SER METAINFO` -> serializer metainfo.
    assert dump.global_meta_info["author"].type_id == TypeID.String
    assert dump.global_meta_info["author"].value == "e2e-fixture"

    # `!$SER REGISTER temperature real IJ` -> a Float64 field, dims 3x4
    # (recorded in netCDF C-order, so reversed to [4, 3]).
    assert "temperature" in dump.field_map
    info = dump.field_map["temperature"]
    assert info.type_id == TypeID.Float64
    assert info.dims == [4, 3]

    # `!$SER SAVEPOINT sp1 step=1` -> one savepoint carrying Int32 metainfo.
    assert len(dump.savepoints) == 1
    sp = dump.savepoints[0]
    assert sp.name == "sp1"
    assert sp.meta_info["step"].type_id == TypeID.Int32
    assert sp.meta_info["step"].value == 1

    # `!$SER DATA temperature=temperature` -> the field data survives the
    # round-trip. Compare the value set (10*i + j) rather than a fixed
    # layout so the assertion is independent of axis ordering.
    data = dump.field_data["temperature"][0]
    expected = {10 * i + j for i in range(1, 4) for j in range(1, 5)}
    assert set(np.asarray(data).ravel().astype(int).tolist()) == expected
