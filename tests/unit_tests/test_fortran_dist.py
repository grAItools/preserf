"""Tests for the bundled Fortran runtime discovery API.

These cover the editable (in-tree) install; the wheel-contents variant
lives in ``tests/integration_tests/test_packaging_distribution.py``.
"""

import preserf
from preserf.fortran_dist import get_cmake_helper, get_fortran_dir


def test_get_fortran_dir_has_runtime_sources() -> None:
    fortran_dir = get_fortran_dir()
    assert fortran_dir.is_dir()
    # A representative slice of the runtime tree must be present.
    assert (fortran_dir / "m_preserf.F90").is_file()
    assert (fortran_dir / "utils_preserf.f90").is_file()
    assert (fortran_dir / "CMakeLists.txt").is_file()


def test_get_fortran_dir_reexported_from_package() -> None:
    assert preserf.get_fortran_dir() == get_fortran_dir()


def test_get_cmake_helper_location() -> None:
    helper = get_cmake_helper()
    assert helper.parent == get_fortran_dir() / "cmake"
    assert helper.name == "PreserfFortran.cmake"
    assert helper.is_file()


def test_get_cmake_helper_reexported_from_package() -> None:
    assert preserf.get_cmake_helper() == get_cmake_helper()
