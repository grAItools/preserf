"""Packaging test: the built wheel ships the Fortran runtime, and the
discovery API/CLI resolve to it.

This guards the spec's central regression — that no install path ships the
runtime — so it lives in the fast ``verify`` gate (pure Python, no Fortran
toolchain). It builds a real wheel with ``python -m build`` and inspects its
contents; ``--no-isolation`` keeps it offline by reusing the dev env's
``hatchling`` rather than downloading the build backend.
"""

from __future__ import annotations

import subprocess
import sys
import zipfile
from pathlib import Path

from typer.testing import CliRunner

import preserf
from preserf.cli import app

_REPO_ROOT = Path(__file__).resolve().parents[2]

# A representative slice of the runtime tree that must travel in the wheel.
_EXPECTED_WHEEL_FILES = (
    "preserf/fortran/m_preserf.F90",
    "preserf/fortran/utils_preserf.f90",
    "preserf/fortran/m_serialize.f90",
    "preserf/fortran/utils_ppser.f90",
    "preserf/fortran/preserf_version.f90.in",
    "preserf/fortran/CMakeLists.txt",
)


def _build_wheel(outdir: Path) -> Path:
    """Build a wheel from the repo into ``outdir`` and return its path."""
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "build",
            "--wheel",
            "--no-isolation",
            "--outdir",
            str(outdir),
            str(_REPO_ROOT),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, (
        f"wheel build exited {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    wheels = list(outdir.glob("*.whl"))
    assert len(wheels) == 1, f"expected one wheel, got {wheels}"
    return wheels[0]


def test_wheel_bundles_fortran_runtime(tmp_path: Path) -> None:
    wheel = _build_wheel(tmp_path)
    names = set(zipfile.ZipFile(wheel).namelist())
    for expected in _EXPECTED_WHEEL_FILES:
        assert expected in names, f"{expected} missing from wheel: {sorted(names)}"
    # The CPP overload templates ship too (m_preserf.F90 #includes them).
    assert any(
        n.startswith("preserf/fortran/") and n.endswith(".inc") for n in names
    ), f"no .inc templates in wheel: {sorted(names)}"


def test_discovery_api_resolves_to_runtime() -> None:
    assert (preserf.get_fortran_dir() / "m_preserf.F90").is_file()


def test_discovery_cli_resolves_to_runtime() -> None:
    result = CliRunner().invoke(app, ["--fortran-dir"])
    assert result.exit_code == 0
    assert (Path(result.stdout.strip()) / "m_preserf.F90").is_file()
