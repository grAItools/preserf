add_executable(test_minimal test_minimal.f90)
target_link_libraries(test_minimal PRIVATE preserf_fortran)

# CMake's Fortran_STANDARD / Fortran_STANDARD_REQUIRED target
# properties do NOT propagate from the linked library to executables,
# so the same F2008 requirement that the preserf_fortran library
# carries has to be repeated here. test_minimal.f90 uses F2008
# constructs (BLOCK, ERROR STOP, deferred-length character) that
# would otherwise fail on compilers whose default dialect is older
# than F2008.
set_target_properties(test_minimal PROPERTIES
    Fortran_STANDARD 2008
    Fortran_STANDARD_REQUIRED ON
)
# Belt-and-braces for gfortran (see top-level CMakeLists.txt note):
# CMake 3.28 doesn't translate Fortran_STANDARD into a `-std=` flag
# for gfortran, so we add it explicitly.
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(test_minimal PRIVATE -std=f2008)
endif()

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
    # Match the 60-second cap the Python wrapper applies to the same
    # binary in tests/test_fortran_minimal.py, so a netCDF/HDF5
    # deadlock cannot block ctest indefinitely either.
    TIMEOUT 60
)
