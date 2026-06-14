"""Packaging test: the built wheel **and** sdist ship the Fortran runtime,
and the discovery API/CLI resolve to it.

This guards the spec's central regression — that no install path ships the
runtime — so it lives in the fast ``verify`` gate (pure Python, no Fortran
toolchain). It builds real artifacts with ``python -m build`` and inspects
their contents; ``--no-isolation`` keeps it offline by reusing the dev env's
``hatchling`` rather than downloading the build backend.

The sdist matters as much as the wheel: ``pip install preserf`` falls back to
building from the source tarball when no matching wheel is available, so a
tarball missing the Fortran runtime sources would break installs that the
wheel test never exercises.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

import pytest
from typer.testing import CliRunner

import preserf
from preserf.cli import app

_REPO_ROOT = Path(__file__).resolve().parents[2]

# A representative slice of the runtime tree that must travel in every
# distribution artifact (paths relative to the ``preserf`` package root).
_EXPECTED_RUNTIME_FILES = (
    "preserf/fortran/m_preserf.F90",
    "preserf/fortran/utils_preserf.f90",
    "preserf/fortran/m_serialize.f90",
    "preserf/fortran/utils_ppser.f90",
    "preserf/fortran/preserf_version.f90.in",
    "preserf/fortran/CMakeLists.txt",
    "preserf/fortran/cmake/PreserfFortran.cmake",
    # PreserfFortran.cmake includes this for the per-compiler preprocessing /
    # standards flags, so a consumer build breaks if it is not shipped too.
    "preserf/fortran/cmake/PreserfFortranFlags.cmake",
    "preserf/fortran/cmake/preserf_fortranConfig.cmake.in",
)


def _build(target: str, outdir: Path, glob: str) -> Path:
    """Build ``target`` (``--wheel`` / ``--sdist``) into ``outdir``.

    Returns the single produced artifact matching ``glob``.
    """
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "build",
            target,
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
        f"{target} build exited {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    artifacts = list(outdir.glob(glob))
    assert len(artifacts) == 1, f"expected one {glob} artifact, got {artifacts}"
    return artifacts[0]


def _build_wheel(outdir: Path) -> Path:
    return _build("--wheel", outdir, "*.whl")


def _build_sdist(outdir: Path) -> Path:
    return _build("--sdist", outdir, "*.tar.gz")


def _wheel_names(wheel: Path) -> set[str]:
    with zipfile.ZipFile(wheel) as archive:
        return set(archive.namelist())


def _sdist_names(sdist: Path) -> set[str]:
    """Member names with the leading ``<name>-<version>/`` prefix stripped.

    sdist members are nested under a top-level ``preserf-<version>/`` dir and
    keep the ``src/`` layout, so we normalise to package-relative paths
    (``preserf/fortran/...``) to share assertions with the wheel.
    """
    with tarfile.open(sdist, "r:gz") as archive:
        members = archive.getnames()
    names: set[str] = set()
    for member in members:
        # Drop the "preserf-<version>/" top-level prefix.
        rel = member.partition("/")[2]
        # sdist keeps the src layout; normalise "src/preserf/..." to "preserf/...".
        if rel.startswith("src/"):
            rel = rel[len("src/") :]
        names.add(rel)
    return names


def test_wheel_bundles_fortran_runtime(tmp_path: Path) -> None:
    names = _wheel_names(_build_wheel(tmp_path))
    for expected in _EXPECTED_RUNTIME_FILES:
        assert expected in names, f"{expected} missing from wheel: {sorted(names)}"
    # The CPP overload templates ship too (m_preserf.F90 #includes them).
    assert any(
        n.startswith("preserf/fortran/") and n.endswith(".inc") for n in names
    ), f"no .inc templates in wheel: {sorted(names)}"


def test_sdist_bundles_fortran_runtime(tmp_path: Path) -> None:
    names = _sdist_names(_build_sdist(tmp_path))
    for expected in _EXPECTED_RUNTIME_FILES:
        assert expected in names, f"{expected} missing from sdist: {sorted(names)}"
    # The CPP overload templates ship too (m_preserf.F90 #includes them).
    assert any(
        n.startswith("preserf/fortran/") and n.endswith(".inc") for n in names
    ), f"no .inc templates in sdist: {sorted(names)}"


@pytest.mark.skipif(
    importlib.util.find_spec("twine") is None,
    reason="twine not installed; metadata validation is best-effort",
)
def test_twine_check_passes(tmp_path: Path) -> None:
    """``twine check`` validates the rendered metadata for both artifacts."""
    wheel = _build_wheel(tmp_path)
    sdist = _build_sdist(tmp_path)
    result = subprocess.run(
        [sys.executable, "-m", "twine", "check", str(wheel), str(sdist)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, (
        f"twine check failed.\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )


def test_discovery_api_resolves_to_runtime() -> None:
    assert (preserf.get_fortran_dir() / "m_preserf.F90").is_file()


def test_discovery_cli_resolves_to_runtime() -> None:
    result = CliRunner().invoke(app, ["--fortran-dir"])
    assert result.exit_code == 0
    assert (Path(result.stdout.strip()) / "m_preserf.F90").is_file()


def test_cmake_helper_api_resolves_to_file() -> None:
    assert preserf.get_cmake_helper().is_file()


def test_cmake_helper_cli_resolves_to_file() -> None:
    result = CliRunner().invoke(app, ["--cmake-helper"])
    assert result.exit_code == 0
    assert Path(result.stdout.strip()).is_file()
