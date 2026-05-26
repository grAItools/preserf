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

# The Fortran test executable is built via ``pixi run build-fortran``, which
# now invokes ``cmake -S tests-fortran -B build/preserf-fortran``. The
# tests-fortran tree registers the executable under ``unit/m_preserf/``
# (see tests-fortran/unit/m_preserf/CMakeLists.txt), so the binary lands at
# ``build/preserf-fortran/unit/m_preserf/preserf_fortran_test_minimal``.
_BUILD_TEST_DIR = _REPO_ROOT / "build/preserf-fortran/unit/m_preserf"

# Single-config generators (Ninja, Unix Makefiles) drop the binary in
# `_BUILD_TEST_DIR` directly; multi-config generators (Visual Studio,
# Xcode) drop it under a per-config subdir. We probe both shapes so the
# fixture works regardless of which generator built the tree.
_CONFIG_SUBDIRS = ("", "Debug", "Release", "RelWithDebInfo", "MinSizeRel")


def _locate_binary() -> Path | None:
    """Find the built preserf_fortran_test_minimal binary.

    Probes the single-config CMake output path AND the multi-config
    generator subdirectories listed in ``_CONFIG_SUBDIRS``. Requires the
    candidate to be executable so a partially-built tree (file exists
    but lacks +x) skips gracefully instead of crashing the test with
    PermissionError.
    """
    names = ("preserf_fortran_test_minimal", "preserf_fortran_test_minimal.exe")
    for config in _CONFIG_SUBDIRS:
        base = _BUILD_TEST_DIR / config if config else _BUILD_TEST_DIR
        for name in names:
            candidate = base / name
            if candidate.is_file() and os.access(candidate, os.X_OK):
                return candidate
    return None


@pytest.fixture
def fortran_binary() -> Path:
    binary = _locate_binary()
    if binary is None:
        # Render the probed subdirs as e.g. "<root>, <root>/Debug, ..."
        # so the diagnostic exactly matches what `_locate_binary` looked
        # for — no drift between probe list and skip message.
        probed = ", ".join(
            str(_BUILD_TEST_DIR / c) if c else str(_BUILD_TEST_DIR)
            for c in _CONFIG_SUBDIRS
        )
        message = (
            f"Fortran test binary not found (probed: {probed}); "
            "run `pixi run build-fortran` to build it."
        )
        # CI sets PRESERF_REQUIRE_FORTRAN=1 to turn a missing binary into a
        # hard failure. A plain pytest.skip would let a broken Fortran build
        # slip through `pixi run verify` silently.
        if os.environ.get("PRESERF_REQUIRE_FORTRAN") == "1":
            pytest.fail(message)
        pytest.skip(message)
    return binary
