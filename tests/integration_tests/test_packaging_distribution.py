"""Packaging test: the built wheel **and** sdist ship the Fortran runtime,
and the discovery API/CLI resolves to it.

This guards the spec's central regression — that no install path ships the
runtime — so it is gated end to end in ``verify`` via the dedicated
``pixi run test-packaging`` lane (pure Python, no Fortran toolchain). It
builds real artifacts with ``python -m build`` and inspects their contents;
``--no-isolation`` keeps it offline by reusing the dev env's
``hatchling`` rather than downloading the build backend.

The sdist matters as much as the wheel: ``pip install preserf`` falls back to
building from the source tarball when no matching wheel is available, so a
tarball missing the Fortran runtime sources would break installs that the
wheel test never exercises.
"""

from __future__ import annotations

import importlib.metadata
import importlib.util
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

import pytest
from packaging.version import Version
from typer.testing import CliRunner

import preserf
from preserf.cli import app
from tests._support.consumer import build, build_wheel

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
    # The typing marker and the runtime README: a typing-aware consumer
    # (py.typed) and a doc-reading consumer (README) need both shipped.
    "preserf/py.typed",
    "preserf/fortran/README.md",
)


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


@pytest.mark.packaging
def test_wheel_bundles_fortran_runtime(tmp_path: Path) -> None:
    names = _wheel_names(build_wheel(tmp_path))
    for expected in _EXPECTED_RUNTIME_FILES:
        assert expected in names, f"{expected} missing from wheel: {sorted(names)}"
    # The CPP overload templates ship too (m_preserf.F90 #includes them).
    assert any(
        n.startswith("preserf/fortran/") and n.endswith(".inc") for n in names
    ), f"no .inc templates in wheel: {sorted(names)}"


@pytest.mark.packaging
def test_sdist_bundles_fortran_runtime(tmp_path: Path) -> None:
    names = _sdist_names(build("--sdist", tmp_path, "*.tar.gz"))
    for expected in _EXPECTED_RUNTIME_FILES:
        assert expected in names, f"{expected} missing from sdist: {sorted(names)}"
    # The CPP overload templates ship too (m_preserf.F90 #includes them).
    assert any(
        n.startswith("preserf/fortran/") and n.endswith(".inc") for n in names
    ), f"no .inc templates in sdist: {sorted(names)}"


@pytest.mark.packaging
@pytest.mark.skipif(
    importlib.util.find_spec("twine") is None,
    reason="twine not installed; metadata validation is best-effort",
)
def test_twine_check_passes(tmp_path: Path) -> None:
    """``twine check`` validates the rendered metadata for both artifacts."""
    wheel = build_wheel(tmp_path)
    sdist = build("--sdist", tmp_path, "*.tar.gz")
    result = subprocess.run(
        [sys.executable, "-m", "twine", "check", str(wheel), str(sdist)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, (
        f"twine check failed.\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )


@pytest.mark.packaging
def test_wheel_metadata_version_matches_source(tmp_path: Path) -> None:
    """The wheel's METADATA ``Version:`` equals ``preserf.__version__``.

    The version derives from a single literal in
    ``src/preserf/__init__.py`` that hatch reads, so a bump there
    propagates to the artifact without any other edit. Compared as
    normalized PEP 440 versions so a valid-but-non-normalized literal
    (e.g. ``0.2.0-dev0``) does not false-fail.
    """
    wheel = build_wheel(tmp_path)
    with zipfile.ZipFile(wheel) as archive:
        dist_info = next(
            name for name in archive.namelist() if name.endswith(".dist-info/METADATA")
        )
        metadata = archive.read(dist_info).decode()
    version_line = next(
        (line for line in metadata.splitlines() if line.startswith("Version:")),
        None,
    )
    assert version_line is not None, "no Version: line in wheel METADATA"
    assert Version(version_line.partition(":")[2].strip()) == Version(
        preserf.__version__
    ), (
        f"wheel METADATA version {version_line!r} does not equal "
        f"preserf.__version__ {preserf.__version__!r}"
    )

    # The spec's version-bump scenario requires BOTH the wheel metadata and
    # importlib.metadata.version("preserf") to reflect the bump — assert the
    # installed-artifact metadata half here (the dev env's editable install
    # shares the same version literal as the wheel under test).
    assert importlib.metadata.version("preserf") == preserf.__version__, (
        f"importlib.metadata.version('preserf') "
        f"{importlib.metadata.version('preserf')!r} != preserf.__version__ "
        f"{preserf.__version__!r}"
    )


@pytest.mark.packaging
def test_wheel_metadata_declares_spec_runtime_deps(tmp_path: Path) -> None:
    """The wheel's METADATA declares the spec's runtime requirements.

    The packaging-distribution spec requires the package to declare
    runtime dependencies ``typer>=0.12`` and ``rich>=13.0`` only, and to
    target Python >= 3.12. The hermetic ``--no-deps`` venv install in the
    consumer test no longer catches a missing or wrong ``Requires-Dist``
    (it borrows the dev environment's deps), so assert the metadata
    directly.
    """
    wheel = build_wheel(tmp_path)
    with zipfile.ZipFile(wheel) as archive:
        dist_info = next(
            name for name in archive.namelist() if name.endswith(".dist-info/METADATA")
        )
        metadata = archive.read(dist_info).decode()
    lines = metadata.splitlines()
    assert "Requires-Dist: typer>=0.12" in lines
    assert "Requires-Dist: rich>=13.0" in lines
    assert "Requires-Python: >=3.12" in lines
    # The spec says those two deps ONLY — enforce the exact set.
    requires_dist = {line for line in lines if line.startswith("Requires-Dist:")}
    assert requires_dist == {
        "Requires-Dist: typer>=0.12",
        "Requires-Dist: rich>=13.0",
    }, f"unexpected Requires-Dist set: {sorted(requires_dist)}"


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
