cmake_minimum_required(VERSION 3.20)
project(preserf_fortran_tests
    DESCRIPTION "Native Fortran tests for the preserf helper library"
    LANGUAGES Fortran)

enable_testing()

# Pull in the helper library. We pass an explicit binary subdirectory so
# the library's build artefacts land in a predictable location under the
# tests' build tree (e.g. build/preserf-fortran/preserf_fortran/...).
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../src/preserf-fortran
                 preserf_fortran)

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
