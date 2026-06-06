"""External-consumer test: build a project against the *bundled* runtime.

Unlike the in-tree e2e test (which builds from the repo's own CMake tree),
this stands up a throwaway project that discovers the runtime purely through
``preserf --cmake-helper`` — the exact path an installed user takes — then
``include()``s the shipped helper, compiles, runs, and validates the store.
It proves the discovery -> helper -> library -> link -> run chain end to end.

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
from typing import TYPE_CHECKING

import numpy as np
import pytest

from tests._support.serialbox import TypeID
from tests._support.storage import read_dump

if TYPE_CHECKING:
    from pathlib import Path

pytestmark = pytest.mark.consumer

# A minimal `!$SER` program, modelled on the e2e fixture: one real64 field
# registered via the `IJ` shortcut, write mode, distinct decodable values.
_CONSUMER_SOURCE = """\
program preserf_consumer
   use, intrinsic :: iso_fortran_env, only: real64
   implicit none
   integer, parameter :: ie = 3, je = 4, nboundlines = 0
   character(len=:), allocatable :: outdir
   integer :: arg_len, arg_stat
   real(real64) :: temperature(ie, je)
   integer :: i, j

   call get_command_argument(1, length=arg_len, status=arg_stat)
   if (arg_stat /= 0) then
      write (*, '(a)') 'preserf-consumer: missing output directory argument'
      error stop 1
   end if
   allocate (character(len=arg_len) :: outdir)
   call get_command_argument(1, value=outdir, status=arg_stat)

   do j = 1, je
      do i = 1, ie
         temperature(i, j) = real(10*i + j, real64)
      end do
   end do

   !$SER INIT directory=outdir prefix="consumer" mode="w"
   !$SER REGISTER temperature real IJ
   !$SER SAVEPOINT sp1 step=1
   !$SER DATA temperature=temperature
   !$SER CLEANUP

   write (*, '(a)') 'preserf-consumer: OK'
end program preserf_consumer
"""

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
    if shutil.which("gfortran") is None:
        missing.append("gfortran")
    if (
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


def test_external_project_builds_against_bundled_runtime(tmp_path: Path) -> None:
    _require_consumer_toolchain()

    project = tmp_path / "project"
    project.mkdir()
    (project / "consumer.f90").write_text(_CONSUMER_SOURCE)
    (project / "CMakeLists.txt").write_text(_CONSUMER_CMAKE)

    build = tmp_path / "build"
    out_dir = tmp_path / "store"
    out_dir.mkdir()

    _run(["cmake", "-S", str(project), "-B", str(build)], cwd=tmp_path)
    _run(["cmake", "--build", str(build)], cwd=tmp_path)

    binary = build / "consumer"
    if not binary.is_file():
        binary = build / "consumer.exe"
    assert binary.is_file(), f"consumer binary not built under {build}"

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
    assert "preserf-consumer: OK" in result.stdout

    # The bundled runtime wrote a store the Python reader decodes.
    dump = read_dump(str(out_dir / "consumer.nc"))
    assert dump.prefix == "consumer"
    assert "temperature" in dump.field_map
    info = dump.field_map["temperature"]
    assert info.type_id == TypeID.Float64
    assert info.dims == [4, 3]  # Fortran (3, 4) -> netCDF C-order [4, 3]

    data = dump.field_data["temperature"][0]
    expected = {10 * i + j for i in range(1, 4) for j in range(1, 5)}
    assert set(np.asarray(data).ravel().astype(int).tolist()) == expected
