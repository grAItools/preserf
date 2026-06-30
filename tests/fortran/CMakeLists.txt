cmake_minimum_required(VERSION 3.20)
project(preserf_fortran_tests
    DESCRIPTION "Native Fortran tests for the preserf helper library"
    LANGUAGES Fortran)

enable_testing()

# Build the runtime library through the SAME shipped CMake helper that the
# e2e test and external consumers use, so the helper's library-build path is
# exercised in CI. The call is idempotent: the e2e subtree calls it again via
# preserf_add_fortran_target(), but the unit subtree below also needs the
# `preserf_fortran` target when e2e is skipped, so define it here up front.
include(${CMAKE_CURRENT_SOURCE_DIR}/../../src/preserf/fortran/cmake/PreserfFortran.cmake)
preserf_fortran_library()

# Recurse into the per-module test subtrees. Each subdir is responsible
# for `add_executable()` + `add_test()` + any CTest fixtures it needs.
add_subdirectory(unit/m_preserf)
# End-to-end: preprocessor -> generated source -> helper -> store.
# The e2e fixture is expanded at build time by the Python `preserf` CLI,
# so it only builds when that CLI is on PATH (true inside the pixi dev
# env). When it is absent — e.g. a Fortran-only build, an IDE configure,
# or a CI job without the Python package — skip the subtree rather than
# hard-failing configure for the whole tree (which would also take down
# the unrelated unit tests above).
find_program(PRESERF_CLI preserf)
if(PRESERF_CLI)
    add_subdirectory(e2e)
else()
    message(STATUS
        "preserf CLI not found on PATH; skipping the e2e test target "
        "(build inside the pixi dev env, or add it to PATH, to enable it)")
endif()
# Future: add_subdirectory(unit/utils_preserf)
#         add_subdirectory(common)
