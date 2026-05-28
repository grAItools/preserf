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

# -----------------------------------------------------------------------------
# Slice A-1: read-mode create-or-resolve-and-validate.
#
# Each scenario is driven through the same binary via its scenario
# argument. Positive scenarios assert their "... OK" marker; negative
# scenarios assert the specific abort message via PASS_REGULAR_EXPRESSION
# (which, when set, determines pass/fail from the output regardless of the
# non-zero exit code that `error stop` produces). A scenario that fails to
# abort prints a non-matching line and exits 0, so the regex fails to
# match and the test fails — catching a validation that silently accepts.
# -----------------------------------------------------------------------------

# Positive: read-mode round-trip (also covers sp_000000 → sp_000001).
add_test(
    NAME preserf_fortran_read_roundtrip
    COMMAND $<TARGET_FILE:preserf_fortran_test_minimal>
            "${CMAKE_CURRENT_BINARY_DIR}/test-output" read-roundtrip
)
set_tests_properties(preserf_fortran_read_roundtrip PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_output_dir
    PASS_REGULAR_EXPRESSION "preserf-fortran: read-roundtrip OK"
    TIMEOUT 60
)

# Slice A-2: read-perturb applies bounded multiplicative noise; scale 0 is
# the identity.
add_test(
    NAME preserf_fortran_perturb_roundtrip
    COMMAND $<TARGET_FILE:preserf_fortran_test_minimal>
            "${CMAKE_CURRENT_BINARY_DIR}/test-output" perturb-roundtrip
)
set_tests_properties(preserf_fortran_perturb_roundtrip PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_output_dir
    PASS_REGULAR_EXPRESSION "preserf-fortran: perturb-roundtrip OK"
    TIMEOUT 60
)

# Positive: explicit reference-store read resolves the savepoint under the
# reference serializer (Phase 2).
add_test(
    NAME preserf_fortran_read_ref
    COMMAND $<TARGET_FILE:preserf_fortran_test_minimal>
            "${CMAKE_CURRENT_BINARY_DIR}/test-output" read-ref
)
set_tests_properties(preserf_fortran_read_ref PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_output_dir
    PASS_REGULAR_EXPRESSION "preserf-fortran: read-ref OK"
    TIMEOUT 60
)

# Negative scenarios: each must abort with its specific message.
add_test(
    NAME preserf_fortran_read_bad_dtype
    COMMAND $<TARGET_FILE:preserf_fortran_test_minimal>
            "${CMAKE_CURRENT_BINARY_DIR}/test-output" read-bad-dtype
)
set_tests_properties(preserf_fortran_read_bad_dtype PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_output_dir
    PASS_REGULAR_EXPRESSION "type_id mismatch"
    TIMEOUT 60
)

add_test(
    NAME preserf_fortran_read_bad_dims
    COMMAND $<TARGET_FILE:preserf_fortran_test_minimal>
            "${CMAKE_CURRENT_BINARY_DIR}/test-output" read-bad-dims
)
set_tests_properties(preserf_fortran_read_bad_dims PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_output_dir
    PASS_REGULAR_EXPRESSION "dims mismatch"
    TIMEOUT 60
)

add_test(
    NAME preserf_fortran_read_bad_halo
    COMMAND $<TARGET_FILE:preserf_fortran_test_minimal>
            "${CMAKE_CURRENT_BINARY_DIR}/test-output" read-bad-halo
)
set_tests_properties(preserf_fortran_read_bad_halo PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_output_dir
    PASS_REGULAR_EXPRESSION "halo .iminushalo. mismatch"
    TIMEOUT 60
)

add_test(
    NAME preserf_fortran_read_bad_spname
    COMMAND $<TARGET_FILE:preserf_fortran_test_minimal>
            "${CMAKE_CURRENT_BINARY_DIR}/test-output" read-bad-spname
)
set_tests_properties(preserf_fortran_read_bad_spname PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_output_dir
    PASS_REGULAR_EXPRESSION "savepoint name mismatch"
    TIMEOUT 60
)

add_test(
    NAME preserf_fortran_read_bad_meta_value
    COMMAND $<TARGET_FILE:preserf_fortran_test_minimal>
            "${CMAKE_CURRENT_BINARY_DIR}/test-output" read-bad-meta-value
)
set_tests_properties(preserf_fortran_read_bad_meta_value PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_output_dir
    PASS_REGULAR_EXPRESSION "value mismatch between run and store"
    TIMEOUT 60
)

add_test(
    NAME preserf_fortran_read_bad_meta_typeid
    COMMAND $<TARGET_FILE:preserf_fortran_test_minimal>
            "${CMAKE_CURRENT_BINARY_DIR}/test-output" read-bad-meta-typeid
)
set_tests_properties(preserf_fortran_read_bad_meta_typeid PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_output_dir
    PASS_REGULAR_EXPRESSION "type-id mismatch"
    TIMEOUT 60
)

add_test(
    NAME preserf_fortran_read_bad_xtype
    COMMAND $<TARGET_FILE:preserf_fortran_test_minimal>
            "${CMAKE_CURRENT_BINARY_DIR}/test-output" read-bad-xtype
)
set_tests_properties(preserf_fortran_read_bad_xtype PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_output_dir
    PASS_REGULAR_EXPRESSION "Registry / variable mismatch"
    TIMEOUT 60
)
