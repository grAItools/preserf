"""Shared pytest fixtures.

The ``fortran_binary`` fixture lives here (not under
``integration_tests/conftest.py``) so any future test — unit or
integration — can opt into the Fortran helper binary by simply
requesting the fixture. Tests in ``unit_tests/`` don't request it and
remain runnable without a Fortran toolchain.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parent.parent

# The Fortran test executables are built via ``pixi run build-fortran``,
# which invokes ``cmake -S tests-fortran -B build/preserf-fortran``. Each
# test subdir registers its executable under its own path in the build
# tree (see the per-subdir CMakeLists.txt files), e.g. the minimal binary
# lands at ``build/preserf-fortran/unit/m_preserf/...`` and the end-to-end
# binary at ``build/preserf-fortran/e2e/...``.
_BUILD_ROOT = _REPO_ROOT / "build/preserf-fortran"

# Single-config generators (Ninja, Unix Makefiles) drop the binary in
# the subdir directly; multi-config generators (Visual Studio, Xcode)
# drop it under a per-config subdir. We probe both shapes so the fixture
# works regardless of which generator built the tree.
_CONFIG_SUBDIRS = ("", "Debug", "Release", "RelWithDebInfo", "MinSizeRel")


def _locate_binary(subdir: str, name: str) -> Path | None:
    """Find a built Fortran test binary under ``build/preserf-fortran``.

    Probes the single-config CMake output path AND the multi-config
    generator subdirectories listed in ``_CONFIG_SUBDIRS``. Requires the
    candidate to be executable so a partially-built tree (file exists
    but lacks +x) skips gracefully instead of crashing the test with
    PermissionError.
    """
    base_dir = _BUILD_ROOT / subdir
    names = (name, f"{name}.exe")
    for config in _CONFIG_SUBDIRS:
        base = base_dir / config if config else base_dir
        for candidate_name in names:
            candidate = base / candidate_name
            if candidate.is_file() and os.access(candidate, os.X_OK):
                return candidate
    return None


def _require_binary(subdir: str, name: str) -> Path:
    binary = _locate_binary(subdir, name)
    if binary is None:
        base_dir = _BUILD_ROOT / subdir
        # Render the probed subdirs so the diagnostic exactly matches what
        # `_locate_binary` looked for — no drift between probe list and
        # skip message.
        probed = ", ".join(
            str(base_dir / c) if c else str(base_dir) for c in _CONFIG_SUBDIRS
        )
        message = (
            f"Fortran test binary '{name}' not found (probed: {probed}); "
            "run `pixi run build-fortran` to build it."
        )
        # CI sets PRESERF_REQUIRE_FORTRAN=1 to turn a missing binary into a
        # hard failure. A plain pytest.skip would let a broken Fortran build
        # slip through `pixi run verify` silently.
        if os.environ.get("PRESERF_REQUIRE_FORTRAN") == "1":
            pytest.fail(message)
        pytest.skip(message)
    return binary


@pytest.fixture
def fortran_binary() -> Path:
    return _require_binary("unit/m_preserf", "preserf_fortran_test_minimal")


@pytest.fixture
def fortran_e2e_binary() -> Path:
    return _require_binary("e2e", "preserf_fortran_test_e2e")
