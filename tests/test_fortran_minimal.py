"""Cross-language wire-compat: Fortran writes, Python reads.

This test runs the ``test_minimal`` binary built from
``src/preserf-fortran/test/test_minimal.f90`` and validates the resulting
store via ``tests/_storage.py``. If the Fortran library hasn't been built
the test is skipped — the Fortran build is intentionally not part of
``uv run pytest`` because it depends on an external toolchain
(``gfortran`` + ``netcdf-fortran``) that not every developer has.

To build the binary locally::

    cmake -S src/preserf-fortran -B src/preserf-fortran/build
    cmake --build src/preserf-fortran/build

Then ``uv run pytest tests/test_fortran_minimal.py`` will pick it up.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import numpy as np
import pytest

from ._serialbox import TypeID
from ._storage import read_dump

_REPO_ROOT = Path(__file__).resolve().parent.parent
_BUILD_TEST_DIR = _REPO_ROOT / "src/preserf-fortran/build/test"


def _locate_binary() -> Path | None:
    """Find the built test_minimal binary.

    Probes the single-config CMake output path AND the typical
    multi-config generator subdirectories (Visual Studio, Xcode and
    similar produce `build/test/<Config>/test_minimal[.exe]`). Requires
    the candidate to be executable so a partially-built tree (file
    exists but lacks +x) skips gracefully instead of crashing the test
    with PermissionError.
    """
    config_subdirs = ("", "Debug", "Release", "RelWithDebInfo", "MinSizeRel")
    names = ("test_minimal", "test_minimal.exe")
    for config in config_subdirs:
        base = _BUILD_TEST_DIR / config if config else _BUILD_TEST_DIR
        for name in names:
            candidate = base / name
            if candidate.is_file() and os.access(candidate, os.X_OK):
                return candidate
    return None


@pytest.fixture
def fortran_binary() -> Path:
    binary = _locate_binary()
    if binary is None:
        pytest.skip(
            f"Fortran test binary not found under {_BUILD_TEST_DIR} "
            "(checked single-config + Debug/Release subdirs); "
            "see tests/test_fortran_minimal.py docstring for build steps."
        )
    return binary


def test_fortran_writes_python_reads(tmp_path: Path, fortran_binary: Path) -> None:
    """The Fortran helper writes a store the Python reader can decode."""
    out_dir = tmp_path / "fortran_out"
    out_dir.mkdir()

    # The Fortran test is expected to complete in well under a second;
    # the 60-second cap is generous but stops a deadlock from hanging
    # CI / local runs indefinitely.
    result = subprocess.run(
        [str(fortran_binary), str(out_dir)],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Fortran binary exited {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert "preserf-fortran: hello-world OK" in result.stdout

    nc_path = out_dir / "fhello.nc"

    # Direct attribute checks on the raw netCDF root. read_dump() skips
    # housekeeping attributes (those starting with `_preserf_`), so a
    # bug in the Fortran writer for `_preserf_writer` or the close-time
    # `_preserf_savepoint_count` refresh wouldn't surface through the
    # SerialboxDump-shaped assertions below.
    import netCDF4  # local import; netCDF4 is a dev-only dependency

    raw = netCDF4.Dataset(str(nc_path), "r")
    try:
        assert raw.getncattr("_preserf_schema_version") == 1
        assert raw.getncattr("_preserf_serialbox_prefix") == "fhello"
        # `_preserf_savepoint_count` is refreshed in preserf_close_serializer;
        # the test writes exactly one savepoint and expects that to be reflected.
        assert raw.getncattr("_preserf_savepoint_count") == 1
        writer = raw.getncattr("_preserf_writer")
        assert isinstance(writer, str) and writer.startswith("preserf ")
    finally:
        raw.close()

    dump = read_dump(str(nc_path))

    # Prefix and writer attribute
    assert dump.prefix == "fhello"

    # Global metainfo written via fs_add_serializer_metainfo
    assert "author" in dump.global_meta_info
    assert dump.global_meta_info["author"].type_id == TypeID.String
    assert dump.global_meta_info["author"].value == "fortran-test"
    assert dump.global_meta_info["schema_version"].type_id == TypeID.Int32
    assert dump.global_meta_info["schema_version"].value == 7
    # use_gpu exercises the Boolean → NF90_BYTE path. The shadow tag
    # carries TypeID.Boolean (=1), and the underlying value round-trips.
    assert dump.global_meta_info["use_gpu"].type_id == TypeID.Boolean
    assert dump.global_meta_info["use_gpu"].value is True
    # Int64 and Float32 metainfo branches.
    assert dump.global_meta_info["wallclock_ns"].type_id == TypeID.Int64
    assert dump.global_meta_info["wallclock_ns"].value == 1_700_000_000_000_000_000
    assert dump.global_meta_info["tolerance32"].type_id == TypeID.Float32
    assert dump.global_meta_info["tolerance32"].value == pytest.approx(1e-3, rel=1e-6)

    # Field registry: three fields covering all three real64 overloads.
    # The helper reverses Fortran-order sizes to C-order, so:
    #   u (Fortran iSize=4, jSize=3, kSize=2) → dims == [2, 3, 4]
    #   v (1-D, iSize=5)                       → dims == [5]
    #   w (2-D, iSize=3, jSize=4)              → dims == [4, 3]
    assert set(dump.field_map.keys()) == {"u", "v", "w"}
    assert dump.field_map["u"].type_id == TypeID.Float64
    assert dump.field_map["u"].dims == [2, 3, 4]
    assert dump.field_map["v"].type_id == TypeID.Float64
    assert dump.field_map["v"].dims == [5]
    assert dump.field_map["w"].type_id == TypeID.Float64
    assert dump.field_map["w"].dims == [4, 3]

    # One savepoint named "step" with two metainfo entries and three fields.
    assert len(dump.savepoints) == 1
    sp = dump.savepoints[0]
    assert sp.name == "step"
    assert sp.meta_info["ntstep"].type_id == TypeID.Int32
    assert sp.meta_info["ntstep"].value == 1
    assert sp.meta_info["t"].type_id == TypeID.Float64
    assert sp.meta_info["t"].value == 0.5
    assert set(sp.fields.keys()) == {"u", "v", "w"}

    # 3-D field round-trip. Fortran u(i,j,k) = 100*i + 10*j + k.
    # After axis reversal the Python view has shape (nk, nj, ni) =
    # (2, 3, 4), and Fortran's u(i,j,k) lands at numpy u_py[k-1, j-1, i-1].
    u_py = dump.field_data["u"][0]
    assert u_py.shape == (2, 3, 4)
    assert u_py.dtype == np.float64
    assert u_py[0, 0, 0] == 111  # Fortran u(1,1,1)
    assert u_py[0, 0, 3] == 411  # Fortran u(4,1,1)
    assert u_py[0, 2, 0] == 131  # Fortran u(1,3,1)
    assert u_py[1, 0, 0] == 112  # Fortran u(1,1,2)
    assert u_py[1, 2, 3] == 432  # Fortran u(4,3,2)

    # 1-D field round-trip. v is rank-1 so the C-order/Fortran-order
    # reversal is a no-op.
    v_py = dump.field_data["v"][0]
    assert v_py.shape == (5,)
    assert v_py.dtype == np.float64
    np.testing.assert_array_equal(v_py, np.arange(1, 6, dtype=np.float64))

    # 2-D field round-trip. Fortran w(i,j) = 10*i + j, registered as
    # iSize=3, jSize=4. C-order shape is (4, 3) and Fortran w(i,j)
    # lands at numpy w_py[j-1, i-1].
    w_py = dump.field_data["w"][0]
    assert w_py.shape == (4, 3)
    assert w_py.dtype == np.float64
    assert w_py[0, 0] == 11  # Fortran w(1,1)
    assert w_py[0, 2] == 31  # Fortran w(3,1)
    assert w_py[3, 0] == 14  # Fortran w(1,4)
    assert w_py[3, 2] == 34  # Fortran w(3,4)
