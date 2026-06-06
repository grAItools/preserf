"""External-consumer test: build a project against the *bundled* runtime.

Unlike the in-tree e2e test (which builds from the repo's own CMake tree),
this stands up a throwaway project that discovers the runtime purely through
``preserf --cmake-helper`` — the exact path an installed user takes — then
``include()``s the shipped helper, compiles, runs, and confirms the bundled
runtime produced a readable preserf store. It proves the discovery -> helper
-> library -> link -> run chain end to end; the *serialization* contract
(exact values, axis order) is owned by ``test_preprocessor_e2e.py``, so this
test asserts only that a valid store was written.

Marked ``consumer`` so it is deselected from the fast ``verify`` gate (see the
``addopts`` in ``pyproject.toml``); it runs under ``pixi run test-consumer`` /
``pixi run test-all``. It skips gracefully when the Fortran toolchain
(compiler, ``netcdf-fortran`` via pkg-config, CMake) or the ``preserf`` CLI is
unavailable.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

from tests._support.serialbox import TypeID
from tests._support.storage import read_dump

pytestmark = pytest.mark.consumer

_REPO_ROOT = Path(__file__).resolve().parents[2]

# Reuse the in-tree e2e fixture as the consumer's sample `!$SER` program
# rather than maintaining a second hand-written copy that could drift from it.
# The fixture prints "preserf-fortran: e2e OK" and writes a store with prefix
# "e2e" (see tests-fortran/e2e/e2e_fixture.f90.in).
_FIXTURE = _REPO_ROOT / "tests-fortran" / "e2e" / "e2e_fixture.f90.in"
_FIXTURE_MARKER = "preserf-fortran: e2e OK"
_FIXTURE_PREFIX = "e2e"

# Probe order matches tests/conftest.py: single-config generators drop the
# binary directly under the build dir, multi-config ones under a per-config
# subdir.
_CONFIG_SUBDIRS = ("", "Debug", "Release", "RelWithDebInfo", "MinSizeRel")

# A consumer's CMakeLists: discover the helper via the CLI and call it — the
# documented integration recipe, with no reference to the in-tree checkout.
_CONSUMER_CMAKE = """\
cmake_minimum_required(VERSION 3.20)
project(preserf_consumer LANGUAGES Fortran)

execute_process(
    COMMAND preserf --cmake-helper
    OUTPUT_VARIABLE PRESERF_CMAKE_HELPER
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE _preserf_rc
)
if(NOT _preserf_rc EQUAL 0)
    message(FATAL_ERROR "preserf --cmake-helper failed (${_preserf_rc})")
endif()

include("${PRESERF_CMAKE_HELPER}")
preserf_add_fortran_target(consumer
    SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/consumer.f90)
"""


def _require_consumer_toolchain() -> None:
    """Skip unless the full external-build toolchain is available."""
    missing: list[str] = []
    if shutil.which("preserf") is None:
        missing.append("preserf CLI")
    if shutil.which("cmake") is None:
        missing.append("cmake")
    # The shipped helper emits GNU-specific flags (-ffree-line-length-none,
    # -cpp), which the long generated `fs_*` lines require, so the build
    # genuinely needs gfortran rather than any Fortran compiler.
    if shutil.which("gfortran") is None:
        missing.append("gfortran")
    if shutil.which("pkg-config") is None:
        # Check the tool exists before invoking it, so a host without
        # pkg-config skips cleanly instead of raising FileNotFoundError.
        missing.append("pkg-config")
    elif (
        subprocess.run(
            ["pkg-config", "--exists", "netcdf-fortran"], check=False
        ).returncode
        != 0
    ):
        missing.append("netcdf-fortran (pkg-config)")
    if missing:
        message = "external-consumer toolchain unavailable: " + ", ".join(missing)
        # Mirror the wire-compat philosophy: a CI run that opts in via
        # PRESERF_REQUIRE_FORTRAN=1 turns a missing toolchain into a failure
        # instead of a silent skip.
        if os.environ.get("PRESERF_REQUIRE_FORTRAN") == "1":
            pytest.fail(message)
        pytest.skip(message)


def _run(cmd: list[str], cwd: Path) -> None:
    result = subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, check=False, timeout=300
    )
    assert result.returncode == 0, (
        f"command failed: {' '.join(cmd)}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


def _locate_binary(build: Path, name: str) -> Path | None:
    """Find the built executable across single- and multi-config generators."""
    for config in _CONFIG_SUBDIRS:
        base = build / config if config else build
        for candidate in (base / name, base / f"{name}.exe"):
            if candidate.is_file():
                return candidate
    return None


def test_external_project_builds_against_bundled_runtime(tmp_path: Path) -> None:
    _require_consumer_toolchain()

    project = tmp_path / "project"
    project.mkdir()
    (project / "consumer.f90").write_text(_FIXTURE.read_text())
    (project / "CMakeLists.txt").write_text(_CONSUMER_CMAKE)

    build = tmp_path / "build"
    out_dir = tmp_path / "store"
    out_dir.mkdir()

    _run(["cmake", "-S", str(project), "-B", str(build)], cwd=tmp_path)
    _run(["cmake", "--build", str(build)], cwd=tmp_path)

    binary = _locate_binary(build, "consumer")
    assert binary is not None, f"consumer binary not built under {build}"

    result = subprocess.run(
        [str(binary), str(out_dir)],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"consumer exited {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert _FIXTURE_MARKER in result.stdout

    # The bundled runtime wrote a store the Python reader decodes. This test
    # only confirms a valid store landed (the build chain works); the full
    # value/axis round-trip is asserted by test_preprocessor_e2e.py.
    dump = read_dump(str(out_dir / f"{_FIXTURE_PREFIX}.nc"))
    assert dump.prefix == _FIXTURE_PREFIX
    assert "temperature" in dump.field_map
    assert dump.field_map["temperature"].type_id == TypeID.Float64
