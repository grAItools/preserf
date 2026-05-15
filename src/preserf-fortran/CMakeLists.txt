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
    ${CMAKE_BINARY_DIR}/generated/preserf_version.f90
    @ONLY
)

target_sources(preserf_fortran PRIVATE
    ${CMAKE_BINARY_DIR}/generated/preserf_version.f90
    utils_preserf.f90
    m_preserf.f90
    # Drop-in re-exports of the names Serialbox / pp_ser historically use.
    utils_ppser.f90
    m_serialize.f90
)

# Put .mod files where dependents can find them. Fortran_STANDARD /
# Fortran_STANDARD_REQUIRED set the portable property for any
# CMake/compiler combo that knows how to translate it (recent ifort/
# ifx, nvfortran, future CMake-gfortran integrations) — current
# CMake (3.28) does NOT translate it for gfortran, so we also
# explicitly add `-std=f2008` in the GNU block below as a fall-back.
set_target_properties(preserf_fortran PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/modules
    POSITION_INDEPENDENT_CODE ON
    Fortran_STANDARD 2008
    Fortran_STANDARD_REQUIRED ON
)
target_include_directories(preserf_fortran PUBLIC
    $<BUILD_INTERFACE:${CMAKE_BINARY_DIR}/modules>
)

target_link_libraries(preserf_fortran PUBLIC PkgConfig::NETCDF_FORTRAN)

# Warnings + explicit F2008 standard for gfortran (the
# Fortran_STANDARD property above is a no-op for gfortran in
# CMake 3.28; this is the working enforcement).
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(preserf_fortran PRIVATE
        -Wall -Wextra -fimplicit-none -std=f2008
    )
endif()

# -----------------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------------
option(PRESERF_FORTRAN_BUILD_TESTS "Build preserf-fortran tests" ON)
if(PRESERF_FORTRAN_BUILD_TESTS)
    enable_testing()
    add_subdirectory(test)
endif()
