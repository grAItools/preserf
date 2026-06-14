# PreserfFortranFlags.cmake — single source of truth for the Fortran compiler
# flags preserf's build and the shipped consumer helper require.
#
# preserf's Fortran sources are not portable under a compiler's *default*
# dialect: `m_preserf.F90` instantiates its overload matrix from cpp `#include`
# templates, the preprocessor emits `#ifdef SERIALIZE` guards, and the runtime
# uses Fortran 2008 constructs (BLOCK, ERROR STOP, deferred-length character).
# Each of those needs an explicit compiler flag — the C preprocessor must be
# turned on (it is off by default for a `.F90` on most compilers) and the
# standard pinned to F2008. The exact spelling differs per compiler:
#
#   compiler (CMAKE_Fortran_COMPILER_ID) | F2008 std    | run cpp        | wide lines
#   -------------------------------------|--------------|----------------|---------------------
#   GNU       (gfortran)                 | -std=f2008   | -cpp           | -ffree-line-length-none
#   Intel     (ifort, classic)           | -stand f08   | -fpp           | (no 132-col limit)
#   IntelLLVM (ifx)                      | -stand f08   | -fpp           | (no 132-col limit)
#   NVHPC/PGI (nvfortran)                | -Mstandard   | -Mpreprocess   | (no 132-col limit)
#
# Previously these flags were gated behind `if(... STREQUAL "GNU")`, so a
# non-GNU build got NO required flags and was silently misconfigured (the cpp
# `#include` templates were never expanded). This module instead branches on
# every compiler preserf claims to support and FATAL_ERRORs on an unrecognised
# one — there is no longer a no-flag path (issue #78).

# Resolve the preprocessing/standards/warning flags for the current Fortran
# compiler into <out_var>.
#
#   preserf_fortran_compile_flags(<out_var> [PREPROCESS] [WARNINGS])
#
# PREPROCESS adds the run-the-C-preprocessor flag (needed for any source that
# uses cpp `#include` templates or `#ifdef SERIALIZE` guards). WARNINGS adds
# the compiler's warning set (the library build opts in; consumer targets do
# not, to avoid drowning user code in warnings from generated lines). The
# F2008 standard + wide-line flags are always included.
function(preserf_fortran_compile_flags out_var)
    cmake_parse_arguments(PFCF "PREPROCESS;WARNINGS" "" "" ${ARGN})

    set(_id "${CMAKE_Fortran_COMPILER_ID}")
    set(_flags "")
    set(_preprocess_flag "")
    set(_warning_flags "")

    if(_id STREQUAL "GNU")
        # -ffree-line-length-none lifts gfortran's 132-column free-form limit so
        # a wide macro instantiation / generated call is not truncated.
        set(_flags -std=f2008 -ffree-line-length-none)
        set(_preprocess_flag -cpp)
        set(_warning_flags -Wall -Wextra -fimplicit-none)
    elseif(_id STREQUAL "Intel" OR _id STREQUAL "IntelLLVM")
        # ifort (Intel) and ifx (IntelLLVM) share the classic-Intel flag
        # spelling. ifort's free-form line limit defaults effectively unlimited;
        # no -ffree-line-length-none equivalent is required.
        set(_flags -stand f08)
        set(_preprocess_flag -fpp)
        set(_warning_flags -warn all)
    elseif(_id STREQUAL "NVHPC" OR _id STREQUAL "PGI")
        # nvfortran (and the legacy PGI id) — the production ICON compiler on
        # CSCS, the reason non-GNU support matters here (see #63/#64).
        set(_flags -Mstandard)
        set(_preprocess_flag -Mpreprocess)
        set(_warning_flags -Minform=warn)
    else()
        # Never leave a supported-but-unmapped compiler with no flags: that is
        # exactly the silent misconfiguration this module exists to prevent.
        message(FATAL_ERROR
            "preserf: unsupported Fortran compiler '${_id}'. preserf needs the "
            "C preprocessor enabled and the F2008 standard selected, but no "
            "flag mapping is known for this compiler. Add a branch for it in "
            "cmake/PreserfFortranFlags.cmake (preprocessing + standards flags) "
            "before building.")
    endif()

    if(PFCF_PREPROCESS)
        list(APPEND _flags ${_preprocess_flag})
    endif()
    if(PFCF_WARNINGS)
        list(APPEND _flags ${_warning_flags})
    endif()

    set(${out_var} "${_flags}" PARENT_SCOPE)
endfunction()
