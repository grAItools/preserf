add_executable(test_minimal test_minimal.f90)
target_link_libraries(test_minimal PRIVATE preserf_fortran)

# Pre-create the output directory and then run the test binary.
# Using `cmake -E make_directory` rather than a shell `mkdir -p` makes
# this portable across Windows/Unix and avoids quoting concerns.
add_test(
    NAME fortran_minimal_setup
    COMMAND ${CMAKE_COMMAND} -E make_directory
            "${CMAKE_BINARY_DIR}/test-output"
)
add_test(
    NAME fortran_minimal
    COMMAND $<TARGET_FILE:test_minimal> "${CMAKE_BINARY_DIR}/test-output"
)
set_tests_properties(fortran_minimal PROPERTIES
    DEPENDS fortran_minimal_setup
    PASS_REGULAR_EXPRESSION "preserf-fortran: hello-world OK"
)
