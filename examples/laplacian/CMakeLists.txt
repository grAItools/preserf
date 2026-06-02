# preserf example: build the Laplacian program against the `preserf_fortran`
# helper library. Run from inside the `examples` pixi env (so the `preserf`
# CLI and the Fortran/netcdf toolchain are on PATH): configuring and building
# (`cmake -S . -B build && cmake --build build`) expands the `!$SER`
# directives and compiles the result — no prior `run.sh` step required.
cmake_minimum_required(VERSION 3.20)
project(preserf_example_laplacian LANGUAGES Fortran)

# Build the helper library from source (mirrors tests-fortran/). The
# explicit binary subdir keeps its artefacts under this example's build tree.
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../src/preserf-fortran
                 preserf_fortran)

# Expand the !$SER directives at build time via the preserf CLI (mirrors the
# e2e test tree). The generated `build/laplacian.F90` is left in place so it
# can be read alongside the input. The `.F90` (uppercase) extension makes the
# compiler run the C preprocessor, which the emitted `#ifdef SERIALIZE` guards
# require.
find_program(PRESERF_CLI preserf REQUIRED)

set(_input ${CMAKE_CURRENT_SOURCE_DIR}/laplacian.f90)
set(_generated ${CMAKE_CURRENT_BINARY_DIR}/laplacian.F90)

# Regenerate whenever the input OR the preprocessor implementation changes, so
# an incremental build never compiles a stale expansion. GLOB_RECURSE picks up
# nested CLI modules (e.g. subpackages), and CONFIGURE_DEPENDS re-globs so a
# newly added module is tracked without a manual reconfigure.
file(GLOB_RECURSE _preserf_cli_sources CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/../../src/preserf/*.py)

add_custom_command(
    OUTPUT ${_generated}
    COMMAND ${PRESERF_CLI} ${_input} -o ${_generated}
    DEPENDS ${_input} ${_preserf_cli_sources}
    COMMENT "preserf: expanding !$SER directives in laplacian.f90"
    VERBATIM
)

add_executable(laplacian ${_generated})
target_link_libraries(laplacian PRIVATE preserf_fortran)

# SERIALIZE activates the guarded serialization calls; without it every
# expanded directive compiles to nothing and the binary writes no store.
target_compile_definitions(laplacian PRIVATE SERIALIZE)

# Fortran_STANDARD does not propagate from the linked library, so repeat it.
set_target_properties(laplacian PROPERTIES
    Fortran_STANDARD 2008
    Fortran_STANDARD_REQUIRED ON
)
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    # preserf-generated calls (e.g. a full fs_register_field) are emitted on
    # a single line that exceeds Fortran's 132-column free-form limit;
    # -ffree-line-length-none lifts the limit so the line is not truncated.
    target_compile_options(laplacian PRIVATE
        -std=f2008 -cpp -ffree-line-length-none
    )
endif()
