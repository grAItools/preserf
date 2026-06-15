cmake_minimum_required(VERSION 3.20)
# The Fortran runtime version is tracked SEPARATELY from the Python package
# version (src/preserf/__init__.py `__version__`), deliberately. This tree is
# a standalone, independently installable CMake project — built via
# `cmake -S "$(preserf --fortran-dir)"` with no Python interpreter in scope —
# so it cannot read the Python version at configure time without coupling the
# two builds. This VERSION is the single source of truth for the helper's
# own version: it stamps `preserf_version.f90.in` (-> PRESERF_VERSION) and the
# installed CMake package-version file. Bump it in lockstep with the Python
# `__version__` when releasing; keep them numerically aligned (PEP 440
# pre-release suffixes like `.dev0` have no CMake equivalent, so the CMake
# version omits them).
project(preserf_fortran
    VERSION 0.2.0
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

# Single source of truth for the per-compiler preprocessing / F2008 / warning
# flags (GNU + Intel/IntelLLVM + NVHPC/PGI; FATAL_ERROR on anything else, so a
# non-GNU build can never silently get no flags — issue #78).
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/PreserfFortranFlags.cmake)

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
    # docs/adr/0004-fortran-cpp-templates.md). The preprocessing flag
    # (`-cpp` / `-fpp` / `-Mpreprocess`, per compiler) is added below via
    # preserf_fortran_compile_flags(... PREPROCESS).
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
${CMAKE_CURRENT_SOURCE_DIR}/preserf_read_field_perturb_noop.inc;\
${CMAKE_CURRENT_SOURCE_DIR}/preserf_apply_perturb.inc;\
${CMAKE_CURRENT_SOURCE_DIR}/preserf_register_tracer.inc;\
${CMAKE_CURRENT_SOURCE_DIR}/preserf_tracer_io.inc;\
${CMAKE_CURRENT_SOURCE_DIR}/preserf_write_kbuff.inc"
)

# Put .mod files where dependents can find them. Fortran_STANDARD /
# Fortran_STANDARD_REQUIRED set the portable property for any
# CMake/compiler combo that knows how to translate it (recent ifort/
# ifx, nvfortran, future CMake-gfortran integrations) — current
# CMake (3.28) does NOT translate it for gfortran, so we also
# explicitly add the standards flag (`-std=f2008` / per-compiler
# equivalent) below as a fall-back.
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

# Namespaced alias so in-tree consumers (add_subdirectory) can link the same
# `preserf::preserf_fortran` name that `find_package` exposes for the installed
# library — the recipe doesn't change when you switch from a source build to an
# installed package.
add_library(preserf::preserf_fortran ALIAS preserf_fortran)

# Warnings + explicit F2008 standard + the C preprocessor. The
# Fortran_STANDARD property above is a no-op for gfortran in CMake 3.28, so
# the explicit `-std=` (and per-compiler equivalents) here is the working
# enforcement. PREPROCESS turns on the C preprocessor that expands
# m_preserf.F90's `#include` overload templates (`-cpp` / `-fpp` /
# `-Mpreprocess` depending on the compiler); WARNINGS adds the compiler's
# warning set. Resolved per-compiler, never gated to GNU only (issue #78).
preserf_fortran_compile_flags(_preserf_fortran_flags PREPROCESS WARNINGS)
target_compile_options(preserf_fortran PRIVATE ${_preserf_fortran_flags})

# -----------------------------------------------------------------------------
# Installation
# -----------------------------------------------------------------------------
#
# Standalone build-and-install workflow:
#
#     cmake -S "$(preserf --fortran-dir)" -B build
#     cmake --build build --target install
#
# produces a relocatable package — the static library, the compiled Fortran
# `.mod` interface files, and a CMake package config — that a downstream
# project consumes with:
#
#     find_package(preserf_fortran REQUIRED)
#     target_link_libraries(my_app PRIVATE preserf::preserf_fortran)
#
# Only the top-level build (this tree configured directly via `cmake -S`)
# emits install rules. When the tree is pulled in through add_subdirectory()
# — the shipped PreserfFortran.cmake helper, the laplacian example, the native
# tests — the enclosing project owns its own install and we add nothing to it.
# project() sets PROJECT_IS_TOP_LEVEL automatically on CMake >= 3.21; derive it
# by hand for the 3.20 floor this project targets.
if(NOT DEFINED PROJECT_IS_TOP_LEVEL)
    if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
        set(PROJECT_IS_TOP_LEVEL TRUE)
    else()
        set(PROJECT_IS_TOP_LEVEL FALSE)
    endif()
endif()
option(PRESERF_FORTRAN_INSTALL
    "Generate install rules for the preserf_fortran runtime library"
    ${PROJECT_IS_TOP_LEVEL})

if(PRESERF_FORTRAN_INSTALL)
    include(GNUInstallDirs)
    include(CMakePackageConfigHelpers)

    set(_preserf_cmakedir "${CMAKE_INSTALL_LIBDIR}/cmake/preserf_fortran")

    # INSTALL_INTERFACE carries the installed `.mod` location to consumers of
    # the exported target (BUILD_INTERFACE above serves the in-tree build).
    target_include_directories(preserf_fortran PUBLIC
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/preserf_fortran>
    )

    install(TARGETS preserf_fortran
        EXPORT preserf_fortranTargets
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    )

    # Fortran `.mod` files are the compiler-visible interface (the equivalent
    # of C headers) and are compiler- and version-specific: a consumer must
    # build with the same compiler that produced them. Install the whole
    # module output directory alongside the library.
    install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/modules/
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/preserf_fortran
        FILES_MATCHING PATTERN "*.mod"
    )

    # The export set + a namespaced, version-checked package config make the
    # library discoverable via find_package(preserf_fortran).
    install(EXPORT preserf_fortranTargets
        FILE preserf_fortranTargets.cmake
        NAMESPACE preserf::
        DESTINATION ${_preserf_cmakedir}
    )

    configure_package_config_file(
        ${CMAKE_CURRENT_SOURCE_DIR}/cmake/preserf_fortranConfig.cmake.in
        ${CMAKE_CURRENT_BINARY_DIR}/preserf_fortranConfig.cmake
        INSTALL_DESTINATION ${_preserf_cmakedir}
    )
    # COMPATIBILITY is SameMinorVersion, not SameMajorVersion, because the
    # helper is pre-1.0 (major 0). Under SemVer's 0.x convention a minor bump
    # (0.2 -> 0.3) may carry breaking changes, so a major-only match would
    # wrongly advertise every 0.x install as compatible with any other.
    # SameMinorVersion requires both major and minor to agree, so a consumer
    # `find_package(preserf_fortran 0.2)` accepts a 0.2.x install but rejects a
    # 0.3.x one; and, as with every CMake basic version file, the requested
    # version must not exceed the install (0.2.5 is rejected against 0.2.0). We
    # may revisit this once the helper reaches 1.0, when major-version
    # compatibility becomes the SemVer-correct policy.
    write_basic_package_version_file(
        ${CMAKE_CURRENT_BINARY_DIR}/preserf_fortranConfigVersion.cmake
        VERSION ${PROJECT_VERSION}
        COMPATIBILITY SameMinorVersion
    )
    install(FILES
        ${CMAKE_CURRENT_BINARY_DIR}/preserf_fortranConfig.cmake
        ${CMAKE_CURRENT_BINARY_DIR}/preserf_fortranConfigVersion.cmake
        DESTINATION ${_preserf_cmakedir}
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
