cmake_minimum_required(VERSION 3.20)
project(preserf_fortran
    VERSION 0.1.0
    DESCRIPTION "Fortran helper modules for preserf"
    LANGUAGES Fortran)

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------
#
# netcdf-fortran does not ship a CMake config or a FindNetCDF module by default.
# pkg-config is the most portable way to discover its compile/link flags;
# distributions ship a `netcdf-fortran.pc` and `nf-config` alongside the library.
#
find_package(PkgConfig REQUIRED)
pkg_check_modules(NETCDF_FORTRAN REQUIRED IMPORTED_TARGET netcdf-fortran)

# -----------------------------------------------------------------------------
# Library
# -----------------------------------------------------------------------------
add_library(preserf_fortran)

# Single source of truth for the helper version: stamp the CMake
# project version into a generated Fortran module that
# `utils_preserf.f90` consumes when writing `_preserf_writer`.
configure_file(
    preserf_version.f90.in
    ${CMAKE_CURRENT_BINARY_DIR}/generated/preserf_version.f90
    @ONLY
)

target_sources(preserf_fortran PRIVATE
    ${CMAKE_CURRENT_BINARY_DIR}/generated/preserf_version.f90
    utils_preserf.f90
    # m_preserf.F90 (uppercase) is compiled through the C preprocessor:
    # the field / read-perturb / array-metainfo overload matrix is
    # generated from `#include` templates (see
    # docs/adr/0004-fortran-cpp-templates.md). The `-cpp` flag is added in
    # the GNU block below.
    m_preserf.F90
    # Drop-in re-exports of the names Serialbox / pp_ser historically use.
    utils_ppser.f90
    m_serialize.f90
)

# m_preserf.F90 pulls in the preserf_*.inc overload templates via the C
# preprocessor. CMake's Fortran dependency scanner only follows Fortran
# INCLUDE / USE, not cpp `#include`, so without this an incremental build
# would not rebuild m_preserf.F90 when a template changes and would reuse a
# stale object. Register the templates explicitly as OBJECT_DEPENDS.
set_source_files_properties(m_preserf.F90 PROPERTIES OBJECT_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/preserf_write_field.inc;\
${CMAKE_CURRENT_SOURCE_DIR}/preserf_write_field_logical.inc;\
${CMAKE_CURRENT_SOURCE_DIR}/preserf_read_field.inc;\
${CMAKE_CURRENT_SOURCE_DIR}/preserf_read_field_logical.inc;\
${CMAKE_CURRENT_SOURCE_DIR}/preserf_read_field_perturb.inc;\
${CMAKE_CURRENT_SOURCE_DIR}/preserf_apply_perturb.inc"
)

# Put .mod files where dependents can find them. Fortran_STANDARD /
# Fortran_STANDARD_REQUIRED set the portable property for any
# CMake/compiler combo that knows how to translate it (recent ifort/
# ifx, nvfortran, future CMake-gfortran integrations) — current
# CMake (3.28) does NOT translate it for gfortran, so we also
# explicitly add `-std=f2008` in the GNU block below as a fall-back.
set_target_properties(preserf_fortran PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/modules
    POSITION_INDEPENDENT_CODE ON
    Fortran_STANDARD 2008
    Fortran_STANDARD_REQUIRED ON
)
target_include_directories(preserf_fortran PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/modules>
)

target_link_libraries(preserf_fortran PUBLIC PkgConfig::NETCDF_FORTRAN)

# Warnings + explicit F2008 standard for gfortran (the
# Fortran_STANDARD property above is a no-op for gfortran in
# CMake 3.28; this is the working enforcement).
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(preserf_fortran PRIVATE
        # -cpp preprocesses m_preserf.F90's `#include` overload templates.
        # -ffree-line-length-none lifts the 132-column free-form limit so a
        # macro instantiation that expands wide does not get truncated
        # (same rationale as the e2e target).
        -Wall -Wextra -fimplicit-none -std=f2008 -cpp -ffree-line-length-none
    )
endif()

# -----------------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------------
#
# Tests live under ../../tests-fortran/ and are driven from there (the
# tests-fortran/ tree is the entry point passed to `cmake -S`; it pulls
# this library in via add_subdirectory). This file builds only the
# library, regardless of whether it is the top-level project or vendored.
