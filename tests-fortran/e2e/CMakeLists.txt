# End-to-end Slice D Phase 4 test: run the preserf preprocessor on a
# `!$SER`-annotated fixture, compile the generated Fortran against the
# helper library, and (via tests/integration_tests/test_preprocessor_e2e.py)
# read the resulting store back. The native ctest below additionally runs
# the binary so `pixi run test-fortran` covers the pipeline too.

# The `preserf` CLI is installed (editable) in the pixi dev environment,
# so it is on PATH during `pixi run build-fortran`. REQUIRED makes the
# configure step fail with a clear message if it is missing rather than
# silently skipping the generated target.
find_program(PRESERF_CLI preserf REQUIRED)

set(_fixture_in ${CMAKE_CURRENT_SOURCE_DIR}/e2e_fixture.f90.in)
# `.F90` (uppercase) so the compiler runs the C preprocessor: the
# generated source carries the `#ifdef SERIALIZE` guards the
# preprocessor emits around every expanded directive.
set(_generated ${CMAKE_CURRENT_BINARY_DIR}/e2e_fixture.F90)

add_custom_command(
    OUTPUT ${_generated}
    COMMAND ${PRESERF_CLI} ${_fixture_in} -o ${_generated}
    DEPENDS ${_fixture_in}
    COMMENT "preserf: expanding !$SER directives in e2e_fixture.f90.in"
    VERBATIM
)

add_executable(preserf_fortran_test_e2e ${_generated})
target_link_libraries(preserf_fortran_test_e2e PRIVATE preserf_fortran)

# SERIALIZE activates the guarded serialization calls; without it every
# expanded directive compiles to nothing and the binary writes no store.
target_compile_definitions(preserf_fortran_test_e2e PRIVATE SERIALIZE)

# Fortran_STANDARD does not propagate from the linked library (see the
# m_preserf test CMakeLists for the same note); repeat it here.
set_target_properties(preserf_fortran_test_e2e PROPERTIES
    Fortran_STANDARD 2008
    Fortran_STANDARD_REQUIRED ON
)
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    # pp_ser-generated calls (e.g. a full 16-arg fs_register_field) are
    # emitted on a single line that exceeds Fortran's 132-column free-form
    # limit. -ffree-line-length-none lifts the limit, matching how
    # Serialbox-preprocessed code is built; without it gfortran truncates
    # the line and the argument list becomes a syntax error.
    target_compile_options(preserf_fortran_test_e2e PRIVATE
        -std=f2008 -cpp -ffree-line-length-none
    )
endif()

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
