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

target_sources(preserf_fortran PRIVATE
    utils_preserf.f90
    m_preserf.f90
    # Drop-in re-exports of the names Serialbox / pp_ser historically use.
    utils_ppser.f90
    m_serialize.f90
)

# Put .mod files where dependents can find them.
set_target_properties(preserf_fortran PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/modules
    POSITION_INDEPENDENT_CODE ON
)
target_include_directories(preserf_fortran PUBLIC
    $<BUILD_INTERFACE:${CMAKE_BINARY_DIR}/modules>
)

target_link_libraries(preserf_fortran PUBLIC PkgConfig::NETCDF_FORTRAN)

# Reasonable warnings for gfortran; ifort/ifx tolerate the same set.
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(preserf_fortran PRIVATE
        -Wall -Wextra -std=f2008 -fimplicit-none
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
