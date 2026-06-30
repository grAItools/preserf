# End-to-end Slice D Phase 4 test: run the preserf preprocessor on a
# `!$SER`-annotated fixture, compile the generated Fortran against the
# helper library, and (via tests/integration_tests/test_preprocessor_e2e.py)
# read the resulting store back. The native ctest below additionally runs
# the binary so `pixi run test-fortran` covers the pipeline too.
#
# Build wiring goes through the SAME shipped CMake helper users get, so the
# integration recipe is continuously exercised and cannot drift. PRESERF_CLI
# is located (non-REQUIRED) by the parent CMakeLists, which only adds this
# subdir when the `preserf` CLI is on PATH; the helper reuses that result.

include(${CMAKE_CURRENT_SOURCE_DIR}/../../../src/preserf/fortran/cmake/PreserfFortran.cmake)

# Regenerate whenever the fixture OR the preprocessor implementation
# changes — otherwise an incremental build would compile a stale .F90 and
# the pipeline test could pass against pre-regression generated code,
# defeating its purpose. CONFIGURE_DEPENDS re-globs so a newly added
# preprocessor module is picked up without a manual reconfigure.
file(GLOB _preserf_cli_sources CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../src/preserf/*.py)

# `e2e_fixture.f90.in` -> NAME_WE `e2e_fixture` -> generated `e2e_fixture.F90`
# (uppercase so the compiler runs the C preprocessor for the `#ifdef
# SERIALIZE` guards the preprocessor emits).
preserf_add_fortran_target(preserf_fortran_test_e2e
    SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/e2e_fixture.f90.in
    DEPENDS_GLOB ${_preserf_cli_sources}
)

add_test(
    NAME preserf_fortran_e2e_setup
    COMMAND ${CMAKE_COMMAND} -E make_directory
            "${CMAKE_CURRENT_BINARY_DIR}/test-output"
)
set_tests_properties(preserf_fortran_e2e_setup PROPERTIES
    FIXTURES_SETUP preserf_fortran_e2e_output_dir
)
add_test(
    NAME preserf_fortran_e2e
    COMMAND $<TARGET_FILE:preserf_fortran_test_e2e> "${CMAKE_CURRENT_BINARY_DIR}/test-output"
)
set_tests_properties(preserf_fortran_e2e PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_e2e_output_dir
    PASS_REGULAR_EXPRESSION "preserf-fortran: e2e OK"
    TIMEOUT 60
)
