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

# -----------------------------------------------------------------------------
# Per-scenario isolated output directories.
#
# Every scenario gets its OWN output subdirectory under `test-output/<name>`
# rather than sharing a single `test-output` dir keyed only by the per-scenario
# store prefix (`fhello.nc`, `fzarr.zarr`, …). The shared-dir layout was
# race-free only by the convention that no two scenarios pick the same prefix;
# `ctest -j` plus one future shared prefix would let two scenarios clobber each
# other's store. Isolating the directories makes parallel ctest safe regardless
# of prefix choices.
#
# Each scenario's directory is created by its own CTest *fixture* (rather than a
# plain DEPENDS edge): DEPENDS only orders tests already in the selected set, so
# running a single scenario in isolation (e.g. from an IDE or via `ctest -R`)
# would otherwise be handed a non-existent output directory. FIXTURES_REQUIRED
# pulls in the matching FIXTURES_SETUP whenever the scenario is run.
#
# `preserf_scenario_test()` registers a scenario; arguments:
#   NAME      ctest test name (also the output-subdir name).
#   SCENARIO  scenario argument passed to the binary (omit for the default
#             hello-world run, which takes no scenario argument).
#   PASS      PASS_REGULAR_EXPRESSION the run output must match.
# Options:
#   WORKDIR   pin the process CWD to the scenario's output dir (needed by the
#             relative-path resolution scenarios whose `directory` is relative).
# Multi-value:
#   ENVIRONMENT  extra `KEY=VALUE` entries for the run.
#   EXTRA_DIRS   additional subdirectories (relative to the scenario dir) the
#                setup fixture must pre-create (nf90_create does not make parent
#                directories for the relative-path scenarios).
set(_PRESERF_TEST_OUTPUT_ROOT "${CMAKE_CURRENT_BINARY_DIR}/test-output")

function(preserf_scenario_test)
    set(options WORKDIR)
    set(oneValueArgs NAME SCENARIO PASS)
    set(multiValueArgs ENVIRONMENT EXTRA_DIRS)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    set(scenario_dir "${_PRESERF_TEST_OUTPUT_ROOT}/${ARG_NAME}")
    set(setup_name "preserf_fortran_${ARG_NAME}_setup")
    set(fixture_name "preserf_fortran_${ARG_NAME}_dir")

    # Setup fixture: create the scenario's isolated output dir (plus any
    # EXTRA_DIRS the scenario needs to exist up front).
    set(make_dirs "${scenario_dir}")
    foreach(extra IN LISTS ARG_EXTRA_DIRS)
        list(APPEND make_dirs "${scenario_dir}/${extra}")
    endforeach()
    add_test(
        NAME ${setup_name}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${make_dirs}
    )
    set_tests_properties(${setup_name} PROPERTIES FIXTURES_SETUP ${fixture_name})

    # The scenario run itself.
    set(run_command $<TARGET_FILE:preserf_fortran_test_minimal> "${scenario_dir}")
    if(NOT ARG_SCENARIO STREQUAL "")
        list(APPEND run_command "${ARG_SCENARIO}")
    endif()
    add_test(NAME preserf_fortran_${ARG_NAME} COMMAND ${run_command})

    set_tests_properties(preserf_fortran_${ARG_NAME} PROPERTIES
        FIXTURES_REQUIRED ${fixture_name}
        PASS_REGULAR_EXPRESSION "${ARG_PASS}"
        # Match the 60-second cap the Python wrapper applies to the same binary
        # in tests/integration_tests/test_fortran_wire_compat.py, so a
        # netCDF/HDF5 deadlock cannot block ctest indefinitely either.
        TIMEOUT 60
    )
    if(ARG_WORKDIR)
        set_tests_properties(preserf_fortran_${ARG_NAME} PROPERTIES
            WORKING_DIRECTORY "${scenario_dir}")
    endif()
    if(ARG_ENVIRONMENT)
        set_tests_properties(preserf_fortran_${ARG_NAME} PROPERTIES
            ENVIRONMENT "${ARG_ENVIRONMENT}")
    endif()
endfunction()

# Default hello-world run (no scenario argument).
preserf_scenario_test(NAME minimal
    PASS "preserf-fortran: hello-world OK")

# Slice D: the widened ppser_initialize keywords (realtype / rprecision /
# rperturb / mpi_rank).
preserf_scenario_test(NAME init_keywords SCENARIO init-keywords
    PASS "preserf-fortran: init-keywords OK")

# Issue #56 negative: an unrecognised realtype (a typo like 'flaot') must abort
# at the ppser_initialize boundary — mirroring the backend allowlist check —
# with a clear message naming the bad value, before any field is registered.
preserf_scenario_test(NAME realtype_bad SCENARIO realtype-bad
    PASS "unknown realtype")

# Issue #56 positive: the four recognised realtype names (case-insensitive)
# continue to set ppser_realtype / ppser_reallength consistently.
preserf_scenario_test(NAME realtype_valid SCENARIO realtype-valid
    PASS "preserf-fortran: realtype-valid OK")

# Slice E: NCZarr V2 backend selector. backend='nczarr-v2' writes a `.zarr`
# directory store via netcdf-c's NCZarr backend; round-trips one real64 field.
preserf_scenario_test(NAME backend_nczarr SCENARIO backend-nczarr
    PASS "preserf-fortran: backend-nczarr OK")

# Slice E negative: an unknown backend aborts at the ppser_initialize boundary
# (allowlist of 'netcdf4' / 'nczarr-v2').
preserf_scenario_test(NAME backend_bad SCENARIO backend-bad
    PASS "unknown backend")

# Issue #49: the nczarr-v2 backend needs an absolute directory for its file://
# URL, but netcdf4 (and Serialbox) accept a relative directory. So nczarr-v2
# must resolve a relative directory to absolute (against the CWD) rather than
# reject it. The scenario writes + reads a field through the RELATIVE directory
# 'rel_zarr_dir' and asserts the store landed at <CWD>/rel_zarr_dir/frel.zarr.
# WORKDIR pins the CWD to the scenario's output dir so the relative path
# resolves there; EXTRA_DIRS pre-creates rel_zarr_dir under it first
# (nf90_create does not create parent dirs).
preserf_scenario_test(NAME backend_nczarr_relpath SCENARIO backend-nczarr-relpath
    PASS "preserf-fortran: backend-nczarr-relpath OK"
    WORKDIR EXTRA_DIRS rel_zarr_dir)

# Issue #63: regression guard for resolve_abs_dir's getcwd copy loop against the
# nvfortran char()-concat miscompile (see utils_preserf.f90). Round-trips a
# field through a MULTI-SEGMENT relative directory and asserts the store lands
# at exactly <CWD>/resolve_rel_dir/leaf/fres.zarr.
preserf_scenario_test(NAME resolve_relpath SCENARIO resolve-relpath
    PASS "preserf-fortran: resolve-relpath OK"
    WORKDIR EXTRA_DIRS resolve_rel_dir/leaf)

# Slice E negative: the nczarr-v2 URL is raw-concatenated (not URI-encoded like
# the Python reference path), so a path with a URI-significant character
# (space / # / ? / %) must abort rather than emit a bad URL.
preserf_scenario_test(NAME backend_nczarr_badchar SCENARIO backend-nczarr-badchar
    PASS "needs URI-encoding")

# Issue #48: with no explicit backend= argument the backend is resolved from the
# PRESERF_BACKEND env var. PRESERF_BACKEND=nczarr-v2 selects the NCZarr V2
# backend; an explicit backend= still overrides the env var.
preserf_scenario_test(NAME backend_env SCENARIO backend-env
    PASS "preserf-fortran: backend-env OK"
    ENVIRONMENT "PRESERF_BACKEND=nczarr-v2")

# Issue #48 negative: an unknown PRESERF_BACKEND value must abort at the
# ppser_initialize boundary with the same "unknown backend" message.
preserf_scenario_test(NAME backend_env_bad SCENARIO backend-env-bad
    PASS "unknown backend"
    ENVIRONMENT "PRESERF_BACKEND=zarr3")

# Issue #48 (review): a whitespace-only PRESERF_BACKEND is blank after trim and
# must be treated as unset, falling back to the 'netcdf4' default.
preserf_scenario_test(NAME backend_env_blank SCENARIO backend-env-blank
    PASS "preserf-fortran: backend-env-blank OK"
    ENVIRONMENT "PRESERF_BACKEND=   ")

# Issue #48 (review): an explicit backend= passed as a fixed-length character
# variable carries leading/trailing blanks; ppser_resolve_backend must trim and
# adjustl them so a logically valid value is accepted. No PRESERF_BACKEND set.
preserf_scenario_test(NAME backend_arg_padded SCENARIO backend-arg-padded
    PASS "preserf-fortran: backend-arg-padded OK")

# issue #46 positive: opt-in compression chunks + deflates the field
# variable (NetCDF4) and round-trips it losslessly through the Fortran
# helper. The Python wire-compat test additionally asserts the on-disk
# deflate filter and the file-size reduction.
add_test(
    NAME preserf_fortran_compression
    COMMAND $<TARGET_FILE:preserf_fortran_test_minimal>
            "${CMAKE_CURRENT_BINARY_DIR}/test-output" compression
)
set_tests_properties(preserf_fortran_compression PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_output_dir
    PASS_REGULAR_EXPRESSION "preserf-fortran: compression OK"
    TIMEOUT 60
)

# issue #46 negative: a compression level outside 0..9 aborts at the
# ppser_initialize boundary before any store is opened.
add_test(
    NAME preserf_fortran_compression_bad_level
    COMMAND $<TARGET_FILE:preserf_fortran_test_minimal>
            "${CMAKE_CURRENT_BINARY_DIR}/test-output" compression-bad-level
)
set_tests_properties(preserf_fortran_compression_bad_level PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_output_dir
    PASS_REGULAR_EXPRESSION "compression level"
    TIMEOUT 60
)

# issue #46 negative: compression is NetCDF4-only in v1, so combining it
# with the nczarr-v2 backend aborts up front rather than writing a store
# that cannot be read back (NCZarr deflate filter plugin may be absent).
add_test(
    NAME preserf_fortran_compression_nczarr
    COMMAND $<TARGET_FILE:preserf_fortran_test_minimal>
            "${CMAKE_CURRENT_BINARY_DIR}/test-output" compression-nczarr
)
set_tests_properties(preserf_fortran_compression_nczarr PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_output_dir
    PASS_REGULAR_EXPRESSION "compression is not supported with the 'nczarr-v2' backend"
    TIMEOUT 60
)

# issue #46 negative: the same rejection must fire when nczarr-v2 is selected
# via the PRESERF_BACKEND env var (no backend= argument), since the guard
# checks the resolved backend — not only an explicit argument.
add_test(
    NAME preserf_fortran_compression_nczarr_env
    COMMAND $<TARGET_FILE:preserf_fortran_test_minimal>
            "${CMAKE_CURRENT_BINARY_DIR}/test-output" compression-nczarr-env
)
set_tests_properties(preserf_fortran_compression_nczarr_env PROPERTIES
    FIXTURES_REQUIRED preserf_fortran_output_dir
    ENVIRONMENT "PRESERF_BACKEND=nczarr-v2"
    PASS_REGULAR_EXPRESSION "compression is not supported with the 'nczarr-v2' backend"
    TIMEOUT 60
)

# -----------------------------------------------------------------------------
# Slice A-1: read-mode create-or-resolve-and-validate.
#
# Positive scenarios assert their "... OK" marker; negative scenarios assert the
# specific abort message via PASS_REGULAR_EXPRESSION (which, when set, determines
# pass/fail from the output regardless of the non-zero exit code that
# `error stop` produces). A scenario that fails to abort prints a non-matching
# line and exits 0, so the regex fails to match and the test fails — catching a
# validation that silently accepts.
# -----------------------------------------------------------------------------

# Positive: read-mode round-trip (also covers sp_000000 -> sp_000001).
preserf_scenario_test(NAME read_roundtrip SCENARIO read-roundtrip
    PASS "preserf-fortran: read-roundtrip OK")

# Issue #32: `mode` is optional on ppser_initialize for pp_ser / Serialbox
# `!$SER INIT` drop-in compatibility. Covers the default-write path, the derived
# read path (set_mode(1) + omitted mode), and read-perturb preservation.
preserf_scenario_test(NAME init_default_mode SCENARIO init-default-mode
    PASS "preserf-fortran: init-default-mode OK")

# Issue #42: in write mode ppser_initialize must create the output `directory`
# (mkdir -p semantics) before nf90_create, matching Serialbox.
preserf_scenario_test(NAME init_mkdir SCENARIO init-mkdir
    PASS "preserf-fortran: init-mkdir OK")

# Slice B: full type-coverage matrix. One round-trip per dtype at rank 1, plus a
# 0-D scalar, a 4-D field, and a real32 read-perturb.
preserf_scenario_test(NAME type_matrix SCENARIO type-matrix
    PASS "preserf-fortran: type-matrix OK")

# Slice B Phase 3: write one field of every (dtype, rank) combination plus array
# metainfo, for the Python cross-language matrix assertions.
preserf_scenario_test(NAME wire_matrix SCENARIO wire-matrix
    PASS "preserf-fortran: wire-matrix OK")

# Slice A-2: read-perturb applies bounded multiplicative noise; scale 0 is the
# identity.
preserf_scenario_test(NAME perturb_roundtrip SCENARIO perturb-roundtrip
    PASS "preserf-fortran: perturb-roundtrip OK")

# Issue #39: 5-arg fs_read_field perturb overloads for integer and logical. The
# perturb argument is accepted but ignored. Covers int32, int64, logical 0-4.
preserf_scenario_test(NAME perturb_noop SCENARIO perturb-noop
    PASS "preserf-fortran: perturb-noop OK")

# Positive: explicit reference-store read resolves the savepoint under the
# reference serializer (Phase 2).
preserf_scenario_test(NAME read_ref SCENARIO read-ref
    PASS "preserf-fortran: read-ref OK")

# Negative scenarios: each must abort with its specific message.
preserf_scenario_test(NAME read_bad_dtype SCENARIO read-bad-dtype
    PASS "type_id mismatch")
preserf_scenario_test(NAME read_bad_dims SCENARIO read-bad-dims
    PASS "dims mismatch")
preserf_scenario_test(NAME read_bad_halo SCENARIO read-bad-halo
    PASS "halo .iminushalo. mismatch")
preserf_scenario_test(NAME read_bad_spname SCENARIO read-bad-spname
    PASS "savepoint name mismatch")
preserf_scenario_test(NAME read_bad_meta_value SCENARIO read-bad-meta-value
    PASS "value mismatch between run and store")
preserf_scenario_test(NAME read_bad_meta_typeid SCENARIO read-bad-meta-typeid
    PASS "type-id mismatch")
preserf_scenario_test(NAME read_bad_xtype SCENARIO read-bad-xtype
    PASS "Registry / variable mismatch")

# Slice C Phase 1: tracers. Registers three real64 tracers and writes them
# through every TRACER entry point; the Python cross-language test asserts the
# on-disk descriptors and data. The native run confirms the writer completes.
preserf_scenario_test(NAME tracers SCENARIO tracers
    PASS "preserf-fortran: tracers OK")

# Slice C Phase 1 read-mode: re-open a tracer store read-only and validate each
# /_tracers descriptor via fs_RegisterAllTracers (no def_var on the read handle).
preserf_scenario_test(NAME tracers_roundtrip SCENARIO tracers-roundtrip
    PASS "preserf-fortran: tracers-roundtrip OK")

# Slice C Phase 2: DATA_KBUFF. Writes a 3-D and a 2-D field one vertical level at
# a time via fs_write_kbuff; the Python cross-language test asserts the assembled
# fields. The native run confirms the buffer flush completes.
preserf_scenario_test(NAME kbuff SCENARIO kbuff
    PASS "preserf-fortran: kbuff OK")

# Slice C Phase 3: OPTION. fs_Option(verbosity=2) sets the runtime knob and
# records the _preserf_option_verbosity root attribute; the Python
# cross-language test reads it back.
preserf_scenario_test(NAME option SCENARIO option
    PASS "preserf-fortran: option OK")

# Slice C: "last write wins" — a second tracer write omitting timelevel must
# clear a timelevel set by an earlier write at the same savepoint.
preserf_scenario_test(NAME tracer_tl_overwrite SCENARIO tracer-tl-overwrite
    PASS "preserf-fortran: tracer-tl-overwrite OK")

# Slice C negative scenarios: each must abort with its specific message.
preserf_scenario_test(NAME tracers_multi_session SCENARIO tracers-multi-session
    PASS "preserf-fortran: tracers-multi-session OK")
preserf_scenario_test(NAME tracers_bad_dup SCENARIO tracers-bad-dup
    PASS "is already registered")
preserf_scenario_test(NAME tracers_bad_namelen SCENARIO tracers-bad-namelen
    PASS "exceeds 64 characters")
preserf_scenario_test(NAME tracers_bad_name SCENARIO tracers-bad-name
    PASS "is not registered")
preserf_scenario_test(NAME tracers_bad_idx SCENARIO tracers-bad-idx
    PASS "is out of range")
preserf_scenario_test(NAME tracers_bad_reorder SCENARIO tracers-bad-reorder
    PASS "tracer_index mismatch")
preserf_scenario_test(NAME tracers_bad_range SCENARIO tracers-bad-range
    PASS "descending index range")
preserf_scenario_test(NAME kbuff_bad_namelen SCENARIO kbuff-bad-namelen
    PASS "exceeds 64 characters")
preserf_scenario_test(NAME kbuff_bad_order SCENARIO kbuff-bad-order
    PASS "expected level 2 but got 3")
preserf_scenario_test(NAME kbuff_bad_shape SCENARIO kbuff-bad-shape
    PASS "inconsistent slice shape")

# Issue #43: fs_write_field auto-registers a field on its first write, matching
# Serialbox, so pp_ser !$SER DATA / !$SER ACCDATA call sites (which never emit
# !$SER REGISTER) write without an explicit registration. The scenario writes
# representative dtypes / ranks with no prior fs_register_field, then re-opens
# read-only and round-trips them back.
preserf_scenario_test(NAME autoregister SCENARIO autoregister
    PASS "preserf-fortran: autoregister OK")

# A direct fs_write_field against a read-mode serializer on an unregistered
# field must abort with the friendly "call fs_register_field first" message
# rather than a raw netCDF def_var error from auto-registration.
preserf_scenario_test(NAME write_readmode_unregistered SCENARIO write-readmode-unregistered
    PASS "call fs_register_field first")

# The gate keys on the handle's `writable` flag, not the global
# ppser_get_mode(): a read-only handle with the global mode forced to 0 (write)
# must still abort rather than reach auto-registration.
preserf_scenario_test(NAME write_readhandle_mode0_unregistered SCENARIO write-readhandle-mode0-unregistered
    PASS "call fs_register_field first")

# The converse: a writable handle must auto-register a first write regardless of
# the global mode. Open 'w', force global mode to 1 (read), write an
# unregistered field, and assert it round-trips losslessly.
preserf_scenario_test(NAME write_writable_mode1_autoregister SCENARIO write-writable-mode1-autoregister
    PASS "preserf-fortran: writable-mode1 autoregister OK")

# Re-registering a field with identical metadata is idempotent (Serialbox
# parity): the duplicate REGISTER validates and returns instead of aborting on a
# duplicate def_var (NC_ENAMEINUSE).
preserf_scenario_test(NAME register_duplicate_ok SCENARIO register-duplicate-ok
    PASS "preserf-fortran: register-duplicate-ok OK")

# Re-registering a field with a different shape aborts with a clear
# "re-registered field" mismatch rather than a duplicate def_var crash.
preserf_scenario_test(NAME register_duplicate_mismatch SCENARIO register-duplicate-mismatch
    PASS "re-registered field")

# A first-write auto-register records zero halos; a later REGISTER that declares
# a non-zero halo must surface the dropped halo as a "re-registered field" halo
# mismatch.
preserf_scenario_test(NAME register_after_autowrite_halo SCENARIO register-after-autowrite-halo
    PASS "re-registered field")

# REGISTER reaching the create path on a read-only handle (global write mode,
# non-writable handle) must abort with a clear "opened read-only" message, not a
# raw netCDF def_var error.
preserf_scenario_test(NAME register_readonly_handle SCENARIO register-readonly-handle
    PASS "opened read-only")

# Auto-registering a zero-size array (a 0 runtime extent) must abort with a clear
# message rather than write a malformed entry / NF90_UNLIMITED dim.
preserf_scenario_test(NAME autoregister_zero_extent SCENARIO autoregister-zero-extent
    PASS "non-positive extent")

# -----------------------------------------------------------------------------
# Scenarios that landed on main after this branch was cut (issues #67, #98, #99,
# #72). Registered through the same per-scenario-isolated helper as the rest.

# Issue #67/#94: ppser_initialize called twice in one process auto-closes the
# previous session (flushing its savepoint count and releasing the handle)
# instead of leaking the handle and abandoning the store.
preserf_scenario_test(NAME reinit_lifecycle SCENARIO reinit-lifecycle
    PASS "preserf-fortran: reinit-lifecycle OK")

# Issue #98: a second fs_RegisterAllTracers in one write session is idempotent
# (inq-guard before def_var) rather than aborting on NC_ENAMEINUSE.
preserf_scenario_test(NAME tracers_register_twice SCENARIO tracers-register-twice
    PASS "preserf-fortran: tracers-register-twice OK")

# Issue #99: tracer and k-buffer reads validate the on-disk xtype / dims before
# nf90_get_var, so a mutated store aborts instead of silently coercing.
preserf_scenario_test(NAME tracer_read_bad_xtype SCENARIO tracer-read-bad-xtype
    PASS "Registry / variable mismatch")
preserf_scenario_test(NAME kbuff_read_bad_xtype SCENARIO kbuff-read-bad-xtype
    PASS "Registry / variable mismatch")
preserf_scenario_test(NAME kbuff_read_bad_extent SCENARIO kbuff-read-bad-extent
    PASS "dimension lengths disagree")

# Issue #72: int64 k-buffer size/offset arithmetic; the kbuff-offset scenario
# pins the column-major layout the int64 offset formula must preserve.
preserf_scenario_test(NAME kbuff_offset SCENARIO kbuff-offset
    PASS "preserf-fortran: kbuff-offset OK")

# Issue #81 item 2: a NaN metainfo value (scalar real32/real64 + a real64
# array) must round-trip without a spurious read-mode "value mismatch"
# (NaN /= NaN previously aborted a perfect round-trip).
preserf_scenario_test(NAME nan_metainfo_roundtrip SCENARIO nan-metainfo-roundtrip
    PASS "preserf-fortran: nan-metainfo-roundtrip OK")

# Issue #81 item 4: with an explicit directory_ref / prefix_ref, DATA, TRACER,
# and KBUFF reads must all resolve against the reference store (the primary
# holds wrong values; the read must recover the reference values).
preserf_scenario_test(NAME explicit_ref_tracer_kbuff SCENARIO explicit-ref-tracer-kbuff
    PASS "preserf-fortran: explicit-ref-tracer-kbuff OK")
