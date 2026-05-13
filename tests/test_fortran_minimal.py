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
_DEFAULT_BIN = _REPO_ROOT / "src/preserf-fortran/build/test/test_minimal"


def _locate_binary() -> Path | None:
    """Find the built test_minimal binary.

    Considers both the POSIX path and a Windows `.exe` sibling, and
    requires that the file be executable so a partially-built tree
    (file exists but lacks +x) skips gracefully instead of crashing the
    test with PermissionError.
    """
    for candidate in (_DEFAULT_BIN, _DEFAULT_BIN.with_suffix(".exe")):
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


@pytest.fixture
def fortran_binary() -> Path:
    binary = _locate_binary()
    if binary is None:
        pytest.skip(
            f"Fortran test binary not built at {_DEFAULT_BIN}; "
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

    dump = read_dump(str(out_dir / "fhello.nc"))

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

    # Field registry: u, Float64. Fortran registered (iSize=4, jSize=3,
    # kSize=2); the helper reverses to C-order, so dims == [2, 3, 4].
    assert set(dump.field_map.keys()) == {"u"}
    u_info = dump.field_map["u"]
    assert u_info.type_id == TypeID.Float64
    assert u_info.dims == [2, 3, 4]

    # One savepoint named "step" with two metainfo entries
    assert len(dump.savepoints) == 1
    sp = dump.savepoints[0]
    assert sp.name == "step"
    assert sp.meta_info["ntstep"].type_id == TypeID.Int32
    assert sp.meta_info["ntstep"].value == 1
    assert sp.meta_info["t"].type_id == TypeID.Float64
    assert sp.meta_info["t"].value == 0.5
    assert sp.fields == {"u": 0}

    # Field data round-trip. The Fortran test sets u(i,j,k) = 100*i + 10*j + k
    # (Fortran indexing). After axis reversal the Python view has shape
    # (nk, nj, ni) = (2, 3, 4), and Fortran's u(i,j,k) lands at numpy
    # u_py[k-1, j-1, i-1].
    u_py = dump.field_data["u"][0]
    assert u_py.shape == (2, 3, 4)
    assert u_py.dtype == np.float64
    # Spot-check the corners and a couple of interior cells.
    assert u_py[0, 0, 0] == 111  # Fortran u(1,1,1)
    assert u_py[0, 0, 3] == 411  # Fortran u(4,1,1)
    assert u_py[0, 2, 0] == 131  # Fortran u(1,3,1)
    assert u_py[1, 0, 0] == 112  # Fortran u(1,1,2)
    assert u_py[1, 2, 3] == 432  # Fortran u(4,3,2)
