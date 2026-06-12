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

import subprocess
from typing import TYPE_CHECKING

import pytest

import preserf
from tests._support.consumer import locate_binary, require_toolchain, run

if TYPE_CHECKING:
    from pathlib import Path

pytestmark = pytest.mark.consumer

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


def test_install_then_find_package(tmp_path: Path) -> None:
    require_toolchain("install/find_package")

    fortran_src = preserf.get_fortran_dir()
    prefix = tmp_path / "prefix"

    # 1. Build and install the runtime through its own CMakeLists — the exact
    #    `cmake -S "$(preserf --fortran-dir)" ...` workflow.
    runtime_build = tmp_path / "runtime-build"
    run(
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
    run(["cmake", "--build", str(runtime_build), "--target", "install"], cwd=tmp_path)

    # The install laid down the package config and at least one `.mod`. Locate
    # them with rglob rather than a hard-coded lib/: GNUInstallDirs resolves
    # CMAKE_INSTALL_LIBDIR to lib64 on some 64-bit distros, and the downstream
    # find_package below searches both regardless.
    assert list(prefix.rglob("preserf_fortranConfig.cmake")), "package config missing"
    assert list(prefix.rglob("m_serialize.mod")), "installed .mod missing"

    # 2. Build a downstream project that consumes the install via find_package.
    project = tmp_path / "project"
    project.mkdir()
    (project / "consumer.f90").write_text(_CONSUMER_PROGRAM)
    (project / "CMakeLists.txt").write_text(_CONSUMER_CMAKE)

    build = tmp_path / "consumer-build"
    run(
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
    run(["cmake", "--build", str(build)], cwd=tmp_path)

    binary = locate_binary(build, "consumer")
    assert binary is not None, f"consumer binary not built under {build}"

    result = subprocess.run(
        [str(binary)], capture_output=True, text=True, check=False, timeout=60
    )
    assert result.returncode == 0, (
        f"consumer exited {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert _CONSUMER_MARKER in result.stdout
