add_executable(test_minimal test_minimal.f90)
target_link_libraries(test_minimal PRIVATE preserf_fortran)

add_test(NAME fortran_minimal
    COMMAND $<TARGET_FILE:test_minimal> "${CMAKE_BINARY_DIR}/test-output"
)
set_tests_properties(fortran_minimal PROPERTIES
    PASS_REGULAR_EXPRESSION "preserf-fortran: hello-world OK"
)
