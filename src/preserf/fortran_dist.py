"""Discovery of the bundled Fortran runtime and CMake helper.

The wheel ships the Fortran runtime sources and a CMake helper as package
data under ``preserf/fortran/``: because that tree lives inside the
``preserf`` package, hatchling includes it by default (no ``force-include``
needed — the packaging test guards that it actually ships). These accessors
resolve their on-disk location so a build system can find them without
knowing install internals — the numpy ``get_include()`` pattern.

Resolution is ``__file__``-relative: this module sits in the ``preserf``
package directory alongside the ``fortran/`` data, so the same code resolves
correctly for an editable (in-tree) install and an installed wheel.
"""

from __future__ import annotations

from pathlib import Path

_PACKAGE_DIR = Path(__file__).resolve().parent


def get_fortran_dir() -> Path:
    """Absolute path to the bundled Fortran runtime sources.

    The directory holds the ``.F90`` / ``.f90`` / ``.inc`` sources, the
    version template, the ``CMakeLists.txt`` that builds the
    ``preserf_fortran`` library, and the ``cmake/`` helper module. A build
    system compiles these against its own ``netcdf-fortran`` to link
    preserf-generated Fortran.
    """
    return _PACKAGE_DIR / "fortran"


def get_cmake_helper() -> Path:
    """Absolute path to the bundled CMake helper module.

    ``include()`` this file from a CMake project to get the
    ``preserf_add_fortran_target()`` and ``preserf_fortran_library()``
    functions that encapsulate the expand → compile → link → ``SERIALIZE``
    workflow.
    """
    return _PACKAGE_DIR / "fortran" / "cmake" / "PreserfFortran.cmake"
