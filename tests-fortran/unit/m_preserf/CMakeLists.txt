add_executable(preserf_fortran_test_minimal test_minimal.f90)
target_link_libraries(preserf_fortran_test_minimal PRIVATE preserf_fortran)

# CMake's Fortran_STANDARD / Fortran_STANDARD_REQUIRED target
# properties do NOT propagate from the linked library to executables,
# so the same F2008 requirement that the preserf_fortran library
# carries has to be repeated here. test_minimal.f90 uses F2008
# constructs (BLOCK, ERROR STOP, deferred-length character) that
# would otherwise fail on compilers whose default dialect is older
# than F2008.
set_target_properties(preserf_fortran_test_minimal PROPERTIES
    Fortran_STANDARD 2008
    Fortran_STANDARD_REQUIRED ON
)
# Belt-and-braces for gfortran (see top-level CMakeLists.txt note):
# CMake 3.28 doesn't translate Fortran_STANDARD into a `-std=` flag
# for gfortran, so we add it explicitly.
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(preserf_fortran_test_minimal PRIVATE -std=f2008)
endif()

# Pre-create the output directory and then run the test binary.
# Using `cmake -E make_directory` rather than a shell `mkdir -p` makes
# this portable across Windows/Unix and avoids quoting concerns.
#
# The directory creation is wired as a CTest *fixture* rather than a
# plain DEPENDS edge: DEPENDS only orders tests that are already in the
# selected set, so running just `preserf_fortran_minimal` (e.g. from an
# IDE or via `ctest -R '^preserf_fortran_minimal$'`) would skip the
# setup and hand the binary a non-existent output directory.
# FIXTURES_REQUIRED makes CTest automatically pull in the matching
# FIXTURES_SETUP test whenever the dependent test is run.
add_test(
    NAME preserf_fortran_minimal_setup
    COMMAND ${CMAKE_COMMAND} -E make_directory
            "${CMAKE_CURRENT_BINARY_DIR}/test-output"
)
set_tests_properties(preserf_fortran_minimal_setup PROPERTIES
    FIXTURES_SETUP preserf_fortran_output_dir
)
add_test(
    NAME preserf_fortran_minimal
    COMMAND $<TARGET_FILE:preserf_fortran_test_minimal> "${CMAKE_CURRENT_BINARY_DIR}/test-output"
)
set_tests_properties(preserf_fortran_minimal PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_output_dir
    PASS_REGULAR_EXPRESSION "preserf-fortran: hello-world OK"
    # Match the 60-second cap the Python wrapper applies to the same
    # binary in tests/integration_tests/test_fortran_wire_compat.py, so a
    # netCDF/HDF5 deadlock cannot block ctest indefinitely either.
    TIMEOUT 60
)

# Slice D: the widened ppser_initialize keywords (realtype / rprecision /
# rperturb / mpi_rank). Driven through the same binary via the
# 'init-keywords' scenario argument.
add_test(
    NAME preserf_fortran_init_keywords
    COMMAND $<TARGET_FILE:preserf_fortran_test_minimal>
            "${CMAKE_CURRENT_BINARY_DIR}/test-output" init-keywords
)
set_tests_properties(preserf_fortran_init_keywords PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_output_dir
    PASS_REGULAR_EXPRESSION "preserf-fortran: init-keywords OK"
    TIMEOUT 60
)
