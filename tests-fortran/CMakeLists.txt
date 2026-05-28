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
add_subdirectory(e2e)
# Future: add_subdirectory(unit/utils_preserf)
#         add_subdirectory(common)
