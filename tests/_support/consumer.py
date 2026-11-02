"""Shared helpers for the ``consumer``-marked external-build tests.

``test_external_consumer.py`` (the ``add_subdirectory`` helper path) and
``test_install_find_package.py`` (the ``find_package`` install path) both stand
up a throwaway project, drive CMake, and run the resulting binary. The toolchain
guard, the subprocess runner, and the generator-aware binary locator are
identical across the two, so they live here as the single source of truth.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from pathlib import Path

# Probe order matches tests/conftest.py: single-config generators (Ninja, Unix
# Makefiles) drop the binary directly under the build dir, multi-config ones
# (Visual Studio, Xcode) under a per-config subdir.
CONFIG_SUBDIRS = ("", "Debug", "Release", "RelWithDebInfo", "MinSizeRel")


def require_toolchain(label: str, *, need_preserf_cli: bool = False) -> None:
    """Skip (or fail under PRESERF_REQUIRE_FORTRAN=1) unless the toolchain exists.

    The runtime library is built with GNU-specific flags (``-cpp``,
    ``-ffree-line-length-none``) the generated overload matrix requires, so the
    build genuinely needs gfortran rather than any Fortran compiler.

    ``label`` names the calling test in the skip message; ``need_preserf_cli``
    additionally requires the ``preserf`` CLI on PATH (the helper-discovery path
    shells out to it; the install path does not).
    """
    missing: list[str] = []
    if need_preserf_cli and shutil.which("preserf") is None:
        missing.append("preserf CLI")
    if shutil.which("cmake") is None:
        missing.append("cmake")
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
        message = f"{label} toolchain unavailable: " + ", ".join(missing)
        # Mirror the wire-compat philosophy: a CI run that opts in via
        # PRESERF_REQUIRE_FORTRAN=1 turns a missing toolchain into a failure
        # instead of a silent skip.
        if os.environ.get("PRESERF_REQUIRE_FORTRAN") == "1":
            pytest.fail(message)
        pytest.skip(message)


def run(cmd: list[str], cwd: Path) -> None:
    """Run a build command, asserting success with captured output on failure."""
    result = subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, check=False, timeout=300
    )
    assert result.returncode == 0, (
        f"command failed: {' '.join(cmd)}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


def locate_binary(build: Path, name: str) -> Path | None:
    """Find the built executable across single- and multi-config generators."""
    for config in CONFIG_SUBDIRS:
        base = build / config if config else build
        for candidate in (base / name, base / f"{name}.exe"):
            if candidate.is_file():
                return candidate
    return None
