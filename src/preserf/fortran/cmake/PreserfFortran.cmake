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

# Resolve the bundled runtime directory ONCE, here at include time, where
# CMAKE_CURRENT_LIST_DIR reliably points at this module's directory
# (.../fortran/cmake). Inside a function body it would instead resolve to the
# *caller's* list file, so it must be captured at file scope. Stash it in a
# cache variable so the functions below can read it from any directory scope.
get_filename_component(_preserf_fortran_dir "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(PRESERF_FORTRAN_DIR "${_preserf_fortran_dir}"
    CACHE INTERNAL "Directory of the bundled preserf Fortran runtime sources")

# Single source of truth for the per-compiler preprocessing / standards flags.
# It ships beside this helper (same cmake/ dir), so a consumer that includes
# PreserfFortran.cmake from the wheel gets it too. Captured at file scope:
# CMAKE_CURRENT_LIST_DIR points here only at include time, not inside a
# function body.
include("${CMAKE_CURRENT_LIST_DIR}/PreserfFortranFlags.cmake")

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
        set(PFL_FORTRAN_DIR "${PRESERF_FORTRAN_DIR}")
    endif()
    add_subdirectory("${PFL_FORTRAN_DIR}" preserf_fortran_build)
endfunction()

# ----------------------------------------------------------------------------
# preserf_add_fortran_target(<target>
#                            SOURCES <f90> [<f90> ...]
#                            [DEPENDS_GLOB <file> ...]
#                            [PRESERF_CLI <path>])
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
    if(PAT_UNPARSED_ARGUMENTS)
        # Reject stray tokens rather than letting them fall through to
        # add_executable as source files — a misspelled keyword (e.g.
        # DEPENDS instead of DEPENDS_GLOB) would otherwise become a confusing
        # "cannot find source file" build error instead of a clear failure.
        message(FATAL_ERROR
            "preserf_add_fortran_target(${TARGET}): unexpected argument(s): "
            "${PAT_UNPARSED_ARGUMENTS}. Did you misspell SOURCES or DEPENDS_GLOB?")
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

    add_executable(${TARGET} ${_generated_sources})
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
    # preserf-generated calls (e.g. a full fs_register_field) are emitted on a
    # single line that can exceed Fortran's 132-column free-form limit, and the
    # generated `.F90` carries `#ifdef SERIALIZE` guards. PREPROCESS turns on
    # the C preprocessor (`-cpp` / `-fpp` / `-Mpreprocess`); the standards +
    # wide-line flags come with it. Resolved per-compiler so a non-GNU consumer
    # build is not silently left unpreprocessed (issue #78). No WARNINGS here:
    # user code should not inherit preserf's warning set.
    preserf_fortran_compile_flags(_preserf_target_flags PREPROCESS)
    target_compile_options(${TARGET} PRIVATE ${_preserf_target_flags})
endfunction()
