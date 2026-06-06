# PreserfFortran.cmake — the shipped CMake integration for preserf.
#
# This module travels inside the installed `preserf` wheel (as
# `preserf/fortran/cmake/PreserfFortran.cmake`) and is also consumed in-tree
# by the laplacian example and the Fortran e2e test, so the recipe users get
# is the same one CI exercises on every run. Discover it from a project with:
#
#     execute_process(COMMAND preserf --cmake-helper
#                     OUTPUT_VARIABLE PRESERF_CMAKE_HELPER
#                     OUTPUT_STRIP_TRAILING_WHITESPACE)
#     include("${PRESERF_CMAKE_HELPER}")
#     preserf_add_fortran_target(my_app SOURCES my_app.f90)
#
# Prerequisites (unchanged from a source checkout): a Fortran compiler,
# `netcdf-fortran` discoverable via pkg-config, and CMake >= 3.20.

# ----------------------------------------------------------------------------
# preserf_fortran_library([FORTRAN_DIR <dir>])
#
# Build the `preserf_fortran` runtime library from the bundled sources.
# Idempotent: a second call is a no-op once the target exists, so multiple
# helper invocations (or an explicit top-level call plus per-target calls)
# never double-add the subdirectory. FORTRAN_DIR defaults to the runtime tree
# this module ships in (../, i.e. the directory holding the library
# CMakeLists.txt).
# ----------------------------------------------------------------------------
function(preserf_fortran_library)
    cmake_parse_arguments(PFL "" "FORTRAN_DIR" "" ${ARGN})
    if(TARGET preserf_fortran)
        return()
    endif()
    if(NOT PFL_FORTRAN_DIR)
        # CMAKE_CURRENT_LIST_DIR is .../fortran/cmake; the library lives in
        # its parent, .../fortran.
        get_filename_component(PFL_FORTRAN_DIR "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
    endif()
    add_subdirectory("${PFL_FORTRAN_DIR}" preserf_fortran_build)
endfunction()

# ----------------------------------------------------------------------------
# preserf_add_fortran_target(<target>
#                            SOURCES <f90> [<f90> ...]
#                            [DEPENDS_GLOB <file> ...]
#                            [PRESERF_CLI <path>]
#                            [<extra plain sources> ...])
#
# Reproduce the whole expand -> compile -> link -> SERIALIZE workflow that a
# preserf consumer would otherwise hand-wire: run the `preserf` CLI to expand
# the `!$SER` directives in each SOURCES file into a generated `.F90`
# (uppercase so the compiler runs the C preprocessor the `#ifdef SERIALIZE`
# guards require), build them into an executable named <target>, link it
# against the `preserf_fortran` runtime, and apply the SERIALIZE definition
# and the F2008 / line-length flags the generated code needs.
#
# DEPENDS_GLOB is an optional extra dependency list for the expansion step.
# In-tree callers pass the preprocessor's own `*.py` sources (so an
# incremental build regenerates when the preprocessor changes); an external
# consumer installing a wheel omits it (the package is immutable and only the
# input file matters).
#
# PRESERF_CLI overrides the CLI location; by default it is found on PATH.
# ----------------------------------------------------------------------------
function(preserf_add_fortran_target TARGET)
    cmake_parse_arguments(PAT "" "PRESERF_CLI" "SOURCES;DEPENDS_GLOB" ${ARGN})

    if(NOT PAT_SOURCES)
        message(FATAL_ERROR "preserf_add_fortran_target(${TARGET}): SOURCES is required")
    endif()

    preserf_fortran_library()

    if(NOT PAT_PRESERF_CLI)
        find_program(PRESERF_CLI preserf REQUIRED)
        set(PAT_PRESERF_CLI "${PRESERF_CLI}")
    endif()

    set(_generated_sources "")
    foreach(_src IN LISTS PAT_SOURCES)
        get_filename_component(_stem "${_src}" NAME_WE)
        get_filename_component(_src_abs "${_src}" ABSOLUTE)
        set(_out "${CMAKE_CURRENT_BINARY_DIR}/${_stem}.F90")
        add_custom_command(
            OUTPUT "${_out}"
            COMMAND "${PAT_PRESERF_CLI}" "${_src_abs}" -o "${_out}"
            DEPENDS "${_src_abs}" ${PAT_DEPENDS_GLOB}
            COMMENT "preserf: expanding !$SER directives in ${_stem}"
            VERBATIM
        )
        list(APPEND _generated_sources "${_out}")
    endforeach()

    add_executable(${TARGET} ${_generated_sources} ${PAT_UNPARSED_ARGUMENTS})
    target_link_libraries(${TARGET} PRIVATE preserf_fortran)

    # SERIALIZE activates the guarded serialization calls; without it every
    # expanded directive compiles to nothing and the binary writes no store.
    target_compile_definitions(${TARGET} PRIVATE SERIALIZE)

    # Fortran_STANDARD does not propagate from the linked library, so repeat
    # it on the consuming target.
    set_target_properties(${TARGET} PROPERTIES
        Fortran_STANDARD 2008
        Fortran_STANDARD_REQUIRED ON
    )
    if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
        # preserf-generated calls (e.g. a full fs_register_field) are emitted
        # on a single line that exceeds Fortran's 132-column free-form limit;
        # -ffree-line-length-none lifts the limit so the line is not truncated.
        # -cpp runs the C preprocessor for the #ifdef SERIALIZE guards.
        target_compile_options(${TARGET} PRIVATE
            -std=f2008 -cpp -ffree-line-length-none
        )
    endif()
endfunction()
