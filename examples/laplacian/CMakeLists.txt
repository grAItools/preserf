# preserf example: build the preprocessed Laplacian program against the
# `preserf_fortran` helper library.
#
# Unlike the test tree, this CMakeLists compiles a *pre-generated* source:
# `run.sh` runs the `preserf` CLI first (so users can read the expanded
# `build/laplacian.F90`), then configures and builds this project. The
# `.F90` (uppercase) extension makes the compiler run the C preprocessor,
# which the generated `#ifdef SERIALIZE` guards require.
cmake_minimum_required(VERSION 3.20)
project(preserf_example_laplacian LANGUAGES Fortran)

# Build the helper library from source (mirrors tests-fortran/). The
# explicit binary subdir keeps its artefacts under this example's build tree.
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../src/preserf-fortran
                 preserf_fortran)

# run.sh writes the expanded source here before this project is configured.
set(_generated ${CMAKE_CURRENT_BINARY_DIR}/laplacian.F90)

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
