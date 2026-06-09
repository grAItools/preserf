"""Install-and-find_package test: the standalone CMake install workflow.

Unlike ``test_external_consumer.py`` (which builds an app through the shipped
``PreserfFortran.cmake`` helper, i.e. an ``add_subdirectory`` source build),
this exercises the *installed-library* path the runtime's own ``CMakeLists.txt``
now supports:

    cmake -S "$(preserf --fortran-dir)" -B build -DCMAKE_INSTALL_PREFIX=...
    cmake --build build --target install

followed by a downstream project that consumes the install purely through
``find_package(preserf_fortran)`` + ``target_link_libraries(app PRIVATE
preserf::preserf_fortran)``. It proves the whole install chain — exported
target, installed ``.mod`` interface files, generated package config, and the
re-discovered ``netcdf-fortran`` link dependency — resolves end to end.

Marked ``consumer`` so it is deselected from the fast ``verify`` gate (see the
``addopts`` in ``pyproject.toml``); it runs under ``pixi run test-consumer`` /
``pixi run test-all``. It skips gracefully when the Fortran toolchain
(compiler, ``netcdf-fortran`` via pkg-config, CMake) is unavailable.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from typing import TYPE_CHECKING

import pytest

import preserf

if TYPE_CHECKING:
    from pathlib import Path

pytestmark = pytest.mark.consumer

# Probe order matches tests/conftest.py: single-config generators drop the
# binary directly under the build dir, multi-config ones under a per-config
# subdir.
_CONFIG_SUBDIRS = ("", "Debug", "Release", "RelWithDebInfo", "MinSizeRel")

# A minimal downstream program: it `use`s the installed module (forcing the
# `.mod` interface to resolve) and calls into the library (forcing the link),
# but needs no store on disk, so the test stays fast and filesystem-free.
_CONSUMER_PROGRAM = """\
program check
    use m_serialize, only: fs_enable_serialization, fs_serialization_status
    implicit none
    call fs_enable_serialization()
    if (fs_serialization_status()) then
        print *, "preserf_fortran find_package OK"
    else
        error stop "serialization status not set after enable"
    end if
end program check
"""

_CONSUMER_MARKER = "preserf_fortran find_package OK"

# The downstream consumer: discover the installed package and link the
# namespaced target. No reference to the in-tree checkout or the helper.
_CONSUMER_CMAKE = """\
cmake_minimum_required(VERSION 3.20)
project(preserf_install_consumer LANGUAGES Fortran)

find_package(preserf_fortran REQUIRED)

add_executable(consumer consumer.f90)
target_link_libraries(consumer PRIVATE preserf::preserf_fortran)
"""


def _require_toolchain() -> None:
    """Skip unless the full Fortran build/install toolchain is available."""
    missing: list[str] = []
    if shutil.which("cmake") is None:
        missing.append("cmake")
    # The runtime library is built with GNU-specific flags (-cpp,
    # -ffree-line-length-none) the generated overload matrix requires, so the
    # build genuinely needs gfortran rather than any Fortran compiler.
    if shutil.which("gfortran") is None:
        missing.append("gfortran")
    if shutil.which("pkg-config") is None:
        missing.append("pkg-config")
    elif (
        subprocess.run(
            ["pkg-config", "--exists", "netcdf-fortran"], check=False
        ).returncode
        != 0
    ):
        missing.append("netcdf-fortran (pkg-config)")
    if missing:
        message = "install/find_package toolchain unavailable: " + ", ".join(missing)
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


def test_install_then_find_package(tmp_path: Path) -> None:
    _require_toolchain()

    fortran_src = preserf.get_fortran_dir()
    prefix = tmp_path / "prefix"

    # 1. Build and install the runtime through its own CMakeLists — the exact
    #    `cmake -S "$(preserf --fortran-dir)" ...` workflow.
    runtime_build = tmp_path / "runtime-build"
    _run(
        [
            "cmake",
            "-S",
            str(fortran_src),
            "-B",
            str(runtime_build),
            f"-DCMAKE_INSTALL_PREFIX={prefix}",
        ],
        cwd=tmp_path,
    )
    _run(["cmake", "--build", str(runtime_build), "--target", "install"], cwd=tmp_path)

    # The install laid down the package config and at least one `.mod`.
    assert (
        prefix / "lib" / "cmake" / "preserf_fortran" / "preserf_fortranConfig.cmake"
    ).is_file()
    assert list(prefix.rglob("m_serialize.mod")), "installed .mod missing"

    # 2. Build a downstream project that consumes the install via find_package.
    project = tmp_path / "project"
    project.mkdir()
    (project / "consumer.f90").write_text(_CONSUMER_PROGRAM)
    (project / "CMakeLists.txt").write_text(_CONSUMER_CMAKE)

    build = tmp_path / "consumer-build"
    _run(
        [
            "cmake",
            "-S",
            str(project),
            "-B",
            str(build),
            f"-DCMAKE_PREFIX_PATH={prefix}",
        ],
        cwd=tmp_path,
    )
    _run(["cmake", "--build", str(build)], cwd=tmp_path)

    binary = _locate_binary(build, "consumer")
    assert binary is not None, f"consumer binary not built under {build}"

    result = subprocess.run(
        [str(binary)], capture_output=True, text=True, check=False, timeout=60
    )
    assert result.returncode == 0, (
        f"consumer exited {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert _CONSUMER_MARKER in result.stdout
