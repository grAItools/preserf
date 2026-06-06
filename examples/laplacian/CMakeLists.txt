# preserf example: build the Laplacian program against the `preserf_fortran`
# helper library. Run from inside the `examples` pixi env (so the `preserf`
# CLI and the Fortran/netcdf toolchain are on PATH): configuring and building
# (`cmake -S . -B build && cmake --build build`) expands the `!$SER`
# directives and compiles the result — no prior `run.sh` step required.
cmake_minimum_required(VERSION 3.20)
project(preserf_example_laplacian LANGUAGES Fortran)

# Consume the SAME CMake helper that ships in the wheel (here by its in-tree
# path, which equals the installed layout). The helper owns the whole
# expand -> compile -> link -> SERIALIZE recipe; this file just calls it, so
# the example cannot drift from what `pip install preserf` users get.
include(${CMAKE_CURRENT_SOURCE_DIR}/../../src/preserf/fortran/cmake/PreserfFortran.cmake)

# Regenerate whenever the input OR the preprocessor implementation changes, so
# an incremental build never compiles a stale expansion. GLOB_RECURSE picks up
# nested CLI modules (e.g. subpackages), and CONFIGURE_DEPENDS re-globs so a
# newly added module is tracked without a manual reconfigure. (An external
# wheel consumer omits this — its installed package is immutable.)
file(GLOB_RECURSE _preserf_cli_sources CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/../../src/preserf/*.py)

preserf_add_fortran_target(laplacian
    SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/laplacian.f90
    DEPENDS_GLOB ${_preserf_cli_sources}
)
