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
# Fortran_STANDARD_REQUIRED are CMake's compiler-portable way of
# demanding Fortran 2008 — Intel ifort/ifx, NVIDIA nvfortran etc.
# translate them to their own equivalent of `-std=f2008` / `-stand=f08`.
# The previous GNU-only `-std=f2008` flag let non-GNU builds silently
# compile with their default standard, which could mask code that
# needs an F2008 feature.
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

# Reasonable warnings for gfortran.
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(preserf_fortran PRIVATE
        -Wall -Wextra -fimplicit-none
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
